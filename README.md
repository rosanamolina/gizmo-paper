# gizmo-paper
Software and analysis programs for the GIZMO

`NorthernLights.m` is the main instrument software. Needs a legacy version of ScanImage (available for purchase from to run properly [Vidrio Technologies](https://vidriotechnologies.com/)).
Note that it also requires `tspsearch.m` which can be downloaded from [MATLAB File Exchange](https://www.mathworks.com/matlabcentral/fileexchange/71226-tspsearch).

`NorthernLightsGui.m` is software to setup the GUI.

`NorthernLightsDataViewer.m` is the GUI to view the plate and select colonies based on their indices.

`fixScannerOffsets.m` is a supplementary function to align the GUI plate image to the stage transform.

`recordScanParameters.m` is a supplementary function to record the scan parameters in a .csv file before scanning all colonies on a plate.

`summarizeScans.m` is an analysis function to summarize the colony scan data from a plate and identify the brightest colonies.

`summarizeSequences.m` is an analysis function to summarize the sequencing data of the top colonies from a round of evolution and identify unique mutants.
