#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: slomoco.sh <4dinput> <4doutput> <1dsliacqtime> [<scout_image> [<mcref_image>]]"
    echo ""
    echo " If neither <scout_image> nor <mcref_image> is specified, a reference image"
    echo "    will be generated automatically from volumes 11-20 in the input series."
    echo ""
    echo " If only <scout_image> is specified, motion correction will use <scout_image> "
    echo "    for reference"
    echo ""
    echo " If both <scout_image> and <mcref_image> are specified, motion correction "
    echo "    will use <mcref_image> as its reference, but an additional mcref->scout"
    echo "    coregistration will be appended so that the final outputs are aligned"
    echo "    with <scout_image>"
    echo ""
    exit
}

[ "$2" = "" ] && Usage

input=`${FSLDIR}/bin/remove_ext ${1}`
output=`${FSLDIR}/bin/remove_ext ${2}`
base=`${FSLDIR}/bin/remove_ext ${3}`
mask=`${FSLDIR}/bin/remove_ext ${4}`
motionmatrixdir=${5} #MotionMatrices
slomocodir=${6}
tfile=${7} # 1dsliacqtime

inplanedir=$slomocodir/inplane
outofplanedir=$slomocodir/outofplane

# read tfile and calculate SMS factor  
SMSfactor=0
while IFS= read -r line; do
  # Process each line here
  #echo "Read line: $line"
  if [ $line == "0" ] || [ $line == "0.0" ] ; then
    let "SMSfactor+=1"
  fi
done < "$tfile"
echo "inplane acceleration is $SMSfactor based on slice acquisition timing file."

# sanity check
zdim=`fslval $input dim3`
if [ $SMSfactor == 0 ] ; then
    echo "ERROR: slice acquisition timing does not have zero"
    exit
elif [ $SMSfactor == $zdim ] ; then
    echo "ERROR: all slice acquisition timing was time-shifted to zero"
    exit
elif [ $SMSfactor != "8" ] ; then
    echo "Warning: SMS factor in 3T HCP is expected to be 8."
fi

echo "Do SLOMOCO HCP"
# inplane motion correction
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP1: Inplane motion correction"
$RUN "$SLOMOCOHCPDIR"/slomoco_inplane.sh \
    ${input}              \
    ${output}             \
    ${base}               \
    ${mask}               \
    ${motionmatrixdir}    \
    ${SMSfactor}          \
    ${inplanedir}

# out-of-plane motion estimation (NOT CORRECTION)
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP2: Out-of-plane motion estimation"
$RUN "$SLOMOCOHCPDIR"/slomoco_outofplane.sh \
    ${output}             \
    ${base}               \
    ${mask}               \
    ${motionmatrixdir}    \
    ${SMSfactor}          \
    ${outofplanedir}

# combine in- and out-of-plane motion parameter
echo "SLOMOCO STEP3: Combine in-/out-of-plane motion parameters."
echo "               Will be used as slicewise motion nuisance regressors"
$RUN "$SLOMOCOHCPDIR"/slomoco_combine_mopa.sh \
    ${output}           \
    ${slomocodir}       \
    ${inplanedir}       \
    ${outofplanedir}    \
    ${SMSfactor}
