#!/bin/bash
# Wrapper for FSL's Melodic.

# Written by Andreas Heckel
# University of Heidelberg
# heckelandreas@googlemail.com
# https://github.com/ahheckel
# 12/28/2012

set -e

trap 'echo "$0 : An ERROR has occured."' ERR

Usage() {
    echo ""
    echo "Usage: `basename $0` [-pref out-prefix] <\"input-file(s)\"|inputfiles.txt> <TR(sec)> <output-dir|-1> [melodic options]"
    echo "Examples: `basename $0` \"file01.nii.gz file02.nii.gz ...\" 3.330 -1"
    echo "          `basename $0` inputfiles.txt 3.330 ./melodic_ICA \"--nobet -d 25\""
    echo "          `basename $0` inputfiles.txt 3.330 -1 \"--nobet -d 25\""
    echo ""
    echo "           multiple inputs:          assuming 'concat' mode."
    echo "           textfile as input:        assuming 'concat' mode on files in textfile."
    echo "           single file as input:     assuming single session mode."
    echo "           output-dir -1:            assuming single session mode."
    echo "                                     -1: saves result in directory of input file."
    echo ""
    exit 1
}

function _imtest()
{
  local vol="$1"
 
  if [ -f ${vol} -o -f ${vol}.nii -o -f ${vol}.nii.gz -o -f ${vol}.hdr -o -f ${vol}.img ] ; then
    if [ $(fslinfo $vol 2>/dev/null | wc -l) -gt 0 ] ; then
      echo "1"
    else
      echo "0"
    fi
  else
    echo "0" 
  fi  
}

function testascii()
{
  local file="$1"
  if LC_ALL=C grep -q '[^[:print:][:space:]]' $file; then
      echo "0"
  else
      echo "1"
  fi
}

function exec_melodic()
{
  local input2melodic="$1"
  local outdir="$2"
  local subdir="$3"
  local opts="$4"
  local sge="$5" ; if [ x"$sge" = "x" ] ; then sge=0 ; fi
  
  # convert to absolute paths
  if [ $(echo $input2melodic | grep ^/ | wc -l) -eq 0 ] ; then input2melodic=$(pwd)/$input2melodic ; fi
  if [ $(echo $outdir | grep ^/ | wc -l) -eq 0 ] ; then outdir=$(pwd)/$outdir ; fi
  
  # check
  if [ ! -f $input2melodic ] ; then 
    if [ $(_imtest $input2melodic) -eq 0 ] ; then echo "`basename $0`: ERROR: '$input2melodic' does not exist !" ; exit 1 ; fi
  fi

  # add guireport to opts
  opts="$opts --guireport=$outdir/$subdir/report.html"

  # delete outdir if present
  if [ -f $outdir/$subdir/report/00index.html ] ; then echo "" ; echo "`basename $0`: WARNING : output directory '$outdir/$subdir' already exists - deleting it in 5 seconds..." ; echo "" ; sleep 5 ; rm -r $outdir/$subdir ; fi
  
  # create output directory
  mkdir -p $outdir/$subdir

  # execute melodic
  echo ""
  cmd="melodic -i $input2melodic -o $outdir/$subdir $opts"
  echo $cmd | tee $outdir/$subdir/melodic.cmd
  if [ $sge -eq 1 -a x"$SGE_ROOT" != "x" ] ; then
    fsl_sub -l $outdir/$subdir/ -t $outdir/$subdir/melodic.cmd
  else
    . $outdir/$subdir/melodic.cmd
  fi

  # link to report webpage
  ln -sfv ./report/00index.html $outdir/$subdir/report.html  
}

if [ "$1" = "-pref" ] ; then prefix="$2"_ ; shift 2 ; else prefix="" ; fi
[ "$3" = "" ] && Usage
inputs="$1"
TR=$2
outdir="$3"
_opts="$4"

# single session or group ICA ?
if [ $(echo "$inputs" | wc -w) -eq 1 ] ; then
  if [ $(_imtest $inputs) -eq 1 ] ; then # single session ICA
    gica=0
  elif [ $(testascii $inputs) -eq 1 ] ; then # assume group ICA
    if [ $(cat $inputs | grep "[[:alnum:]]" | wc -l) -eq 1 ] ; then
      gica=0
    elif [ $(cat $inputs | grep "[[:alnum:]]" | wc -l) -gt 1 ] ; then
      gica=1
    else
      echo "`basename $0`: ERROR : '$input' is empty - exiting." ; exit 1
    fi      
    inputs="$(cat $inputs)" # asuming ascii list with volumes
  else
    echo "`basename $0`: ERROR : cannot read inputfile '$inputs' - exiting." ; exit 1 
  fi
else # assume group ICA
  gica=1
fi

# check inputs
err=0
for file in $inputs ; do
  if [ $(_imtest $file) -eq 0 ] ; then echo "`basename $0`: ERROR: '$file' does not exist !" ; err=1 ; fi
done
if [ $err -eq 1 ] ; then echo "`basename $0`: An ERROR has occured. Exiting..." ; exit 1 ; fi

# create command options
opts="-v --tr=${TR} --report --mmthresh=0.5 --Oall $_opts"

# display info
if [ $gica -eq 1 -a "$outdir" != "-1" ] ; then
  echo "`basename $0`: applying 'concat' mode."
  opts="$opts -a concat"
else 
  echo "`basename $0`: applying single session mode."
fi

# group melodic - output in $outdir
if [ $gica -eq 1 -a "$outdir" != "-1" ] ; then
  # create output directory
  mkdir -p $outdir
  # gather inputs (four group melodic)
  err=0 ; rm -f $outdir/melodic.inputfiles ; i=1
  for file in $inputs ; do
    if [ $(_imtest $file) -eq 1 ] ; then echo "`basename $0`: $i adding '$file' to input filelist..." ; echo $file >> $outdir/melodic.inputfiles ; i=$[$i+1] ; else echo "`basename $0`: ERROR: '$file' does not exist !" ; err=1 ; fi
  done
  if [ $err -eq 1 ] ; then echo "`basename $0`: An ERROR has occured. Exiting..." ; exit 1 ; fi
  input2melodic="$outdir/melodic.inputfiles"
  outdir="$outdir"
  subdir=${prefix}groupmelodic.ica
  # execute
  exec_melodic $input2melodic $outdir $subdir "$opts"
fi

# single session - multiple files - input directory as outdir
if  [ $gica -eq 1 -a "$outdir" = "-1" ] ; then
  i=1
  for file in $inputs ; do
    outdir="$(dirname $file)"
    subdir=${prefix}$(remove_ext $(basename $file)).ica
    echo "`basename $0`: $i. single session ICA will be carried out for file '$file' in '$outdir/$subdir'..."
    if [ $(_imtest $file) -eq 0 ] ; then echo "`basename $0`: ERROR: '$file' does not exist !" ; err=1 ; fi
    i=$[$i+1]
  done
  if [ $err -eq 1 ] ; then echo "`basename $0`: An ERROR has occured. Exiting..." ; exit 1 ; fi  
  for file in $inputs ; do
    input2melodic="$file" # single file for single session ICA
    outdir="$(dirname $file)"
    subdir=${prefix}$(remove_ext $(basename $file)).ica
    # execute
    exec_melodic $input2melodic $outdir $subdir "$opts" 1
  done
fi

# single session - single file - output in $outdir
if [ $gica -eq 0 -a "$outdir" != "-1" ] ; then
  input2melodic="$inputs" # single file for single session ICA
  outdir="$outdir"
  subdir=${prefix}$(remove_ext $(basename $inputs)).ica  
  # execute
  exec_melodic $input2melodic $outdir $subdir "$opts" 
fi

# single session - single file - input directory as outdir
if [ $gica -eq 0 -a "$outdir" = "-1" ] ; then
  input2melodic="$inputs" # single file for single session ICA
  outdir="$(dirname $inputs)"
  subdir=${prefix}$(remove_ext $(basename $inputs)).ica
  # execute
  exec_melodic $input2melodic $outdir $subdir "$opts"  
fi

# done
echo "`basename $0`: done."
