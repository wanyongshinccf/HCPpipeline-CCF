#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: slomoco_regout.sh <4dinput> <4doutput> <MotionMatrixDir> <scout_image> <scount_image_mask>"
    echo ""
    exit
}

InputfMRI=`${FSLDIR}/bin/remove_ext ${1}`
OutputfMRI=`${FSLDIR}/bin/remove_ext ${2}`
ScoutInput_mask=${3}
SLOMOCOFolder=${4}
VolumeMotion1D=${5} #MotionMatrices
SliceMotion1D=${6}
PhysioRegressor1D=${7}
PVTimeSeries=${8}

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
fMRIFolder=/home/shinw/HCP/100206/rfMRI_REST1_RL
SLOMOCOFolder=$fMRIFolder/SLOMOCO
InputfMRI=$SLOMOCOFolder/epi_gdc_mocoxy
OutputfMRI=$fMRIFolder/rfMRI_REST1_RL_slomoco         
ScoutInput=$fMRIFolder/Scout_gdc
ScoutInput_mask=$fMRIFolder/Scout_gdc_mask
MotionMatrixFolder=$fMRIFolder/MotionMatrices                          
VolumeMotion1D="$fMRIFolder"/MotionCorrection/rfMRI_REST1_RL_mc.par    
PhysioRegressor1D="$fMRIFolder"/Physio/RetroTS.PMU.slibase.1D      
SliceMotion1D=${SLOMOCOFolder}/slimopa.1D 
PVTimeSeries=${SLOMOCOFolder}/epi_gdc_pv 
fi

# Step 1; prepare volmot + polinomial detrending
1d_tool.py                  \
    -infile $VolumeMotion1D       \
    -demean                 \
    -write $SLOMOCOFolder/__rm.mopa6.demean.1D  \
    -overwrite
    
# volmopa includues the polinominal (linear) detrending 
3dDeconvolve                                                            \
    -input  ${InputfMRI}.nii.gz                                                      \
    -polort A                                                    \
    -num_stimts 6                                                       \
    -stim_file 1 $SLOMOCOFolder/__rm.mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
    -stim_file 2 $SLOMOCOFolder/__rm.mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
    -stim_file 3 $SLOMOCOFolder/__rm.mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
    -stim_file 4 $SLOMOCOFolder/__rm.mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
    -stim_file 5 $SLOMOCOFolder/__rm.mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
    -stim_file 6 $SLOMOCOFolder/__rm.mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
    -x1D       $SLOMOCOFolder/volreg.1D                                           \
    -x1D_stop                                                           \
    -overwrite

# update 
volregstr="-matrix volreg.1D "

# step2 slimopa + physio 1D
1d_tool.py                  \
    -infile $SliceMotion1D       \
    -demean                 \
    -write $SLOMOCOFolder/__rm.slimot.1D  \
    -overwrite

# replace zero vectors with linear one
\rm -f  $SLOMOCOFolder/__rm.slimotzp.1D \
        $SLOMOCOFolder/slireg.1D
python $HCPPIPECCFDIR/patch_zeros.py    \
    -infile $SLOMOCOFolder/__rm.slimot.1D \
    -write  $SLOMOCOFolder/__rm.slimotzp.1D  

if [ -e $PhysioRegressor1D ]; then
    1d_tool.py                  \
        -infile $PhysioRegressor1D       \
        -demean                 \
        -write $SLOMOCOFolder/__rm.physio.1D  \
        -overwrite

    #  combine 
    python $HCPPIPECCFDIR/combine_physio_slimopa.py  \
        -slireg $SLOMOCOFolder/__rm.slimotzp.1D                      \
        -physio $SLOMOCOFolder/__rm.physio.1D                       \
        -write  $SLOMOCOFolder/slireg.1D
else
    \cp -f $SLOMOCOFolder/__rm.slimotzp.1D  $SLOMOCOFolder/slireg.1D
fi

sliregstr="-slibase_sm $SLOMOCOFolder/slireg.1D " 

volregstr="-dsort ${PVTimeSeries}.nii.gz "

# regress out all nuisances here
3dREMLfit               \
    -input  ${InputfMRI}.nii.gz    \
    $volregstr          \
    $sliregstr          \
    $voxregstr          \
    -Oerrts $SLOMOCOFolder/errts.nii.gz  \
    -GOFORIT            \
    -overwrite       

# injected tissue contrast and make output
3dTstat -mean -prefix $SLOMOCOFolder/__rm.mean.nii.gz ${InputfMRI}.nii.gz
3dcalc \
    -a $SLOMOCOFolder/errts.nii.gz \
    -b $SLOMOCOFolder/__rm.mean.nii.gz \
    -expr 'a+b' \
    -prefix $OutputfMRI.nii.gz \
    -overwrite

# clean
\rm -f  $SLOMOCOFolder/__rm.* \
        $SLOMOCOFolder/errts.* \
        $SLOMOCOFolder/epi_gdc_pv.nii.gz 

echo "Finished: 13 vol-/sli-/vox-wise motion nuisance regressors & "
echo "          polymonial detrending lines are regressed out."