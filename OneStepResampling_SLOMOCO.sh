#!/bin/bash 

# Requirements for this script
#  installed versions of: FSL
#  environment: HCPPIPEDIR, FSLDIR

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

set -eu

pipedirguessed=0
if [[ "${HCPPIPEDIR:-}" == "" ]]
then
    pipedirguessed=1
    #fix this if the script is more than one level below HCPPIPEDIR
    export HCPPIPEDIR="$(dirname -- "$0")/../.."
fi

source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source "$HCPPIPEDIR/global/scripts/newopts.shlib" "$@"
source ${HCPPIPEDIR}/global/scripts/tempfiles.shlib


opts_SetScriptDescription "Script to combine warps and affine transforms together and do a single resampling, with specified output resolution"

opts_AddMandatory '--workingdir' 'WD' 'path' 'working dir'

opts_AddMandatory '--infmri' 'InputfMRI' 'image' "input fMRI 4D image"

opts_AddMandatory '--t1' 'T1wImage' 'image' "input T1w restored image"

opts_AddMandatory '--fmriresout' 'FinalfMRIResolution' 'resolution' "output resolution for images or typically the fmri resolution"

opts_AddMandatory '--fmrifolder' 'fMRIFolder' 'path' "fMRI processing folder"

opts_AddMandatory '--fmri2structin' 'fMRIToStructuralInput' 'path' "input fMRI to T1w warp"

opts_AddMandatory '--struct2std' 'StructuralToStandard' 'path' "input T1w to MNI warp"

opts_AddMandatory '--owarp' 'OutputTransform' 'path' "output fMRI to MNI warp"

opts_AddMandatory '--oiwarp' 'OutputInvTransform' 'path' "output MNI to fMRI warp"

opts_AddMandatory '--motionmatdir' 'MotionMatrixFolder' 'path' "input motion correcton matrix directory"

opts_AddMandatory '--motionmatprefix' 'MotionMatrixPrefix' 'string' "input motion correcton matrix filename prefix"

opts_AddMandatory '--ofmri' 'OutputfMRI' 'image' "input fMRI 4D image"

opts_AddMandatory '--freesurferbrainmask' 'FreeSurferBrainMask' 'mask' "input FreeSurfer brain mask or nifti format in atlas (MNI152) space"

opts_AddMandatory '--biasfield' 'BiasField' 'image' "input biasfield image or in atlas (MNI152) space"

opts_AddMandatory '--gdfield' 'GradientDistortionField' 'gradient' "input warpfield for gradient non-linearity correction"

opts_AddMandatory '--scoutin' 'ScoutInput' 'image' "input scout image (EPI pre-sat, before gradient non-linearity distortion correction)"

opts_AddMandatory '--scoutgdcin' 'ScoutInputgdc' 'gradient' "input scout gradient nonlinearity distortion corrected image (EPI pre-sat)"

opts_AddMandatory '--oscout' 'ScoutOutput' 'image' "output transformed + distortion corrected scout image"

opts_AddMandatory '--ojacobian' 'JacobianOut' 'image' "output transformed + distortion corrected Jacobian image"

opts_AddMandatory '--slomocomotionmatdir' 'SLOMOCOMatrixFolder' 'path' "SLOMOCO inplane directory"

opts_AddMandatory '--sliacqfile' 'SLIACQTIME' 'file' "Slice acquisition timing file"

#Optional Args 
opts_AddOptional '--fmrirefpath' 'fMRIReferencePath' 'path' "path to an external BOLD reference or NONE (default)" "NONE"

opts_AddOptional '--wb-resample' 'useWbResample' 'true/false' "Use wb command to do volume resampeling instead of applywarp, requires wb_command version newer than 1.5.0" "0"

opts_AddOptional '--fmrirefreg' 'fMRIReferenceReg' 'registration method' "whether to do 'linear', 'nonlinear' or no ('NONE', default) registration to external BOLD reference image" "NONE"

opts_ParseArguments "$@"

if ((pipedirguessed))
then
    log_Err_Abort "HCPPIPEDIR is not set, you must first source your edited copy of Examples/Scripts/SetUpHCPPipeline.sh"
fi

#display the parsed/default values
opts_ShowValues

log_Check_Env_Var FSLDIR

################################################### OUTPUT FILES #####################################################

# Outputs (in $WD):
#         NB: all these images are in standard space
#             but at the specified resolution (to match the fMRI - i.e. low-res)
#     ${T1wImageFile}.${FinalfMRIResolution}
#     ${FreeSurferBrainMaskFile}.${FinalfMRIResolution}
#     ${BiasFieldFile}.${FinalfMRIResolution}
#     Scout_gdc_MNI_warp     : a warpfield from original (distorted) scout to low-res MNI
#
# Outputs (not in either of the above):
#     ${OutputTransform}  : the warpfield from fMRI to standard (low-res)
#     ${OutputfMRI}
#     ${JacobianOut}
#     ${ScoutOutput}
#          NB: last three images are all in low-res standard space

#hidden: toggle for unreleased new resampling command, default off
#with wb_command -volume-resample, the warpfields and per-frame motion affines do not need to be combined in advance,
#and the timeseries can be resampled without splitting into one-frame files, resulting in much less file IO

case "$(echo "$useWbResample" | tr '[:upper:]' '[:lower:]')" in
    (yes | true | 1)
        useWbResample=1
        ;;
    (no | false | 0)
        useWbResample=0
        ;;
    (*)
        log_Err_Abort "unrecognized boolean '$useWbResample', please use yes/no, true/false, or 1/0"
        ;;
esac

# --- Report arguments

verbose_echo "  "
verbose_red_echo " ===> Running OneStepResampling_SLOMOCO"
verbose_echo " "
verbose_echo " Using parameters ..."
verbose_echo "         --workingdir: ${WD}"
verbose_echo "             --infmri: ${InputfMRI}"
verbose_echo "                 --t1: ${T1wImage}"
verbose_echo "         --fmriresout: ${FinalfMRIResolution}"
verbose_echo "         --fmrifolder: ${fMRIFolder}"
verbose_echo "      --fmri2structin: ${fMRIToStructuralInput}"
verbose_echo "         --struct2std: ${StructuralToStandard}"
verbose_echo "              --owarp: ${OutputTransform}"
verbose_echo "             --oiwarp: ${OutputInvTransform}"
verbose_echo "       --motionmatdir: ${MotionMatrixFolder}"
verbose_echo "    --motionmatprefix: ${MotionMatrixPrefix}"
verbose_echo "              --ofmri: ${OutputfMRI}"
verbose_echo "--freesurferbrainmask: ${FreeSurferBrainMask}"
verbose_echo "          --biasfield: ${BiasField}"
verbose_echo "            --gdfield: ${GradientDistortionField}"
verbose_echo "            --scoutin: ${ScoutInput}"
verbose_echo "         --scoutgdcin: ${ScoutInputgdc}"
verbose_echo "             --oscout: ${ScoutOutput}"
verbose_echo "          --ojacobian: ${JacobianOut}"
verbose_echo "        --fmrirefpath: ${fMRIReferencePath}"
verbose_echo "         --fmrirefreg: ${fMRIReferenceReg}"
verbose_echo "--slomocomotionmatdir: ${SLOMOCOMatrixFolder}"
verbose_echo "         --sliacqfile: ${SLIACQTIME}"
verbose_echo " "

# Test purpose
# WD="/home/shinw/HCP/100206/rfMRI_REST1_RL/OneStepResampling_SLOMOCO"
# InputfMRI="/home/shinw/HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_orig.nii.gz"
# T1wImage="/home/shinw/HCP/100206/MNINonLinear/T1w_restore"
# FinalfMRIResolution="2"
# fMRIFolder="/home/shinw/HCP/100206/rfMRI_REST1_RL"
# fMRIToStructuralInput="/home/shinw/HCP/100206/T1w/xfms/rfMRI_REST1_RL2str"
# StructuralToStandard="/home/shinw/HCP/100206/MNINonLinear/xfms/acpc_dc2standard"
# OutputTransform="/home/shinw/HCP/100206/MNINonLinear/xfms/rfMRI_REST1_RL2standard"
# OutputInvTransform="/home/shinw/HCP/100206/MNINonLinear/xfms/standard2rfMRI_REST1_RL"
# MotionMatrixFolder="/home/shinw/HCP/100206/rfMRI_REST1_RL/MotionMatrices"
# MotionMatrixPrefix="MAT_"
# OutputfMRI="/home/shinw/HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_orig_slomoco_nonlin"
# FreeSurferBrainMask="/home/shinw/HCP/100206/MNINonLinear/brainmask_fs"
# BiasField="/home/shinw/HCP/100206/MNINonLinear/BiasField"
# GradientDistortionField="/home/shinw/HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_gdc_warp"
# ScoutInput="/home/shinw/HCP/100206/rfMRI_REST1_RL/Scout_orig"
# ScoutInputgdc="/home/shinw/HCP/100206/rfMRI_REST1_RL/Scout_gdc"
# ScoutOutput="/home/shinw/HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_orig_SBRef_nonlin"
# JacobianOut="/home/shinw/HCP/100206/rfMRI_REST1_RL/Jacobian_MNI.2"
# fMRIReferencePath="NONE"
# useWbResample="0"
# fMRIReferenceReg="NONE"
# SLOMOCOMatrixFolder="${fMRIFolder}/SLOMOCO/inplane/MAT"
# FSLDIR=/home/shinw/fsl
######

BiasFieldFile=`basename "$BiasField"`
T1wImageFile=`basename $T1wImage`
FreeSurferBrainMaskFile=`basename "$FreeSurferBrainMask"`

# read tfile and calculate SMS factor  
SMSfactor=0
while IFS= read -r line; do
  # Process each line here
  #echo "Read line: $line"
  if [ $line == "0" ] || [ $line == "0.0" ] ; then
    let "SMSfactor+=1"
  fi
done < "$SLIACQTIME"
echo "inplane acceleration is $SMSfactor based on slice acquisition timing file."

echo " "
echo " START: OneStepResampling_SLOMOCO"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt


########################################## DO WORK ##########################################

#Save TR for later
TR_vol=`${FSLDIR}/bin/fslval ${InputfMRI} pixdim4 | cut -d " " -f 1`
NumFrames=`${FSLDIR}/bin/fslval ${InputfMRI} dim4`
zdim=`${FSLDIR}/bin/fslval  ${InputfMRI} dim3`

# Create fMRI resolution standard space files for T1w image, wmparc, and brain mask
#   NB: don't use FLIRT to do spline interpolation with -applyisoxfm for the
#       2mm and 1mm cases because it doesn't know the peculiarities of the
#       MNI template FOVs
if [[ $(echo "${FinalfMRIResolution} == 2" | bc) == "1" ]] ; then
    ResampRefIm=$FSLDIR/data/standard/MNI152_T1_2mm
elif [[ $(echo "${FinalfMRIResolution} == 1" | bc) == "1" ]] ; then
    ResampRefIm=$FSLDIR/data/standard/MNI152_T1_1mm
else
  ${FSLDIR}/bin/flirt -interp spline -in ${T1wImage} -ref ${T1wImage} -applyisoxfm $FinalfMRIResolution -out ${WD}/${T1wImageFile}.${FinalfMRIResolution}
  ResampRefIm=${WD}/${T1wImageFile}.${FinalfMRIResolution}
fi
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${T1wImage} -r ${ResampRefIm} --premat=$FSLDIR/etc/flirtsch/ident.mat -o ${WD}/${T1wImageFile}.${FinalfMRIResolution}

# Create brain masks in this space from the FreeSurfer output (changing resolution)
${FSLDIR}/bin/applywarp --rel --interp=nn -i ${FreeSurferBrainMask}.nii.gz -r ${WD}/${T1wImageFile}.${FinalfMRIResolution} --premat=$FSLDIR/etc/flirtsch/ident.mat -o ${WD}/${FreeSurferBrainMaskFile}.${FinalfMRIResolution}.nii.gz

# Create versions of the biasfield (changing resolution)
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${BiasField} -r ${WD}/${FreeSurferBrainMaskFile}.${FinalfMRIResolution}.nii.gz --premat=$FSLDIR/etc/flirtsch/ident.mat -o ${WD}/${BiasFieldFile}.${FinalfMRIResolution}
${FSLDIR}/bin/fslmaths ${WD}/${BiasFieldFile}.${FinalfMRIResolution} -thr 0.1 ${WD}/${BiasFieldFile}.${FinalfMRIResolution}

# Downsample warpfield (fMRI to standard) to increase speed
#   NB: warpfield resolution is 10mm, so 1mm to fMRIres downsample loses no precision

# Create a combined warp if nonlinear registration to reference is used
if [ "$fMRIReferenceReg" == "nonlinear" ]; then
  # Note that the name of the post motion correction warp is hard-coded in MotionCorrection.sh
  ${FSLDIR}/bin/convertwarp --relout --rel --warp1=${MotionMatrixFolder}/postmc2fmriref_warp --warp2=${fMRIToStructuralInput} --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} --out=${WD}/postmc2struct_warp
  ${FSLDIR}/bin/convertwarp --relout --rel --warp1=${WD}/postmc2struct_warp --warp2=${StructuralToStandard} --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} --out=${OutputTransform}
else
  ${FSLDIR}/bin/convertwarp --relout --rel --warp1=${fMRIToStructuralInput} --warp2=${StructuralToStandard} --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} --out=${OutputTransform}
fi

# Copy some files from ${WD} (--workingdir arg) to ${fMRIFolder} (--fmrifolder arg)
${FSLDIR}/bin/imcp ${WD}/${T1wImageFile}.${FinalfMRIResolution} ${fMRIFolder}/${T1wImageFile}.${FinalfMRIResolution}
${FSLDIR}/bin/imcp ${WD}/${FreeSurferBrainMaskFile}.${FinalfMRIResolution} ${fMRIFolder}/${FreeSurferBrainMaskFile}.${FinalfMRIResolution}
${FSLDIR}/bin/imcp ${WD}/${BiasFieldFile}.${FinalfMRIResolution} ${fMRIFolder}/${BiasFieldFile}.${FinalfMRIResolution}

if ((useWbResample))
then
    tempfiles_create OneStepResampleAffSeries_XXXXXX.txt affseries
    
    #gdc warp space is input to input, affine is input to input, OutputTransform is input to MNI
    xfmargs=(-warp "$GradientDistortionField".nii.gz -fnirt "$InputfMRI"
             -affine-series "$affseries" -flirt "$InputfMRI" "$InputfMRI"
             -warp "$OutputTransform".nii.gz -fnirt "$InputfMRI")
    
    wb_command -volume-resample "$InputfMRI" "$WD/$T1wImageFile.$FinalfMRIResolution".nii.gz CUBIC "$OutputfMRI".nii.gz "${xfmargs[@]}" -nifti-output-datatype INT32
    
    #resample all-ones volume series with enclosing voxel to determine FOV coverage
    #yes, this is the entire length of the timeseries on purpose
    tempfiles_create OneStepResampleFovCheck_XXXXXX.nii.gz fovcheck
    wb_command -volume-math '1' "$fovcheck" -var x "$InputfMRI"
    #fsl's "nn" interpolation is just as pessimistic about the FoV as non-extrapolating interpolation
    #so, in wb_command, use trilinear here instead of enclosing voxel to get the same FoV behavior as CUBIC
    #still doesn't match FSL's "nn" (and the FoV edge on "spline" isn't the same as wb_command CUBIC), not sure why
    wb_command -volume-resample "$fovcheck" "$WD/$T1wImageFile.$FinalfMRIResolution".nii.gz TRILINEAR "$OutputfMRI"_mask.nii.gz "${xfmargs[@]}" -nifti-output-datatype INT32

else
    mkdir -p ${WD}/prevols
    mkdir -p ${WD}/postvols

    # Apply combined transformations to fMRI in a one-step resampling
    # note that SLOMOCO is inplane motion correction output, according to SMS excitation
    # (combines gradient non-linearity distortion, motion correction, and registration to atlas (MNI152) space, but keeping fMRI resolution)
    ${FSLDIR}/bin/fslsplit ${InputfMRI} ${WD}/prevols/vol -t

    FrameMergeSTRING=""
    FrameMergeSTRINGII=""
    for ((k=0; k < $NumFrames; k++)); do
        echo running SLOMOCO OneStepResampling in $k volume
        vnum=`${FSLDIR}/bin/zeropad $k 4`
        volmatrix="${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum}"
      
        # split volxxxx.nii.gz to each slice for SLOMOCO 
        ${FSLDIR}/bin/fslsplit ${WD}/prevols/vol${vnum} ${WD}/prevols/sli -z
      
        # Start SLOMOCO
        SliceMergeSTRING="" 
        for ((z=0; z < $zdim; z++)); do
            let "zmb=$z%$SMSfactor" || true
            zmbnum=`${FSLDIR}/bin/zeropad $zmb 4`
            znum=`${FSLDIR}/bin/zeropad $z 4`
            slimatrix="${SLOMOCOMatrixFolder}/epiSMSsli_mc_mat_z${zmbnum}_t${vnum}"

            # concat vol + sli motion matrix
            convert_xfm -omat ${WD}/prevols/volslimatrix -concat ${slimatrix} ${volmatrix}
        
            # Combine GCD with vol+sli motion correction
            ${FSLDIR}/bin/convertwarp \
                --relout \
                --rel \
                --ref=${WD}/prevols/sli${znum}.nii.gz \
                --warp1=${GradientDistortionField} \
                --postmat=${WD}/prevols/volslimatrix \
                --out=${MotionMatrixFolder}/sli_gdc_warp${znum}.nii.gz

            # Store concatenate slicewise warp motion (in EPI space)
            SliceMergeSTRING+="${MotionMatrixFolder}/sli_gdc_warp${znum}.nii.gz "   
        done

        # Merge sli_gdc to volume gdc warp 
        ${FSLDIR}/bin/fslmerge -z ${MotionMatrixFolder}/SLOMOCO_gdc_warp.nii.gz $SliceMergeSTRING

        # Add in the warp to MNI152
        ${FSLDIR}/bin/convertwarp \
        --relout \
        --rel \
        --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} \
        --warp1=${MotionMatrixFolder}/SLOMOCO_gdc_warp.nii.gz \
        --warp2=${OutputTransform} \
        --out=${MotionMatrixFolder}/SLOMOCO_all_warp.nii.gz
      
        # Apply one-step warp, using spline interpolation
        ${FSLDIR}/bin/applywarp \
        --rel \
        --interp=spline \
        --in=${WD}/prevols/vol${vnum}.nii.gz \
        --warp=${MotionMatrixFolder}/SLOMOCO_all_warp.nii.gz \
        --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} \
        --out=${WD}/postvols/vol${vnum}.nii.gz

        # Generate a mask for keeping track of spatial coverage (use nearest neighbor interpolation here)
        ${FSLDIR}/bin/fslmaths ${WD}/prevols/vol${vnum}.nii.gz -mul 0 -add 1 ${WD}/prevols/vol${vnum}_mask.nii.gz
        ${FSLDIR}/bin/applywarp \
        --rel \
        --interp=nn \
        --in=${WD}/prevols/vol${vnum}_mask.nii.gz \
        --warp=${MotionMatrixFolder}/SLOMOCO_all_warp.nii.gz \
        --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} \
        --out=${WD}/postvols/vol${vnum}_mask.nii.gz
      
        # Create strings for merging
        FrameMergeSTRING+="${WD}/postvols/vol${vnum}.nii.gz " 
        FrameMergeSTRINGII+="${WD}/postvols/vol${vnum}_mask.nii.gz "

        #Do Basic Cleanup
        \rm -f  ${MotionMatrixFolder}/SLOMOCO_all_warp.nii.gz \
              ${MotionMatrixFolder}/sli_gdc_warp*.nii.gz     
      
    done

    verbose_red_echo "---> Merging results"
    # Merge together results and restore the TR (saved beforehand)
    ${FSLDIR}/bin/fslmerge -tr ${OutputfMRI} $FrameMergeSTRING $TR_vol
    ${FSLDIR}/bin/fslmerge -tr ${OutputfMRI}_mask $FrameMergeSTRINGII $TR_vol

    # Do Basic Cleanup
    \rm -r ${WD}/postvols ${WD}/prevols
fi

# Generate a spatial coverage mask that captures the voxels that have data available at *ALL* time points
# (gets applied in IntensityNormalization.sh; so don't change name here without changing it in that script as well).
fslmaths ${OutputfMRI}_mask -Tmin ${OutputfMRI}_mask

if [ ${fMRIReferencePath} = "NONE" ] ; then
  # Combine transformations: gradient non-linearity distortion + fMRI_dc to standard
  ${FSLDIR}/bin/convertwarp --relout --rel --ref=${WD}/${T1wImageFile}.${FinalfMRIResolution} --warp1=${GradientDistortionField} --warp2=${OutputTransform} --out=${WD}/Scout_gdc_MNI_warp.nii.gz
  ${FSLDIR}/bin/applywarp --rel --interp=spline --in=${ScoutInput} -w ${WD}/Scout_gdc_MNI_warp.nii.gz -r ${WD}/${T1wImageFile}.${FinalfMRIResolution} -o ${ScoutOutput}
fi

# Create trilinear interpolated version of Jacobian (T1w space, fMRI resolution)
#${FSLDIR}/bin/applywarp --rel --interp=trilinear -i ${JacobianIn} -r ${WD}/${T1wImageFile}.${FinalfMRIResolution} -w ${StructuralToStandard} -o ${JacobianOut}
#fMRI2Struct is from gdc space to T1w space (optionally through an external reference), ie, only fieldmap-based distortions (like topup)
#output jacobian is both gdc and topup/fieldmap jacobian, but not the to MNI jacobian
#JacobianIn was removed from inputs, now we just compute it from the combined warpfield of gdc and dc (NOT MNI)
#compute combined warpfield, but don't use jacobian output because it has 8 frames for no apparent reason
#NOTE: convertwarp always requires -o anyway
if [ "$fMRIReferenceReg" == "nonlinear" ]; then
  ${FSLDIR}/bin/convertwarp \
    --relout \
    --rel \
    --ref=${WD}/postmc2struct_warp \
    --warp1=${GradientDistortionField} \
    --warp2=${WD}/postmc2struct_warp \
    -o ${WD}/gdc_dc_warp \
    --jacobian=${WD}/gdc_dc_jacobian
else
  ${FSLDIR}/bin/convertwarp \
    --relout \
    --rel \
    --ref=${fMRIToStructuralInput} \
    --warp1=${GradientDistortionField} \
    --warp2=${fMRIToStructuralInput} \
    -o ${WD}/gdc_dc_warp \
    --jacobian=${WD}/gdc_dc_jacobian
fi
#but, convertwarp's jacobian is 8 frames - each combination of one-sided differences, so average them
${FSLDIR}/bin/fslmaths ${WD}/gdc_dc_jacobian -Tmean ${WD}/gdc_dc_jacobian

#and resample it to MNI space
# Note that trilinear instead of spline interpolation is used with the purpose to minimize the ringing artefacts that occur 
# with downsampling of the jacobian field and are then propagated to the BOLD image itself.
${FSLDIR}/bin/applywarp --rel --interp=trilinear -i ${WD}/gdc_dc_jacobian -r ${WD}/${T1wImageFile}.${FinalfMRIResolution} -w ${StructuralToStandard} -o ${JacobianOut}

verbose_green_echo "---> Finished OneStepResampling_SLOMOCO"

echo " "
echo "END: OneStepResampling_SLOMOCO"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ##########################################

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "cd `pwd`" >> $WD/qa.txt
echo "# Check registrations to low-res standard space" >> $WD/qa.txt
echo "fslview ${WD}/${T1wImageFile}.${FinalfMRIResolution} ${WD}/${FreeSurferBrainMaskFile}.${FinalfMRIResolution} ${WD}/${BiasFieldFile}.${FinalfMRIResolution} ${OutputfMRI}" >> $WD/qa.txt

##############################################################################################


