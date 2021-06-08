<!-- dx-header -->
# bcl2fastq v2.20 (DNAnexus Platform App)

Dx wrapper to run the bcl2fastq demultiplexing tool

This is the source code for an app that runs on the DNAnexus Platform.

<!-- Insert a description of your app here -->
## What does this app do?
Takes in the tar.gz packets of data uploaded from the NovaSeq sequencer as data was generated. OR the sentinel record file that was generated during dx-streaming-upload (which lists the file IDs of the tar.gz packets). Untars the files to reconstruct the NovaSeq output directory structure and demultiplexes the base call files to paired fastq.tar.gz for samples in the SampleSheet.csv based on the barcode sequences.

## What are typical use cases for this app?
This app may be executed as a standalone app or as part of an analysis pipeline.
Used as the first step once sequencing data is streamed from the sequencer to DNAnexus before bioinformatics analysis of the reads can begin.

## What data are required for this app to run?
This app requires
* upload sentinel record OR
* array of tar.gz containing the output packets from the sequencer

Optional input parameters:
* SampleSheet.csv - overrides the one that was uploaded from the sequencer
* advanced options for running bcl2fastq eg -l ERROR to display log messages to the terminal

## What does this app output?
* demultiplexed paired fastq reads (Data/Intensities/BaseCalls)
* demultiplexing and run-level statistics

## Dependencies
The applet depends on the bcl2fastq .deb file which is stored as an asset on DNAnexus.

### This app was made by East GLH
