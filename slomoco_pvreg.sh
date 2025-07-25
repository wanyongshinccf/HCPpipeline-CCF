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

InputfMRI=`${FSLDIR}/bin/remove_ext ${1}`
OutputfMRI=`${FSLDIR}/bin/remove_ext ${2}`
GradientDistortionField=`${FSLDIR}/bin/remove_ext${3}` 
MotionMatrixDir=${4} #MotionMatrices
PartialVolumeFolder=${5}

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
InputfMRI=$fMRIFolder/rfMRI_REST1_RL_orig
OutputfMRI=$fMRIFolder/SLOMOCO/epi_gdc_pv        
GradientDistortionField=${3}"$fMRIFolder"/rfMRI_REST1_RL_gdc_warp 
MotionMatrixDir=$fMRIFolder/MotionMatrices
PartialVolumeFolder="$fMRIFolder"/SLOMOCO/pv                 
fi

# generate inplane directory
if [ ! -d ${PartialVolumeFolder} ]; then
    mkdir -p ${PartialVolumeFolder}
fi

## read dimensions
zdim=`fslval $InputfMRI dim3`
tdim=`fslval $InputfMRI dim4`
tr=`fslval $InputfMRI pixdim4`
let "zmbdim=$zdim/$SMSfactor"

# generate mean volume of input
fslmaths $InputfMRI -Tmean ${PartialVolumeFolder}/epimean
fslsplit $InputfMRI ${PartialVolumeFolder}/vol  -t

# generate the reference images at each TR
str_tcombined=""
for ((t = 0 ; t < $tdim ; t++ )); 
do 
    echo Generating MOTSIM data and resampling back at volume $t  
    vnum=`${FSLDIR}/bin/zeropad $t 4`

    fmat=${MotionMatrixDir}/MAT_${vnum}
    convert_xfm -omat ${PartialVolumeFolder}/bmat -inverse $fmat

    # Add stuff for estimating RMS motion
    volmatrix="${MotionMatrixFolder}/MAT_${vnum}"

    # Combine GCD with injected motion
    ${FSLDIR}/bin/convertwarp \
    --relout --rel \
    --ref=${PartialVolumeFolder}/epimean \
    --warp1=${GradientDistortionField} \
    --postmat=${PartialVolumeFolder}/bmat \
    --out=${PartialVolumeFolder}/MAT_${vnum}_gdc_warp    
    
    # Apply one-step warp, using spline interpolation
    ${FSLDIR}/bin/applywarp \
        --rel \
        --interp=nn \
        --in=${PartialVolumeFolder}/vol${vnum} \
        --warp=${PartialVolumeFolder}/MAT_${vnum}_gdc_warp \
        --ref=${PartialVolumeFolder}/epimean \
        --out=${PartialVolumeFolder}/motsim

    # move back MOTSIM
    flirt                                       \
        -in             ${PartialVolumeFolder}/motsim         \
        -ref            ${PartialVolumeFolder}/epimean        \
        -applyxfm -init ${fmat}                 \
        -out            ${PartialVolumeFolder}/epipv${vnum}  \
        -interp         nearestneighbour

    str_tcombined="$str_tcombined ${PartialVolumeFolder}/epipv${vnum} "
done

# combine all the volumes
${FSLDIR}/bin/fslmerge -tr ${PartialVolumeFolder}/epipvall `echo $str_tcombined` $tr

# demean and normaliz
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -Tmean ${PartialVolumeFolder}/epipv_mean
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -Tstd  ${PartialVolumeFolder}/epipv_std 
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -sub ${PartialVolumeFolder}/epipv_mean -div ${PartialVolumeFolder}/epipv_std ${OutputfMRI}

# clean up
\rm -rf ${PartialVolumeFolder}