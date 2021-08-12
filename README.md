<!-- dx-header -->
# bcl2fastq v2.20 (DNAnexus Platform App)

Dx wrapper to run the bcl2fastq demultiplexing tool

This is the source code for an app that runs on the DNAnexus Platform.

<!-- Insert a description of your app here -->
## What does this app do?
Takes in the tar.gz packets of data uploaded from the NovaSeq machine as sequencing data was generated. OR the sentinel record file that was generated during dx-streaming-upload. Untars the files to reconstruct the NovaSeq output directory structure and demultiplexes the base call files to paired fastq.tar.gz for samples in the SampleSheet.csv based on the barcode sequences.

## What are typical use cases for this app?
This app may be executed as a standalone app or as part of an analysis pipeline.
Used as the first step when sequencing data is streamed from the sequencer to DNAnexus before bioinformatics analysis can begin.

## What data are required for this app to run?
This app requires
* SampleSheet.csv
* upload sentinel record
* array of tar.gz containing the output packets from the sequencer

Optional input parameters:
* advanced options for running bcl2fastq

## What does this app output?
* uploads all data from the sequencer (except for bcl files)
* including the demultiplexed fastq files in the folder where they are generated (Data/Intensities/BaseCalls)
* all files in `Logs/` are uploaded to a single tar (`Logs.tar.gz`)
* all files in `InterOp/` are uploaded to a single tar (`InterOp.tar.gz`)

## Dependencies
The applet depends on the bcl2fastq .deb file which is stored as an asset on DNAnexus.

### This app was made by East GLH
