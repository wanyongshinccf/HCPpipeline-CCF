#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: slomoco_pv_reg.sh <4dinput> <4doutput> <MotionMatrixDir> <scout_image> <scount_image_mask>"
    echo ""
    exit
}

input=`${FSLDIR}/bin/remove_ext ${1}`
output=`${FSLDIR}/bin/remove_ext ${2}`
GradientDistortionField=`${FSLDIR}/bin/remove_ext${3}` 
MotionMatrixDir=${4} #MotionMatrices
pvdir=${5}

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
input=$fMRIFolder/rfMRI_REST1_RL
output=$fMRIFolder/rfMRI_REST1_RL_gdc_slomoco        
GradientDistortionField=${3}"$fMRIFolder"/rfMRI_REST1_RL_gdc_warp \  
MotionMatrixDir=$fMRIFolder/MotionMatrices
slomocodir="$fMRIFolder"/SLOMOCO                 
gdfield="$fMRIFolder"/rfMRI_REST1_RL_gdc_warp \              
volmot1d="$fMRIFolder"/MotionCorrection/rfMRI_REST1_RL_mc.par    
physio1d="$fMRIFolder"/Physio/RetroTS.PMU.slibase.1D       
tfile=/mnt/hcp01/SW/HCPpipeline-CCF/SliceAcqTime_3T_TR720ms.txt
fi

# generate inplane directory
if [ ! -d ${pvdir} ]; then
    mkdir -p ${pvdir}
fi

# read dimensions
tdim=`fslval $input dim4`
tr=`fslval $input pixdim4`

# generate mean volume of input
fslmaths $input -Tmean ${pvdir}/epimean
fslsplit $input ${pvdir}/epivol  -t

# generate the reference images at each TR
str_tcombined=""
for ((t = 0 ; t < $tdim ; t++ )); 
do 
    echo Generating MOTSIM data and resampling back at volume $t  
    tnum=`printf %04d $t`
    fmat=${MotionMatrixDir}/MAT_`printf %04d $t`
    convert_xfm -omat $pvdir/bmat -inverse $fmat

    ${FSLDIR}/bin/convertwarp \
        --relout \
        --rel \
        --ref=${OSDir}/prevols/sli${znum}.nii.gz \
        --warp1=${GDField} \
        --postmat=${OSDir}/prevols/volslimatrix \
        --out=${OSDir}/sli_gdc_warp${znum}.nii.gz

    # inject the inverse motion
    flirt                                       \
        -in             ${pvdir}/epimean        \
        -ref            ${pvdir}/epivol${tnum}  \
        -applyxfm -init ${pvdir}/bmat           \
        -out            ${pvdir}/motsim        \
        -interp         nearestneighbour

    # move back MOTSIM
    flirt                                       \
        -in             ${pvdir}/motsim         \
        -ref            ${pvdir}/epimean        \
        -applyxfm -init ${fmat}                 \
        -out            ${pvdir}/epipv${tnum}  \
        -interp         nearestneighbour

    str_tcombined="$str_tcombined ${pvdir}/epipv${tnum} "
done

# combine all the volumes
${FSLDIR}/bin/fslmerge -tr ${pvdir}/epipvall `echo $str_tcombined` $tr
${FSLDIR}/bin/immv ${pvdir}/epipvall ${output}

# clean up
rm -rf ${pvdir}