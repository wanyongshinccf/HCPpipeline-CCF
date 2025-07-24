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
MotionMatrixDir=${3} #MotionMatrices
pvdir=${4}

# test purpose, will be deleted
#input=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_mc
#output=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_mc_pv
#MotionMatrixDir=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/MotionMatrices
#pvdir=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/SLOMOCO/pv  

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