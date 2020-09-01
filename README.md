# gizmo-paper
Software and analysis programs for the GIZMO, as described in
## High throughput instrument to screen fluorescent proteins under two-photon excitation
Rosana S. Molina1, Jonathan King2, Jacob Franklin2, Nathan Clack2, Christopher McRaven3,4, 
Vasily Goncharov3, Daniel Flickinger3, Karel Svoboda3, Mikhail Drobizhev1, Thomas E. Hughes1

1Department of Cell Biology & Neuroscience, Montana State University, 109 Lewis Hall, Bozeman, MT 59717, USA\
2Vidrio Technologies, LLC., PO Box 1870, Leesburg, VA 20177, USA\
3Janelia Research Campus, 19700 Helix Dr, Ashburn, VA 20147, USA\
4Current address: Advanced Engineering Laboratory, Woods Hole Oceanographic Institution, 86 Water St, Woods Hole, MA 02543, USA

`NorthernLights.m` is the main instrument software. Needs a legacy version of ScanImage (available for purchase from to run properly [Vidrio Technologies](https://vidriotechnologies.com/)).
Note that it also requires `tspsearch.m` which can be downloaded from [MATLAB File Exchange](https://www.mathworks.com/matlabcentral/fileexchange/71226-tspsearch).

`NorthernLightsGui.m` is software to setup the GUI.

`NorthernLightsDataViewer.m` is the GUI to view the plate and select colonies based on their indices.

`fixScannerOffsets.m` is a supplementary function to align the GUI plate image to the stage transform.

`recordScanParameters.m` is a supplementary function to record the scan parameters in a .csv file before scanning all colonies on a plate.

`summarizeScans.m` is an analysis function to summarize the colony scan data from a plate and identify the brightest colonies.

`summarizeSequences.m` is an analysis function to summarize the sequencing data of the top colonies from a round of evolution and identify unique mutants.
