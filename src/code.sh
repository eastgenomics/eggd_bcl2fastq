#!/bin/bash

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

# check if lane splitting is turned on
if [ "${no_lane_splitting}" == "true" ]
then
    args+=("--no-lane-splitting")
fi

 # either a run archive or a sentinel record must be provided as an input
  if [ -n "${run_archive}" ]; then

    for i in ${!run_archive_name[@]}; do

        # format check and uncompress
        name="${run_archive_name[${i}]}"
        if [ "${name}" == *.rar ]; then

          dx download "${run_archive[${i}]}" -o "${name}"
          unrar x "${name}"

        elif [ "${name}" == *.zip ]; then

          dx download "${run_archive[$i]}" -o "${name}"
          unzip "${name}"

        elif [[ "${name}" == *.tgz ]] || [[ "${name}" == *.tar.gz ]]; then

          dx cat "${run_archive[${i}]}" | tar zxf - --no-same-owner

        else

          dx-jobutil-report-error "ERROR: The input was not a .rar, .zip, .tar.gz or .tgz"

        fi
done

elif [ -n "${upload_sentinel_record}" ]
  then
  mkdir ./input
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
      dx cat ${file_id} | tar xzf - --no-same-owner -C ./input/

    elif [[ "${extn}" == "tar" ]]; then
      dx cat ${file_id} | tar xf - --no-same-owner -C ./input/

    else
        dx-jobutil-report-error "The upload_sentinel_record doesn't contain tar or tar.gzs"
    fi

  done
  rm files_names.t*

else
  dx-jobutil-report-error "Please provide either a compressed RUN folder or an upload Sentinel Record as an input"
fi

# check for the presence/location of the run folder

location_of_data=$(find . -type d -name "Data")

if [ "${location_of_data}" == "" ]; then
  dx-jobutil-report-error "The Data folder could not be found."
fi

location_of_runarchive=${location_of_data%/Data}

# check if the samplesheet is provided as an input, if so, download it

if [ "${sample_sheet}" != "" ]; then
  dx download -f "${sample_sheet}" -o SampleSheet.csv


# if not check if its present along with the sentinel record
  # get the samplesheet id from the sentinel record and download it

elif [ -n "${upload_sentinel_record}" ]; then
  sample_sheet_id=$(dx get_details "${upload_sentinel_record}" | jq -r .samplesheet_file_id)

  if [ "${sample_sheet_id}" ==  "null"  ]; then
    dx-jobutil-report-error "Samplesheet was not found." AppInternalError

  else
    dx download -f "${sample_sheet_id}" -o SampleSheet.csv
  fi

  # check if its present in the run folder --
elif [ -f ${location_of_runarchive}/SampleSheet.csv ]; then
      echo "The SampleSheet found in the run directory."

else
      dx-jobutil-report-error "The SampleSheet could not be found."
fi

# make sure the sample sheet is present in the correct location as the tool would expect
if [ "${location_of_runarchive}" != "." ]; then
  mv SampleSheet.csv "${location_of_runarchive}"/SampleSheet.csv
fi

cd "${location_of_runarchive}"

# formatting check
/usr/bin/dos2unix SampleSheet.csv

cp SampleSheet.csv SampleSheet.tmp

# remove any non alphanumeric characters in place
sed -i 's/[: ()]//g' SampleSheet.csv

# get run ID for prefix the summary/stats files
run_id=$(cat RunInfo.xml | grep "Run Id" | cut -d'"' -f2)


docker load -i /bcl2fastq.tar.gz

docker run --rm -v $PWD:/home/dnanexus/"${location_of_runarchive}" -w /home/dnanexus/"${location_of_runarchive}" bcl2fastq bcl2fastq $args $advanced_opts

# /usr/bin/bcl2fastq $args $advanced_opts
    
  # Annotating R1 reads

    awk -v value="Sample_ID" '{if($0~value) print $0",R1.fastq.gz"; else print $0}' SampleSheet.tmp > SampleSheet.csv
  find . -name "*_R1_*.fastq.gz" -mindepth 5 | while read file
  do 
        prefix=`basename $file |  cut -d  '_' -f1`
            if [ "$prefix" == "Undetermined" ]; then
              echo "Don't test undetermined"
          else
          #prefix=`echo $file | cut -d '/' -f7 |  cut -d  '_' -f1`
              size=$(stat -c%s "$file")
            cp SampleSheet.csv SampleSheet.tmp
          if [ "$size" -lt "$size_limit" ]; then
                awk -v value="$prefix" '{if($0~value) print $0",FAIL"; else print $0}' SampleSheet.tmp >  SampleSheet.csv
                else
                  awk -v value="$prefix" '{if($0~value) print $0",PASS"; else print $0}' SampleSheet.tmp > SampleSheet.csv
          fi
    fi
done

# Annotating R2 reads
    # cp SampleSheet.csv SampleSheet.tmp
    awk -v value="Sample_ID" '{if($0~value) print $0",R2.fastq.gz"; else print $0}' SampleSheet.tmp > SampleSheet.csv
    find . -name "*_R2_*.fastq.gz" -mindepth 5 | while read file
  do
        prefix=`basename $file | cut -d  '_' -f1`
        if [ "$prefix" == "Undetermined" ]; then
                              echo "Don't test undetermined"
            else
                  #prefix=`echo $file | cut -d '/' -f7 |  cut -d  '_' -f1`
                  size=$(stat -c%s "$file")
                # cp SampleSheet.csv SampleSheet.tmp
                if [ "$size" -lt "$size_limit" ]; then
                  awk -v value="$prefix" '{if($0~value) print $0",FAIL"; else print $0}' SampleSheet.tmp >  SampleSheet.csv
                else
                        awk -v value="$prefix" '{if($0~value) print $0",PASS"; else print $0}' SampleSheet.tmp > SampleSheet.csv
                fi
        fi
    done

dos2unix SampleSheet.csv
cp SampleSheet.csv ${info}_SampleSheet.csv


basecalls="Data/Intensities/BaseCalls/"


#upload fastqs
# Make a dummy entry for reads2 (for single end sequencing)
echo "{\"reads2\":[]}" > ~/job_output.json

  dx upload ${info}_SampleSheet.csv  --path $dest_project:/ 
  
  dx-jobutil-add-output out_info "$info" --class=string
  file_id=$(dx upload SampleSheet.csv --brief)
  dx-jobutil-add-output new_sample_sheet "$file_id" --class file

# look for R1 fastq files and upload them
find . -name "*_R1_*.fastq.gz" | while read fastq1
do

  name="${fastq1##./Data/Intensities/BaseCalls/}"

  file_id=$(dx upload "${fastq1}" --brief -p --path "${name}")
  dx-jobutil-add-output reads "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
  fi

done

# look for R2 fastq files and upload them
find . -name "*_R2_*.fastq.gz" | while read fastq2
do

  name="${fastq2##./Data/Intensities/BaseCalls/}"

  file_id=$(dx upload "${fastq2}" --brief -p --path "${name}")
  dx-jobutil-add-output reads2 "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi
done

#upload reports
reportsbase="${basecalls}Reports/"

# concatenate all the lane.html and laneBarcode.html files
all_barcodes=''
all_lanes=''
for file in $(find ${reportsbase} -name "laneBarcode.html"); do all_barcodes="${all_barcodes} ${file}"; done
cat ${all_barcodes} > all_barcodes.html
cat all_barcodes.html | grep -v "hide" > all_barcodes_edited.html

for file in $(find ${reportsbase} -name "lane.html"); do all_lanes="${all_lanes} ${file}"; done
cat ${all_lanes} > all_lanes.html
cat all_lanes.html | grep -v "show" > all_lanes_edited.html

# upload the html files
file_id=$(dx upload all_barcodes_edited.html --brief -p --path "summary/${run_id}_all_barcodes.html")
dx-jobutil-add-output stats "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi

file_id=$(dx upload all_lanes_edited.html --brief -p --path "summary/${run_id}_all_lanes.html")
dx-jobutil-add-output stats "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi

#upload stats
statsbase="${basecalls}Stats/"
find $statsbase -name "*.xml" | while read xml
do

  name="${xml##Data/Intensities/BaseCalls/Stats/}"
  file_id=$(dx upload "${xml}" --brief -p --path "summary/${run_id}_${name}")
  dx-jobutil-add-output stats "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi
done

#upload summaries
find ${statsbase} -name "FastqSummary*.txt" | while read summary
do

  name="${summary##Data/Intensities/BaseCalls/Stats/}"
  file_id=$(dx upload "${summary}" --brief -p --path "summary/${run_id}_${name}")
  dx-jobutil-add-output fastq_summaries "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi
done

find ${statsbase} -name "DemuxSummary*.txt" | while read summary
do
  name="${summary##Data/Intensities/BaseCalls/Stats*/}"
  file_id=$(dx upload "${summary}" --brief -p --path "summary/${run_id}_${name}")
  dx-jobutil-add-output demux_summaries "${file_id}" --class file --array

  if [ -n "${upload_sentinel_record}" ]; then
  /usr/bin/propagate-user-meta "${upload_sentinel_record}" "${file_id}"
fi
done

record_id=$(create_stat_summary.py --fastq_summaries $(find "${statsbase}" -name "FastqSummary*.txt") \
    --demux_summaries $(find "${statsbase}" -name "DemuxSummary*.txt") \
    --record_name "${run_id}".stats_record)

dx-jobutil-add-output stats_record "${record_id}" --class record

if [ -n "${upload_sentinel_record}" ]; then
/usr/bin/propagate-user-meta "${upload_sentinel_record}" "${record_id}"
fi
