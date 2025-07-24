# SLOMOCO_HCP
bash scripts of SLOMOCO for HCP pipeline

Instruction to add SLOMOCO_HCP
1. Download the files and save them in your local
2. Add the following in SetupHCPPipeline.sh
export SLOMOCOHCPDIR="<your SLOMOCO_HCP directory>"
export SLIACQTIME=${SLOMOCOHCPDIR}/SliceAcqTime_3T_TR720ms.txt 
3. Modify GenericfMRIVolumeProcessingPipeline.sh
The example of the modified GenericfMRIVolumeProcesesingPipeline.sh
(from HCPpipeline-5.0.0) is included.
Find the modification with a search word of "SLOMOCOHCPDIR" 
4. SLOMOCO output is ${fMRIFolder}/${NameOffMRI}_slomoco_nonlin_norm.nii.gz or
   ${ResultsFolder}/${NameOffMRI}_slomoco.nii.gz
5. SLOMOCO algorithm utilzes 12 rigid volume/slice motion nuissance
   and voxelwise partial volume nusance regressors (total 13), not using FIXICA.
   13 nuisannce regressors are removed in "PostSLOMOCO.sh"
6. Final SLOMOCO output after regression out is XXX
7. SLOMOCO is not prepared for multi-echo data yet, e.g. ${nEcho} > 1
8. If you are running non 3T WU_MINN_HCP data, e.g. 7T,
   store a slice acquisition timing file and update "SLIACQTIME" in step2

Please cite the followings if you use SLOMOCO_HCP
1) Shin W., Taylor P., Lowe MJ., Estimation and Removal of Residual Motion Artifact in 
Retrospectively Motion-Corrected fMRI Data: A Comparison of Intervolume and Intravolume 
Motion Using Gold Standard Simulated Motion Data. 2024 Neuro Aperture, 2024; 4
https://doi.org/10.52294/001c.123369

2) Beall EB, Lowe MJ. SimPACE: generating simulated motion corrupted BOLD data with 
synthetic-navigated acquisition for the development and evaluation of SLOMOCO: a new, 
highly effective slicewise motion correction. Neuroimage. 2014 Nov 1;101:21-34. 
