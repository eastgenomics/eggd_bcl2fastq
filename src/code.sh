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
        exit 1
      fi
    done

  elif [ -n "${upload_sentinel_record}" ]; then
    # get the tar.gzs linked to the record and uncompress them in the order they were created
    file_ids=$(dx get_details "${upload_sentinel_record}" | jq -r '.tar_file_ids | .[]')

    # check first tar to see if they are compressed (should be)
    first_tar=($file_ids)
    name=$(dx describe --json $first_tar | jq -r '.name')
    extn="${name##*.}"

    threads=$(nproc --all )  # control how many downloads to open in parallel

    SECONDS=0
    if [[ "${extn}" == "gz" ]]; then
      echo $file_ids | sed 's/ /\n/g' | xargs -P ${threads} -n1 -I{} sh -c "dx cat {} | tar xzf - --no-same-owner --absolute-names -C ./"
    elif [[ "${extn}" == "tar" ]]; then
      echo $file_ids | sed 's/ /\n/g' | xargs -P ${threads} -n1 -I{} sh -c "dx cat {} | tar xf - --no-same-owner --absolute-names -C ./"
    else
        dx-jobutil-report-error "The upload_sentinel_record doesn't contain tar or tar.gzs"
        exit 1
    fi
    duration=$SECONDS

    echo "Donwloading and unpackaing took $(($duration / 60))m$(($duration % 60))s."

  else
    dx-jobutil-report-error "Please provide either a compressed RUN folder or an upload Sentinel Record as an input"
  fi

  echo "Step 2: locate Data folder and SampleSheet.csv"
  # Locate the unpacked Data files
  # check for the presence/location of the run folder
  location_of_data=$(find . -type d -name "Data")

  if [ "${location_of_data}" == "" ]; then
    dx-jobutil-report-error "The Data folder could not be found."
    exit 1
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

  # Sample sheet not given, try finding it in the run folder, use regex to account for anything named differently
  # e.g. run-id_SampleSheet.csv, sample_sheet.csv, Sample Sheet.csv, sampleSheet.csv etc.
  elif [[ $(find ./ -regextype posix-extended  -iregex '.*sample[-_ ]?sheet.csv$') ]]; then
    samplesheet=$(find ./ -regextype posix-extended  -iregex '.*sample[-_ ]?sheet.csv$')
    echo "found sample sheet: $samplesheet in run directory"
    mv ${samplesheet} "${location_of_runarchive}"/SampleSheet.csv

  # if not, check if its present along with the sentinel record
  # get the samplesheet id from the sentinel record and download it
  elif [ -n "${upload_sentinel_record}" ]; then
    sample_sheet_id=$(dx get_details "${upload_sentinel_record}" | jq -r .samplesheet_file_id)

    if [ "${sample_sheet_id}" ==  "null"  ]; then
      dx-jobutil-report-error "Samplesheet was not found." AppInternalError
      exit 1
    else
      dx download -f "${sample_sheet_id}" -o SampleSheet.csv
    fi

  else
      dx-jobutil-report-error "No SampleSheet could be found."
      exit 1
  fi

  cd "${location_of_runarchive}"

  echo "Step 3: build and run bcl2fastq" # from asset
  # Load the bcl2fastq from root where it was placed from the asset bundle
  dpkg -i /bcl2fastq*.deb

  # run bcl2fastq with advanced options if given (default: -l INFO)
  /usr/bin/time -v bcl2fastq $advanced_opts

  # get run ID to prefix the summary and stats files
  run_id=$(cat RunInfo.xml | grep "Run Id" | cut -d'"' -f2)
  echo $run_id

  echo "Step 4: upload fastqs and run statistics"
  # look for fastq files and upload them

  # upload reports (stats)
  outdir=/home/dnanexus/out/output && mkdir -p ${outdir}

  # concatenate all the laneBarcode.html files into single ${run_id}_all_barcodes.html file
  # this floods the logs so turning off set -x
  echo "Creating combined barcode html files"
  all_barcodes=''
  set +x
  for file in $(find Data/Intensities/BaseCalls/Reports/ -name "laneBarcode.html")
  do
    all_barcodes="${all_barcodes} ${file}"
  done

  cat ${all_barcodes} > all_barcodes.html
  cat all_barcodes.html | grep -v "hide" > all_barcodes_edited.html
  mv all_barcodes_edited.html Data/Intensities/BaseCalls/Reports/${run_id}_all_barcodes.html


  # concatenate all the lane.html files into single ${run_id}_all_lanes.html file
  all_lanes=''
  for file in $(find Data/Intensities/BaseCalls/Reports/ -name "lane.html")
  do
    all_lanes="${all_lanes} ${file}"
  done

  cat ${all_lanes} > all_lanes.html
  cat all_lanes.html | grep -v "show" > all_lanes_edited.html

  set -x

  # remove bcl files and their folders
  mkdir bcls
  mv Data/Intensities/BaseCalls/L* bcls/

  # tar the Logs/ and InterOp/ directories to speed up upload process
  tar -czf InterOp.tar.gz InterOp/
  tar -czf Logs.tar.gz Logs/
  tar -czf htmlLaneReports.tar.gz Data/Intensities/BaseCalls/Reports/html/

  # dump out all reports since we have tarred them
  mv -t /tmp Data/Intensities/BaseCalls/Reports/html/

  # add in the summarised html
  mv all_lanes_edited.html Data/${run_id}_all_lanes.html

  # move dirs to output to be uploaded
  mv -t ${outdir}/ Data/ Config/ Recipe/

  # add tars and other required files to upload separately
  mv -t ${outdir}/ InterOp.tar.gz Logs.tar.gz htmlLaneReports.tar.gz
  mv R*.* ${outdir}/ # RTAComplete.{txt/xml}. RTA3.cfg, RunInfo.xml, RunParameters.xml
  mv S*.* ${outdir}/ # SampleSheet.csv and SequenceComplete.txt

  # Upload outputs
  /usr/bin/time -v dx-upload-all-outputs --parallel

  # check usage to monitor usage of instance storage
  echo "Total file system usage"
  df -h

  echo "DONE!"
}