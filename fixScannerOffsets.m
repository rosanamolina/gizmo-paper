function fixScannerOffsets(hNL)
%fixScannerOffsets.m Auto-sets the stage offsets in NorthernLights to match
%the GUI image to the stage position.
%   - To use this function, first manually move the stage to a position by
%   right clicking a position on the GUI image and selecting "Move Stage
%   Here." It's best to find a large colony or blob of E. coli, so that you
%   are more likely to be at an XY position where there are bacteria even
%   though the scanner offsets are off.
%   - Then, adjust the Z stage position until you can observe fluorescence
%   in "Focus" mode.
%   - Then, (with laser safety glasses on!!) visually observe where the
%   fluorescent point is on the plate, and manually add a colony at that
%   position on the GUI image. 
%   - Then, call fixScannerOffsets(hNL) to adjust the offsets. The command
%   window will display the new hNL.scannerYPosOffset and
%   hNL.scannerXPosOffset to copy and paste into the properties around line
%   120 in NorthernLights.m
%   - Finally, double check that the actual stage position and the GUI
%   image stage position match. You can do this by moving the stage to a
%   distinguishable spot (like the center of a small colony) and visually
%   observing that the fluorescent point is at the expected position. If
%   not, repeat the above steps until it is.


% Adjust the offsets
actual = hNL.stagePosition;
image = hNL.scanableColonyPositions(end,:);
offset = actual - image;
hNL.scannerYPosOffset = hNL.scannerYPosOffset + offset(1);
hNL.scannerXPosOffset = hNL.scannerXPosOffset + offset(2);

% Display new offsets in command window
xOffset = num2str(round(hNL.scannerXPosOffset));
yOffset = num2str(round(hNL.scannerYPosOffset));
date = datestr(now,'mm/dd/yy');
disp('Copy and paste the following into NorthernLights.m around line 120:');
disp(['scannerXPosOffset = ' xOffset '; % Adjusted ' date]);
disp(['scannerYPosOffset = ' yOffset '; % Adjusted ' date]);
end