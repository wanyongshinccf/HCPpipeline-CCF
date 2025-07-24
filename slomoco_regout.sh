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

input=`${FSLDIR}/bin/remove_ext ${1}`
output=`${FSLDIR}/bin/remove_ext ${2}`
slomocodir=${3}
volmot1d=${4} #MotionMatrices
slimot1d=${5}
physio1d=${6}
voxelpv=${7}

# test purpose, will be deleted
#fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
#input=$fMRIFolder/rfMRI_REST1_RL_gdc.nii.gz
#output=$fMRIFolder/rfMRI_REST1_RL_gdc_slomoco                                      
#volmot1d="$fMRIFolder"/MotionCorrection/rfMRI_REST1_RL_mc.par    
#physio1d="$fMRIFolder"/Physio/RetroTS.PMU.slibase.1D       
#slimot1d="$fMRIFolder"/SLOMOCO/slimopa.1D
#voxelpv="$fMRIFolder"/SLOMOCO/epi_pv
#slomocodir="$fMRIFolder"/SLOMOCO

# Step 1; prepare volmot + polinomial detrending
1d_tool.py                  \
    -infile $volmot1d       \
    -demean                 \
    -write $slomocodir/__rm.mopa6.demean.1D  \
    -overwrite
    -mask   ${epi_mask}                                                 \
    
# volmopa includues the polinominal (linear) detrending 
3dDeconvolve                                                            \
    -input  ${input}                                                      \
    -polort A                                                    \
    -num_stimts 6                                                       \
    -stim_file 1 $slomocodir/__rm.mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
    -stim_file 2 $slomocodir/__rm.mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
    -stim_file 3 $slomocodir/__rm.mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
    -stim_file 4 $slomocodir/__rm.mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
    -stim_file 5 $slomocodir/__rm.mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
    -stim_file 6 $slomocodir/__rm.mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
    -x1D       $slomocodir/volreg.1D                                           \
    -x1D_stop                                                           \
    -overwrite

# update 
volregstr="-matrix volmot.1D "

# step2 slimopa + physio 1D
1d_tool.py                  \
    -infile $physio1d       \
    -demean                 \
    -write $slomocodir/__rm.physio.1D  \
    -overwrite

1d_tool.py                  \
    -infile $slimot1d       \
    -demean                 \
    -write $slomocodir/__rm.slimot.1D  \
    -overwrite

# replace zero vectors with linear one
\rm -f $slomocodir/__rm.sliregs.1D 
python $HCPPIPECCFDIR/patch_zeros.py    \
    -infile $slomocodir/__rm.slimot.1D \
    -write  $slomocodir/__rm.slimotzp.1D  

#  combine 
python $HCPPIPECCFDIR/combine_physio_slimopa.py  \
    -slireg $slomocodir/__rm.slimotzp.1D                      \
    -physio $slomocodir/__rm.physio.1D                       \
    -write  $slomocodir/slireg.1D  

sliregstr="-slibase_sm $slomocodir/slireg.1D " 

volregstr="-dsort $voxelpv "

# regress out all nuisances here
3dREMLfit               \
    -input  ${input}    \
    $volregstr          \
    $sliregstr          \
    $voxregstr          \
    -Oerrts $slomocodir/errts  \
    -GOFORIT            \
    -overwrite       
