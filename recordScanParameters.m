function recordScanParameters(hNL, csvFilename, pmtGain, laserPowerBeforePockelsCell, laserWavelength, plateName)
%{
recordScanParameters.m Records the GIZMO scan parameters of the current plate into a .csv file. Run
this function after starting a scan of all the colonies.
Inputs:
    hNL             :   NorthernLights object handle. Just enter 'hNL'.
    csvFilename     :   string, the filename to record the parameters (e.g. 'scans_on_this_date'). 
                        If this matches an already existing file, the parameters will be appended to
                        that file.
    pmtGain         :   float, the gain of the PMT (which was set manually with the knob).
    laserPowerBeforePockelsCell : float or int, the laser power measured before the pockels cell.
    laserWavelength :   The wavelength of the excitation laser.
    plateName       :   (optional) The name of the current plate. If this is not provided, the plate
                        name will be the hNL.logFolder name. 
Outputs:
    None.
Saves:
    'csvFilename'.csv file containing the scan parameters in the parent folder of the 
    hNL.logFolder. If this file already exists, it appends the scan parameters of the current scan
    to that file.
Notes: 
    If plateName is not provided, this assumes that the plate scan is logged into a folder named 
    after the plate. 
%}

% Record the date and time of scan
t = datetime('now');
t = datestr(t);

% Find number of scanned colonies
nScannedColonies = length(hNL.scanableColonyPositions);

folderDividers=strfind(hNL.logFolder,'\');

if ~exist('plateName', 'var')
    % get the plate name based on the folder name.    
    plateName = hNL.logFolder(folderDividers(end)+1:end);
    disp(' ');
    disp(plateName);
end

% Save the scan parameters in the parent folder of the logFolder.
savePath = hNL.logFolder(1:folderDividers(end)-1); 
filename = [savePath '/' csvFilename '.csv'];
fid = fopen(filename,'at');
fileinfo = dir(filename);

% If nothing has been logged in this file yet, add column titles
if fileinfo.bytes == 0
    fprintf(fid, ['Plate, Date and Time of Scan, Total Number of Fluorescent Colonies,',...
        'Laser Wavelength (nm), Laser Power Before Pockels Cell (mW),',...
        'PMT Gain, Logging Directory, Exposure Time (ms), Camera Gain (dB),'... 
        'Min Px Radius, Max Px Radius, 1P Threshold,',...
        'Laser Power (%%), Scan Depth Range (um), Scan Time per Colony (ms), Scan Size (um),',...
        'Minimum Detected Z Position, Maximum Detected Z Position']);
end
fprintf(fid,'\n%s,%s,%d,%d,%d,%.3f,%s,%.2f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f-%.0f,%.0f,%.0f', ...
    plateName, t, nScannedColonies,...
    laserWavelength, laserPowerBeforePockelsCell, ...
    pmtGain, hNL.logFolder, hNL.cameraExposureTime, hNL.cameraGain,...
    hNL.colonyMinRadPx, hNL.colonyMaxRadPx, hNL.colonyThreshold,...
    hNL.lineLaserPower, hNL.scanDepthRange(1), hNL.scanDepthRange(2), hNL.scanTime, hNL.scanSize);

% If z position was auto-detected, record the min and max detected z positions
if ~isempty(hNL.zTestColonies)
    fprintf(fid,',%.0f,%.0f', ...
        min(hNL.zTestColonies(:,3)), max(hNL.zTestColonies(:,3)));
end
fclose(fid);

% Print to command window the estimated scan time based on the number of colonies
fprintf('\nEstimated scan time is %.2f minutes.\n\n', 2.8/100*nScannedColonies);

end