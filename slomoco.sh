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

InputfMRI=`${FSLDIR}/bin/remove_ext ${1}`
InputfMRIgdc=`${FSLDIR}/bin/remove_ext ${2}`
OutputfMRI=`${FSLDIR}/bin/remove_ext ${3}`
ScoutInput=`${FSLDIR}/bin/remove_ext ${4}`
ScoutInput_mask=`${FSLDIR}/bin/remove_ext ${5}`
MotionMatrixFolder=${6} #MotionMatrices "$fMRIFolder"/MotionCorrection/"$NameOffMRI".par  
SLOMOCOFolder=${7}
GradientDistortionField=${8}
VolumeMotion1D=${9} # 1dsliacqtime
PhysioRegressor1D=${10} # 1dsliacqtime
SliAcqTimeFile=${11} # 1dsliacqtime

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
InputfMRI=$fMRIFolder/rfMRI_REST1_RL_orig
InputfMRIgdc=$fMRIFolder/rfMRI_REST1_RL_gdc
OutfMRI=$fMRIFolder/rfMRI_REST1_RL_gdc_slomoco         
ScoutInput=$fMRIFolder/Scout_gdc
ScoutInput_mask=$fMRIFolder/Scout_gdc_mask
MotionMatrixFolder=$fMRIFolder/MotionMatrices
SLOMOCOFolder="$fMRIFolder"/SLOMOCO                 
GradientDistortionField="$fMRIFolder"/rfMRI_REST1_RL_gdc_warp         
VolumeMotion1D="$fMRIFolder"/MotionCorrection/rfMRI_REST1_RL_mc.par    
PhysioRegressor1D="$fMRIFolder"/Physio/RetroTS.PMU.slibase.1D       
SliAcqTimeFile=/mnt/hcp01/SW/HCPpipeline-CCF/SliceAcqTime_3T_TR720ms.txt
fi

# define dir
InplaneMotinFolder="$SLOMOCOFolder/inplane"
OutofPlaneMotionFolder="$SLOMOCOFolder/outofplane"
PartialVolumeFolder="$SLOMOCOFolder/pv"

# read tfile and calculate SMS factor  
SMSfactor=0
while IFS= read -r line; do
  # Process each line here
  #echo "Read line: $line"
  if [ $line == "0" ] || [ $line == "0.0" ] ; then
    let "SMSfactor+=1"
  fi
done < "$SliAcqTimeFile"
echo "inplane acceleration is $SMSfactor based on slice acquisition timing file."

# sanity check
zdim=`fslval $InputfMRI dim3`
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
$RUN "$HCPPIPECCFDIR"/slomoco_inplane.sh    \
    ${InputfMRIgdc}                         \
    ${SLOMOCOFolder}/epi_gdc_mocoxy         \
    ${ScoutInput}                           \
    ${ScoutInput_mask}                      \
    ${MotionMatrixFolder}                   \
    ${SMSfactor}                            \
    ${InplaneMotinFolder}

# out-of-plane motion estimation (NOT CORRECTION)
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP2: Out-of-plane motion estimation"
$RUN "$HCPPIPECCFDIR"/slomoco_outofplane.sh \
    ${SLOMOCOFolder}/epi_gdc_mocoxy         \
    ${ScoutInput}                           \
    ${ScoutInput_mask}                      \
    ${MotionMatrixFolder}                   \
    ${SMSfactor}                            \
    ${OutofPlaneMotionFolder}

# combine in- and out-of-plane motion parameter
echo "SLOMOCO STEP3: Combine in-/out-of-plane motion parameters."
echo "               Will be used as slicewise motion nuisance regressors"
$RUN "$HCPPIPECCFDIR"/slomoco_combine_mopa.sh \
    ${InputfMRI}                \
    ${SLOMOCOFolder}            \
    ${InplaneMotinFolder}       \
    ${OutofPlaneMotionFolder}   \
    ${SMSfactor}

# onesampling in native space 
echo "SLOMOCO STEP4: Combine GDC and SLOMOCO motion correction."
echo "               Due to slicewise regressors in a native space,"
echo "               SLOMOCO is resampled first in native space with regress-out."
echo "               Then move to MNI space later again using OneSampling_SLOMOCO.sh"
$RUN "$HCPPIPECCFDIR"/slomoco_onesampling.sh \
    ${InputfMRI}                \
    ${OutputfMRI}               \
    ${GradientDistortionField}  \
    ${MotionMatrixFolder}       \
    ${SLOMOCOFolder}            \
    ${InplaneMotinFolder}       \
    ${OutofPlaneMotionFolder}   \
    ${SMSfactor}

# HCP version of gen_pvreg.tcsh
echo "SLOMOCO STEP5: Voxelwise partial volume regressor." 
$RUN "$HCPPIPECCFDIR"/slomoco_pvreg.sh \
    ${InputfMRI}                \
    ${SLOMOCOFolder}/epi_pv     \
    ${GradientDistortionField}  \
    ${MotionMatrixFolder}       \
    ${PartialVolumeFolder}

# regress-out 
echo "SLOMOCO STEP6: Regress out 13 vol-/sli-/voxel-regressors."
$RUN "$HCPPIPECCFDIR"/slomoco_regout.sh \
    ${InputfMRI}_mocoxy           \
    ${OutputfMRI}    \
    ${ScoutInput_mask}       \
    ${SLOMOCOFolder}       \
    ${VolumeMotion1D}    \
    ${SLOMOCOFolder}/slimopa.1D    \
    ${PhysioRegressor1D}    \
    ${SLOMOCOFolder}/epi_pv 
