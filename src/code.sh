#!/bin/bash

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

main() {

  echo "Step 1: download input tars and unpack them"
  # either a run archive or a sentinel record must be provided as an input
  if [ -n "${run_archive}" ]; then
    for i in ${!run_archive_name[@]}; do
      # check format and decompress
      name="${run_archive_name[${i}]}"

      if [[ "${name}" == *.tar.gz ]] || [[ "${name}" == *.tgz ]]; then
        dx cat "${run_archive[${i}]}" | tar zxf - --no-same-owner

      elif [ "${name}" == *.zip ]; then
        dx download "${run_archive[$i]}" -o "${name}"
        unzip "${name}"

      elif [ "${name}" == *.rar ]; then
        dx download "${run_archive[${i}]}" -o "${name}"
        unrar x "${name}"

      else
        dx-jobutil-report-error "ERROR: The input was not a .rar, .zip, .tar.gz or .tgz"

      fi
    done

  elif [ -n "${upload_sentinel_record}" ]; then
    # get the tar.gzs linked to the record and uncompress them in the order they were created
    file_ids=$(dx get_details "${upload_sentinel_record}" | jq -r '.tar_file_ids | .[]')

    # This has to be done in order, so no parallelization

    #Tarball are not in the correct order
    declare -A files_names_ids

    for id in $(echo ${file_ids}); do name=$(dx describe ${id} --name); files_names_ids[${name}]=${id}; echo ${name} >> files_names.tmp; done
    sort files_names.tmp > files_names.txt

    for name in $(cat files_names.txt); do
      # format check and uncompress
      file_id=${files_names_ids[${name}]}
      extn="${name##*.}"

      if [[ "${extn}" == "gz" ]]; then
        dx cat ${file_id} | tar xzf - --no-same-owner -C ./

      elif [[ "${extn}" == "tar" ]]; then
        dx cat ${file_id} | tar xf - --no-same-owner -C ./

      else
          dx-jobutil-report-error "The upload_sentinel_record doesn't contain tar or tar.gzs"
      fi

    done
    rm files_names.t*

  else
    dx-jobutil-report-error "Please provide either a compressed RUN folder or an upload Sentinel Record as an input"
  fi

  echo "Step 2: locate Data folder and SampleSheet.csv"
  # Locate the unpacked Data files 
  # check for the presence/location of the run folder
  location_of_data=$(find . -type d -name "Data")

  if [ "${location_of_data}" == "" ]; then
    dx-jobutil-report-error "The Data folder could not be found."
  fi

  location_of_runarchive=${location_of_data%/Data}

  # Find the SampleSheet.csv
  # check if the samplesheet is provided as an input, if so, download it
  if [ "${sample_sheet}" != "" ]; then
    dx download -f "${sample_sheet}" -o SampleSheet.csv

  # make sure the sample sheet is present in the correct location as the tool would expect
  if [ "${location_of_runarchive}" != "." ]; then
    mv SampleSheet.csv "${location_of_runarchive}"/SampleSheet.csv
  fi
  
  # check if its present in the run folder
  elif [ -f ${location_of_runarchive}/*heet.csv ]; then
    mv ${location_of_runarchive}/*heet.csv "${location_of_runarchive}"/SampleSheet.csv
    echo "The SampleSheet.csv was found in the run directory."

  # if not, check if its present along with the sentinel record
  # get the samplesheet id from the sentinel record and download it
  elif [ -n "${upload_sentinel_record}" ]; then
    sample_sheet_id=$(dx get_details "${upload_sentinel_record}" | jq -r .samplesheet_file_id)

    if [ "${sample_sheet_id}" ==  "null"  ]; then
      dx-jobutil-report-error "Samplesheet was not found." AppInternalError
    else
      dx download -f "${sample_sheet_id}" -o SampleSheet.csv
    fi

  else
      dx-jobutil-report-error "No SampleSheet could be found."
  fi

  cd "${location_of_runarchive}"
  # dos2unix SampleSheet.csv

  echo "Step 3: build and run bcl2fastq" # from asset
  # Load the bcl2fastq from root where it was placed from the asset bundle
  dpkg -i /bcl2fastq*.deb
  bcl2fastq $advanced_opts

  # get run ID to prefix the summary and stats files
  run_id=$(cat RunInfo.xml | grep "Run Id" | cut -d'"' -f2)
  echo $run_id

  echo "Step 4: upload fastqs and run statistics"
  # look for fastq files and upload them
  outdir=/home/dnanexus/out/output && mkdir -p ${outdir}

  # concatenate all the lane.html and laneBarcode.html files
  all_barcodes=''
  for file in $(find Data/Intensities/BaseCalls/Reports/ -name "laneBarcode.html"); do all_barcodes="${all_barcodes} ${file}"; done
  cat ${all_barcodes} > all_barcodes.html
  cat all_barcodes.html | grep -v "hide" > all_barcodes_edited.html
  mv all_barcodes_edited.html Data/Intensities/BaseCalls/Reports/${run_id}_all_barcodes.html

  all_lanes=''
  for file in $(find Data/Intensities/BaseCalls/Reports/ -name "lane.html"); do all_lanes="${all_lanes} ${file}"; done
  cat ${all_lanes} > all_lanes.html
  cat all_lanes.html | grep -v "show" > all_lanes_edited.html
  mv all_lanes_edited.html Data/Intensities/BaseCalls/Reports/${run_id}_all_lanes.html

  # remove bcl files and their folders
  mkdir bcls
  mv Data/Intensities/BaseCalls/L* bcls/

  mv Data ${outdir}/
  mv S* ${outdir}/ # SampleSheet.csv and SequenceComplete.txt

  # Upload outputs
  dx-upload-all-outputs

  echo "DONE!"
}