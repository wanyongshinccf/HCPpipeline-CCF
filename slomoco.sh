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
motionmatrixdir=${5} #MotionMatrices "$fMRIFolder"/MotionCorrection/"$NameOffMRI".par  
slomocodir=${6}
volmot1d=${7} # 1dsliacqtime
physio1d=${8} # 1dsliacqtime
tfile=${9} # 1dsliacqtime

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
input=$fMRIFolder/rfMRI_REST1_RL_gdc
output=$fMRIFolder/rfMRI_REST1_RL_gdc_slomoco         
base=$fMRIFolder/Scout_gdc
mask=$fMRIFolder/Scout_gdc_mask
motionmatrixdir=$fMRIFolder/MotionMatrices
slomocodir="$fMRIFolder"/SLOMOCO                               
volmot1d="$fMRIFolder"/MotionCorrection/rfMRI_REST1_RL_mc.par    
physio1d="$fMRIFolder"/Physio/RetroTS.PMU.slibase.1D       
tfile=/mnt/hcp01/SW/HCPpipeline-CCF/SliceAcqTime_3T_TR720ms.txt
fi

# define dir
inplanedir="$slomocodir/inplane"
outofplanedir="$slomocodir/outofplane"
pvdir="$slomocodir/pv"

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
$RUN "$HCPPIPECCFDIR"/slomoco_inplane.sh \
    ${input}              \
    $slomocodir/epi_mocoxy       \
    ${base}               \
    ${mask}               \
    ${motionmatrixdir}    \
    ${SMSfactor}          \
    ${inplanedir}

# out-of-plane motion estimation (NOT CORRECTION)
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP2: Out-of-plane motion estimation"
$RUN "$HCPPIPECCFDIR"/slomoco_outofplane.sh \
    $slomocodir/epi_mocoxy      \
    ${base}               \
    ${mask}               \
    ${motionmatrixdir}    \
    ${SMSfactor}          \
    ${outofplanedir}

# combine in- and out-of-plane motion parameter
echo "SLOMOCO STEP3: Combine in-/out-of-plane motion parameters."
echo "               Will be used as slicewise motion nuisance regressors"
$RUN "$HCPPIPECCFDIR"/slomoco_combine_mopa.sh \
    ${input}           \
    ${slomocodir}       \
    ${inplanedir}       \
    ${outofplanedir}    \
    ${SMSfactor}

# HCP version of gen_pvreg.tcsh
echo "SLOMOCO STEP4: Voxelwise partial volume regressor." 
$RUN "$HCPPIPECCFDIR"/slomoco_pv_reg.sh \
    ${input}            \
    ${slomocodir}/epi_pv         \
    ${motionmatrixdir}    \
    ${pvdir}

# regress-out 
echo "SLOMOCO STEP5: Regress out 13 vol-/sli-/voxel-regressors."
$RUN "$HCPPIPECCFDIR"/slomoco_regout.sh \
    ${inputput}_mocoxy           \
    ${output}    \
    ${slomocodir}       \
    ${votmot1d}    \
    ${slomocodir}/slimopa.1D    \
    ${physio1d}    \
    ${input}_pv
