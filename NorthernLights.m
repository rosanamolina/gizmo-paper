classdef NorthernLights < most.AppConfiguration
    
    properties (SetObservable)
        status = 'Idle';
        samplePosition = 'camera';
        stageTarget = [0 0 0];
        stagePosition = [0 0 0];
        
        cameraLive = false;
        illuminatorActive = false;
        illuminatorIntensityFraction = 0.2;
        
        scanDepthRange = [0 400];
        
        colonyPositions = [];
        zTestColonies = [];
        
        rasterNumSlices = 20;
        
        scanTime = 100; %ms
        scanSize = 200; %um 
        
        liveFramePeriod = 0.1;
        cameraExposureTime;
        cameraGain;
        lastLiveFrame;
        
        ssFrameData = {};
        ssStagePos = {};
        
        enableSnapShotTile = true;
        snapShotTileSize = 2;
        snapShotTileOverlap = 0.5;
        
%         colonyDiameterMin_px = 10;
%         colonySolidityMin_pct = 0.8;

        colonyMinRadPx = 4; 
        colonyMaxRadPx = 25; 
        colonyThreshold = 300; 
        
        bleachPass = 1;
        totalBleachPasses = 4;
        bleachingPowers = [0 15 30 60];
        bleachingModeActive = false;
        bleachSingleMode = false;
        bleachFinished = true;
        
        numSnapAvg = 10;
        
        % cameraToStageTransform is in units of um per fov 
        % (total image width)
        cameraToStageTransform = [68800 0 0; 0 68600 0; 0 0 1];
        
        enableLogging = true;
        
        % Set logFolder for default save location
        logFolder = '.';
        
        scanMode = 'line';
        
        frameLaserPower = 40; 
        lineLaserPower = 5; 
        pointLaserPower = 30; % For bleaching
        
        findZMinPos = 300; 
        findZMaxPos = 1350; 
        findZStepSize = 300;
        findZActive = false;
        colonyFound = false;
        startGrabFlag = true;
        
        maxSafeZ = 10500;
        
    end
    
    properties (Hidden)
        hSI;
        hTimer;
        hSpin;
        hMotors;
        hFpgaDaq;
        hZaber;
        hGrabTimer;
    end
    
    % status properties
    properties (Hidden)
        scanIter;
        abortReq = false;
        homePosition = [0 0 0];
        colonyScanning = false;
        laserPower;
        
        debugActive = false;
    end
    
    % configuration properties
    properties (Hidden)
        siMdf = '';
        
        scannerResolution = 60; %um/deg
        
        illuminatorDaq = '';
        illuminatorEnableDO = '';
        illuminatorIntensityAOChan = []; % The AO channel identity for the illuminator
        hTaskIlluminatorEnable;
        hTaskIlluminatorIntensity;
        
        zaberComPort = [];
    end
    
    properties (Constant)
        configurationSchema = initCfgSchema();
        cfgExtension = '.nlcfg';
    end
    
    properties (SetObservable)
        zaberScanPos = 49350;
        zaberCamPos = 262000;
        scannerYPosOffset = -3700; % May have to adjust this via separate fixScannerOffsets function
        scannerXPosOffset = -3700; % May have to adjust this via separate fixScannerOffsets function
        objectiveLensRadius = 12000; %um
        dishSize = 101000; 
        dishCenter = [0 0];
        scanableColonyPositions = [];
        oobColonyPositions = [];
        
        zTimeStamps = {};
       
    end
    
    %% LIFECYCLE
    methods (Static)
        function launch
            %#function NorthernLights
            %#function NorthernLightsGui
            if ~evalin('base','exist(''hNL'')') || ~most.idioms.isValidObj(evalin('base','hNL'))
                evalin('base','hNL = NorthernLights;');
            end
            
            if evalin('base','exist(''hNL'')') && most.idioms.isValidObj(evalin('base','hNL'))
                if evalin('base','exist(''hNLGUI'')')
                    hNLGUI = evalin('base','hNLGUI');
                    if most.idioms.isValidObj(hNLGUI)
                        figure(hNLGUI.hFig);
                        return;
                    end
                end

                evalin('base','hNLGUI = NorthernLightsGui(hNL);');
            end
        end
    end
    
    methods
        function obj = NorthernLights()
            obj.loadSettings();
            
            disp('Starting ScanImage...');
            obj.hSI = scanimage.SI(obj.siMdf);
            obj.hSI.initialize();
            assignin('base','hSI',obj.hSI);
            
            if obj.hSI.fpgaMap.isKey('RIO0')
                obj.hFpgaDaq = dabs.ni.rio.fpgaDaq.fpgaDaq(obj.hSI.fpgaMap('RIO0').hFpga,'NI7855');
            end
            
            % set zero of stage
            obj.hMotors = {obj.hSI.hMotors.hMotor.hLSC};
            obj.hSI.hMotors.setMotorZero([50000 50000 0]);
            
            addlistener(obj.hSI.hUserFunctions, 'acqDone', @obj.endOfAcq);
            addlistener(obj.hSI.hUserFunctions, 'acqAbort', @(varargin)obj.abort(false));
            
            obj.hGrabTimer = timer('Name','Bleach Start Timer');
            obj.hGrabTimer.ExecutionMode = 'singleShot';
            obj.hGrabTimer.StartDelay = 0.5;
            obj.hGrabTimer.TimerFcn = @(varargin)obj.primeNextGrab;

            fprintf('Launching Spinnaker...');
            try
                obj.hSpin = dabs.Spinnaker.Camera();
                obj.hTimer = timer('Name','Cam Grab Timer','TimerFcn',@(varargin)obj.getFrame(),'ExecutionMode','fixedSpacing','Period',obj.liveFramePeriod);
            catch ME
               warning(ME.message); 
            end
            fprintf('Done!\n');
            
            obj.moveStage([nan nan 0]);
            
            %init zaber here instead of SI
            if ~isempty(obj.zaberComPort)
                obj.hZaber = dabs.zaber.XLRQ300('comport',obj.zaberComPort);
            else
                obj.hZaber = XLRQ300;
            end
            
            obj.updateStagePosition();
            obj.samplePosition = 'camera';
            
            
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hTimer);
            most.idioms.safeDeleteObj(obj.hFpgaDaq);
            
            if most.idioms.isValidObj(obj.hSI)
                obj.hSI.exit();
            end
            
            most.idioms.safeDeleteObj(obj.hSpin);
            
            most.idioms.safeDeleteObj(obj.hTaskIlluminatorEnable);
            most.idioms.safeDeleteObj(obj.hTaskIlluminatorIntensity);
            most.idioms.safeDeleteObj(obj.hZaber);
        end
        
        function exit(obj)
            delete(obj);
            evalin('base','clear hNL hNLGUI');
        end
    end
    
    %% CONFIGURATION
    methods
        function loadSettings(obj)
            obj.appConfigFileCachePath = fullfile(fileparts(mfilename('fullpath')),'NorthernLightsConfigPath.txt');
            obj.loadAppConfiguration();
        end
    end
    
    %% USER METHODS
    methods
        function setupScan(obj,N)
            
            if strcmp(obj.scanMode,'line')
                if obj.findZActive
                    % Setup - Scan at a time, no looping
                    obj.hSI.hStackManager.framesPerSlice = 1;
                    obj.hSI.acqsPerLoop = 1;
                    obj.hSI.hScan2D.trigAcqInTerm = 'PFI0';
                    obj.hSI.extTrigEnable = false;
                    
                    % Setup acquisition
                    obj.hSI.hScan2D.sampleRate = 1000000;
%                     obj.bleachSingleMode = false;
                    obj.hSI.hRoiManager.scanType = 'line';
                    rg = scanimage.mroi.RoiGroup;
                    
                    % Create spiral ROI
                    roi = scanimage.mroi.Roi;
                    sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.zspiral,{'revolutions', 5, 'zrepeats', 10},...
                        obj.scanTime*0.001,1,[0 0], [.5 .5] .* obj.scanSize / obj.scannerResolution,0,[],obj.scanDepthRange(2) - obj.scanDepthRange(1));
                    roi.add(obj.scanDepthRange(1),sf);
                    rg.add(roi);
                    
                    % Create pause
                    roi = scanimage.mroi.Roi;
                    sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.pause,{},0.0005,1,[0 0],[16 16],0,20);
                    roi.add(obj.scanDepthRange(1),sf);
                    rg.add(roi);
                    
                    % Set ROI Line scan Group to the above
                    obj.hSI.hRoiManager.roiGroupLineScan = rg;
                    
                    % Set volume parameters
                    obj.hSI.hStackManager.numSlices = 1;
                    obj.hSI.hFastZ.enable = true;
                    
                    % Set laser power
                    obj.hSI.hBeams.powers = obj.lineLaserPower;
                    
                    % Set Log File Name for Z Find Scans
                    obj.hSI.hScan2D.logFileStem = sprintf('Colony %d of %d', obj.scanIter, size(obj.zTestColonies,1));
                    
                % Regular Line(Spiral) Scan
                else
                    obj.hSI.hStackManager.framesPerSlice = 1;
                    obj.hSI.acqsPerLoop = N;
                    obj.hSI.hScan2D.trigAcqInTerm = 'PFI0';
                    obj.hSI.extTrigEnable = true;

                    obj.hSI.hScan2D.sampleRate = 1000000;
                    obj.bleachSingleMode = false;
                    obj.hSI.hRoiManager.scanType = 'line';
                    rg = scanimage.mroi.RoiGroup;

                    roi = scanimage.mroi.Roi;
                    sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.zspiral,{'revolutions', 5, 'zrepeats', 10},...
                        obj.scanTime*0.001,1,[0 0], [.5 .5] .* obj.scanSize / obj.scannerResolution,0,[],obj.scanDepthRange(2) - obj.scanDepthRange(1));
                    roi.add(obj.scanDepthRange(1),sf);
                    rg.add(roi);

                    roi = scanimage.mroi.Roi;
                    sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.pause,{},0.0005,1,[0 0],[16 16],0,20);
                    roi.add(obj.scanDepthRange(1),sf);
                    rg.add(roi);

                    obj.hSI.hRoiManager.roiGroupLineScan = rg;
                    obj.hSI.hStackManager.numSlices = 1;
                    obj.hSI.hFastZ.enable = true;

                    obj.hSI.hBeams.powers = obj.lineLaserPower;
                    
%                     obj.hSI.hScan2D.logFileStem = 'colony';
                end
                
            % Photo-beaching mode
            elseif strcmp(obj.scanMode,'point')
                % Setup - 1 "frame", no looping
                obj.hSI.hStackManager.framesPerSlice = 1;
                obj.hSI.acqsPerLoop = 1;
                obj.hSI.hScan2D.trigAcqInTerm = 'PFI0';
                obj.hSI.extTrigEnable = false;
                
                % Setup acquisition
                obj.hSI.hDisplay.lineScanHistoryLength = 100;
                obj.hSI.hScan2D.sampleRate = 250000;%500000;
                obj.hSI.hRoiManager.scanType = 'line';
                
                % Setup POINT Scan ROI
                rg = scanimage.mroi.RoiGroup;
                
                % Point Scan for photobleaching
                roi = scanimage.mroi.Roi;
                % StimulusField(stimfcnhdl,stimparams,duration,repetitions,centerXY,scalingXY,rotationDegrees,powers,zSpan)
                sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.point,{'revolutions', 5},...
                    obj.scanTime*0.001,1,[0,0],[1,1],0,[]); % Leave bleach power as [] to use current power setting?
                roi.add(0,sf);
                rg.add(roi);
                
                % Pause
                roi = scanimage.mroi.Roi;
                sf = scanimage.mroi.scanfield.fields.StimulusField(@scanimage.mroi.stimulusfunctions.pause,{},0.0005,1,[0 0],[16 16],0,1);
                roi.add(0,sf);
                rg.add(roi);
                
                
                obj.hSI.hRoiManager.roiGroupLineScan = rg;
                obj.hSI.hStackManager.numSlices = 1;                
                obj.hSI.hBeams.powers = obj.bleachingPowers(obj.bleachPass);
                
            % Raster Frame Scan
            else
                obj.hSI.hStackManager.framesPerSlice = 1;
                obj.hSI.acqsPerLoop = N;
                obj.hSI.hScan2D.trigAcqInTerm = 'PFI0';
                obj.hSI.extTrigEnable = true;
                
                obj.hSI.hScan2D.sampleRate = 1000000;
                obj.bleachSingleMode = false;
                obj.hSI.hRoiManager.scanType = 'frame';
                obj.hSI.hFastZ.enable = false;
                obj.hSI.hScan2D.pixelBinFactor = 2;
                
                obj.hSI.hStackManager.slowStackWithFastZ = true;
                obj.hSI.hStackManager.shutterCloseMinZStepSize = 100;
                obj.hSI.hStackManager.stackStartCentered = false;
                
                obj.hSI.hStackManager.numSlices = obj.rasterNumSlices;
                if obj.rasterNumSlices > 1
                    obj.hSI.hStackManager.stackZStepSize = diff(obj.scanDepthRange) / (obj.rasterNumSlices - 1);
                end
                
                obj.hSI.hBeams.powers = obj.frameLaserPower;
            end
            
            if obj.enableLogging
                if isempty(obj.logFolder)
                    f = pwd;
                else
                    if obj.findZActive
                        f = [obj.logFolder '\Z Find'];
                    elseif strcmp(obj.scanMode,'point')
                        f = [obj.logFolder '\Photobleaching'];
                    else
                        f = [obj.logFolder '\Scan Data'];
                    end
                end
                obj.hSI.hChannels.loggingEnable = obj.enableLogging;
                nm = datestr(now,'dd_mmm_yyyy_HHMMSS'); 
                obj.hSI.hScan2D.logFilePath = fullfile(f, nm);
                if ~exist(obj.hSI.hScan2D.logFilePath,'file')
                    mkdir(f,nm);
                end
                obj.hSI.hScan2D.logFileStem = 'colony';
                obj.saveMetaData(obj.hSI.hScan2D.logFilePath);
            else
                obj.hSI.hChannels.loggingEnable = obj.enableLogging;
            end
        end
        
        function startFocus(obj,i)
            % Verify Zaber Position
            if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                if strcmp(choice, 'Yes')
                    obj.samplePosition = 'scanner';
                    while obj.hZaber.isMoving
                        pause(0.01);
                        obj.status = 'Moving sample....';
                    end
                    obj.status = 'Idle';
                else
                    return;
                end
            end
            
            if nargin > 1 && ~isempty(i)
                % move to colony i
            end
            
            obj.setupScan(1);
            obj.hSI.extTrigEnable = false;
            
            if strcmp(obj.scanMode,'line')
                obj.hSI.hStackManager.framesPerSlice = inf;
                obj.hSI.hChannels.loggingEnable = false;
                obj.hSI.startGrab();
            else
                obj.hSI.startFocus();
            end
        end
        
        function scanSingleColony(obj,i)
            % Verify Zaber Position
            if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                if strcmp(choice, 'Yes')
                    obj.samplePosition = 'scanner';
                    while obj.hZaber.isMoving
                        pause(0.01);
                        obj.status = 'Moving sample....';
                    end
                    obj.status = 'Idle';
                else
                    return;
                end
            end
            
            if nargin > 1 && ~isempty(i)
                % move to colony i
            end

            obj.setupScan(1);
            obj.hSI.extTrigEnable = false;
            obj.hSI.startGrab();
        end
        
        function scanAllColonies(obj)
            if ~isempty(obj.scanableColonyPositions)
                
                % Verify Zaber Position
                if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                    choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                    if strcmp(choice, 'Yes')
                        obj.samplePosition = 'scanner';
                        while obj.hZaber.isMoving
                            pause(0.01);
                            obj.status = 'Moving sample....';
                        end
                        obj.status = 'Idle';
                    else
                        return;
                    end
                end
                
                obj.scanIter = 1;
                obj.homePosition = obj.hSI.hMotors.motorPosition;
                pause(0.1);
                
                % setup scan
                obj.optimizeScanOrder();
                obj.setupScan(size(obj.scanableColonyPositions,1));
                pause(0.1);
                
                % start the scan
                obj.hSI.startLoop();
                obj.colonyScanning = true;
                pause(0.5);
                obj.startNextColony();
            end
        end
        
        % Function to begin photobleaching passes on a single colony. Assumes
        % colony is at your current position, i.e. will not move to colony.
        function bleachSingle(obj)
            % Verify Zaber Position
            if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                if strcmp(choice, 'Yes')
                    obj.samplePosition = 'scanner';
                    while obj.hZaber.isMoving
                        pause(0.01);
                        obj.status = 'Moving sample....';
                    end
                    obj.status = 'Idle';
                else
                    return;
                end
            end
                
            % Setup Point Bleach

            % Flag which tracks whether we are currently
            % photobleaching. Use to distinguish behavior from
            % non-bleaching modes
            obj.bleachingModeActive = true;

            % Flag which states that we are only bleaching 1 colony.
            % Distinguishes behavior
            obj.bleachSingleMode = true;

            % Set ScanIter to 1. Used to track scanning across multiple
            % colonies
            obj.scanIter = 1;

            % Set current pass number to. Used to track number of
            % passes over the same colony. 
            obj.bleachPass = 1;

            % Cache current stage position
            obj.homePosition = obj.stagePosition;
            pause(0.1);

            % Sets up Scan: Sets scan mode, creates ROI, sets power
            obj.setupScan(1);

            % Setup log file
            str = sprintf('Colony_%d_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%', 1,1,obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
            obj.hSI.hScan2D.logFileStem = str;
            pause(0.1);

            % Start scan procedure
            obj.startNextColony();
        end
        
        function startBleaching(obj)
            if ~isempty(obj.scanableColonyPositions)
                % Verify Zaber Position
                if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                    choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                    if strcmp(choice, 'Yes')
                        obj.samplePosition = 'scanner';
                        while obj.hZaber.isMoving
                            pause(0.01);
                            obj.status = 'Moving sample....';
                        end
                        obj.status = 'Idle';
                    else
                        return;
                    end
                end
                
                obj.bleachingModeActive = true;
                obj.bleachSingleMode = false;
                obj.scanIter = 1;
                obj.bleachPass = 1;
                
                obj.homePosition = obj.hSI.hMotors.motorPosition;
                pause(0.1);
                
                % setup scan
%                 obj.setupScan(size(obj.scanableColonyPositions,1)*obj.totalBleachPasses);
                obj.setupScan(1);
                pause(0.1);
                
                % Setup log file
%                 str = sprintf('Colony_%d_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%', 1,size(obj.scanableColonyPositions,1),obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
                s = [sprintf('Colony_%%0%dd', numel(num2str(size(obj.scanableColonyPositions,1)))) '_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%'];
                str = sprintf(s, 1,size(obj.scanableColonyPositions,1),obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
                obj.hSI.hScan2D.logFileStem = str;
                
                pause(0.1);
                obj.startNextColony();
            end
        end
        
        function saveMetaData(obj,path)
            if nargin < 2 || isempty(path)
                path = pwd;
            end
            
            % save northern lights configuration info
            metaDataPropSet = obj.buildAppPropSet(initMetaDataSchema());
            most.json.savejson([],metaDataPropSet,fullfile(path,'NorthernLightsCfg.meta.txt'));
            
            % save image snapshots
            imageData = obj.ssFrameData;
            stagePositions = obj.ssStagePos;
            cameraToStageTransform = obj.cameraToStageTransform;
            save(fullfile(path,'SnapShotImages.mat'),'imageData','stagePositions','cameraToStageTransform');
        end
        
        function abort(obj,abortSI)
            if nargin < 2 || isempty(abortSI) || abortSI
                obj.hSI.abort();
            else
                if ~obj.findZActive
                    obj.status = 'Idle';
                end
            end

            obj.bleachingModeActive = false; 
            obj.colonyScanning = false;
        end
        
        function updateStagePosition(obj)
            obj.hSI.hMotors.recover();
            
            if strcmp(obj.samplePosition, 'scanner')
                offs = [obj.scannerYPosOffset obj.scannerXPosOffset 0];
            else
                offs = 0;
            end
            
            obj.stagePosition = obj.hSI.hMotors.motorPosition - offs;
        end
        
        function moveStage(obj,newpos,blocking)
            if nargin < 3
                blocking = true;
            end
            
            if newpos(end) > obj.maxSafeZ
               newpos(end) = obj.maxSafeZ; 
            end
            
            obj.stageTarget = newpos;
            if strcmp(obj.samplePosition, 'scanner')
                newpos = newpos + [obj.scannerYPosOffset obj.scannerXPosOffset 0];
            end
            drawnow();
            
            if blocking
                % Command stages to newpos
                obj.hSI.hMotors.motorPosition = newpos;
                % Timestamp initial command
                t_init = tic;
                t_total = t_init;
                
                % While the stage is not at the commanded position (still
                % moving or cut out early)
%                 while any(obj.hSI.hMotors.motorPosition < newpos - 5) || any(obj.hSI.hMotors.motorPosition > newpos + 5)
%                     % Let it try for 5 secs before re-ordering the command,
%                     % in theory it should eventually make it to within
%                     % target and exit this loop. Otherwise keep trying...
%                     if toc(t_init) > 5
%                         obj.hSI.hMotors.motorPosition = newpos;
%                         t_init = tic;
%                     end
%                     
%                     if toc(t_total) > 30
%                        disp('Move Failed?');
%                        fprintf('Final position actual: [%.2f %.2f %.2f]\n Desired position: [%.2f %.2f %.2f]\n', obj.hSI.hMotors.motorPosition, newpos);
%                        break;
% %                        return;
%                     end
%                     pause(0.2);
%                 end
                curpos=obj.hSI.hMotors.motorPosition;
                dr=curpos-newpos;
                dr(isnan(dr))=0;
                distance_um=sqrt(sum(dr.^2));
                tmove=tic;
                total_time=0;
                while distance_um>10 && total_time < 10 
                    
                    curpos=obj.hSI.hMotors.motorPosition;
                    dr=curpos-newpos;
                    dr(isnan(dr))=0;
                    distance_um=sqrt(sum(dr.^2));
                    pause(0.001);
                    total_time=total_time+toc(tmove);
                    tmove=tic;
                    obj.hSI.hMotors.hMotor(1).hLSC.stop();
                    obj.hSI.hMotors.hMotor(2).hLSC.stop();
                    pause(0.01);
                    obj.hSI.hMotors.motorPosition = newpos;
                end
                
                if total_time>=10
                    warning('STAGE motion did not reach target');
                    obj.hSI.hMotors.hMotor(1).hLSC.stop();
                    obj.hSI.hMotors.hMotor(2).hLSC.stop();
                end
                
                obj.hSI.hMotors.hMotor(1).hLSC.stop();
                obj.hSI.hMotors.hMotor(2).hLSC.stop();
                
                obj.updateStagePosition();
            else
                obj.hSI.hMotors.moveStartRelative(newpos);
                pause(0.1);
            end
        end
        
        function snapShot(obj)
            if obj.enableSnapShotTile
                obj.ssFrameData = {};
                obj.ssStagePos = {};
                nd = (obj.snapShotTileSize-1)*mean(obj.cameraToStageTransform([1,5]))*(1-obj.snapShotTileOverlap)/2;
                crds = linspace(-nd,nd,obj.snapShotTileSize);
                xcrds = obj.stagePosition(1) + crds;
                ycrds = obj.stagePosition(2) + crds;
                m = [];
                
                obj.homePosition = obj.stagePosition;
                for i = xcrds
                    for j = ycrds
                        obj.status = 'Moving to next snap shot position...';
                        obj.moveStage([i j nan]);
                        obj.status = 'Capturing image...';
                        drawnow('nocallbacks');
                        obj.singleSnapShot();
                        m(end+1,:) = [i j];
                    end
                    ycrds = fliplr(ycrds);
                end
                obj.status = 'Returning home...';
                obj.moveStage([obj.homePosition(1:2) nan]);
                obj.abort();
                
                obj.cameraToStageTransform = pixelsToStageTransform(obj.ssFrameData,m);
                
               %Save snapshot
%                 imageData = obj.ssFrameData;
%                 stagePositions = obj.ssStagePos;
%                 cameraToStageTransform = obj.cameraToStageTransform;
%                 save(fullfile(obj.logFolder,'SnapShotImages.mat'),'imageData')%,'stagePositions','cameraToStageTransform');
%                 
            else
                obj.singleSnapShot();
            end
        end
        
        function singleSnapShot(obj)
            obj.illuminatorActive = true;
            pause(0.05);
            obj.ssFrameData{end+1} = obj.hSpin.snapshot;
            obj.ssStagePos{end+1} = obj.stagePosition;
            pause(0.05);
            obj.illuminatorActive = false;
        end
        
        function autoSelect(obj, img, coords)
            % This gets called once per tile
            assert(nargin > 2 && ~isempty(coords) && ~isempty(img),...
                'No image coordinates provided. Image assumed to be at motor coords.');
                
            if nargin < 2 || isempty(img)
                if ~isempty(obj.lastLiveFrame)
                    im = obj.lastLiveFrame;
                elseif ~isempty(obj.ssFrameData)
                    im = obj.ssFrameData{end};
                else
                    msgbox('A reference image is needed to detect colonies. Please take a snap shot or live image.', 'Auto Colony Detection', 'warn');
                    return;
                end
            else
                im = img;
            end
            
            warning('off');
            [centroids, ~] = findColonesAlt(im, obj.colonyMinRadPx, obj.colonyMaxRadPx, obj.colonyThreshold);
            warning('on');
            warning('off', 'MATLAB:subscripting:noSubscriptsSpecified');
%             [centroids, ~] = findcolonies(im, obj.colonyDiameterMin_px, obj.colonySolidityMin_pct);

            % image transform: maps field-of-view to it's location in stage
            % space
            imageTransform=diag(1./[size(im) 1]);
            imageTransform(1:2,3)=[-0.5 -0.5];
            
            centers = scanimage.mroi.util.xformPoints(centroids,obj.cameraToStageTransform*imageTransform);
                                   
            centers(:,1) = centers(:,1) + coords(1);
            centers(:,2) = centers(:,2) + coords(2);

            numCenters = size(centers, 1);
            
            for i = 1:numCenters
                obj.addColony([centers(i,:) obj.stagePosition(3)]);
            end
            
        end
        
        function optimizeScanOrder(obj)
            disp('Optimizing colony scan order, please wait...');
            tic
            r = obj.scanableColonyPositions;
            % reorder for optimized scan
            % using an approximate traveling-salesman solver
            try 
                if ~isempty(r)
                    [p,~] = tspsearch(r(:,1:2),3);
                    r=r(p,:);
                    obj.scanableColonyPositions = r;
                end
            catch e                    
                warning(e)
                disp('Scan path optimization failed for some reason.');
            end
            toc
        end
        
        function startZFind(obj)
            if ~isempty(obj.scanableColonyPositions) && ~isempty(obj.zTestColonies)
                % Verify Zaber Position
                if strcmp(obj.samplePosition, 'camera') || ~strcmp(obj.samplePosition, 'scanner')
                    choice = questdlg('The sample must be moved to the 2P side before proceeding. Move now?', 'Sample Position', 'Yes', 'No', 'Yes');
                    if strcmp(choice, 'Yes')
                        obj.samplePosition = 'scanner';
                        while obj.hZaber.isMoving
                            pause(0.01);
                            obj.status = 'Moving sample....';
                        end
                        obj.status = 'Idle';
                    else
                        return;
                    end
                end
                
                % Ensure Minimum number of test colonies
                assert(size(obj.zTestColonies,1) > 3, 'There must be at least 4 Z Test Colonies to correctly interpolate Z positions');
                
                % Set scan iterations to 1
                obj.scanIter = 1;
                
                % Set correct scan mode - spiral Z scan
                obj.scanMode = 'line';
                
                % Set flag denoting Z find mode
                obj.findZActive = true;
                
                % Cache current stage position
                obj.homePosition = obj.stagePosition;
                
                % Set up scan parameters
                obj.setupScan(1);
                
                % Move stage to first colony
                obj.moveStage([obj.zTestColonies(obj.scanIter,1:2), obj.findZMinPos], true);
                
                % Start Scanning
                obj.startNextColony();
            end
        end
                
    end
    
    %% INTERNAL METHODS
    methods
        function primeNextGrab(obj)
            obj.hSI.startGrab();
        end
        
        function handleZFind(obj)
            % Scan has completed, check data. 
            [found, z, adjust] = obj.detectZ();
            obj.colonyFound = found;

            % Colony has been found: Set the test colonies Z position,
            % display the zFind data, update scan iteration to scan the
            % next colony, start scanning of next colony.
            if obj.colonyFound 

                %Check if this is the first colony. Then
                %adjust the minimum z based on what the z was.
                if obj.scanIter == 1
                    if z > 200
                        obj.findZMinPos = z - 200;
                    else
                        obj.findZMinPos = 0;
                    end
                end
                
                obj.zTestColonies(obj.scanIter,3) = z; 
                
                % Display some Z find data
                lastFramePointer = obj.hSI.hDisplay.lineScanLastFramePtr;
                imgDataStructRaw = obj.hSI.hDisplay.lineScanAvgDataBuffer;
                frameData = imgDataStructRaw(:,lastFramePointer);
                plotName = sprintf('Colony %d of %d [%.3f %.3f %.0f], z set @ %.0f, %s', obj.scanIter,...
                    size(obj.zTestColonies, 1),obj.zTestColonies(obj.scanIter,1),obj.zTestColonies(obj.scanIter,2),...
                    z, obj.zTestColonies(obj.scanIter,3), char(datetime(clock)));
                disp('plotting z data');
                figure('Name', plotName)
                plot(frameData);
              
                % Update scanIteration to point to next colony
                obj.scanIter = obj.scanIter + 1;
                
                % Start Scanning
                obj.findZActive = ~obj.startNextColony();
                
                % Colony not been found: Determine if we are at the end
                % of the scan range, make adjustments to the zPosition,
                % scan again.
            else
                % We are not at at the end of the scan range, so adjust
                % and scan again.
                
                if obj.stagePosition(end) < obj.findZMaxPos
                    if isempty(adjust)
                        %Make sure the next step doesn't go over the set stage limit.
                        if obj.stagePosition(end)+obj.findZStepSize <= obj.findZMaxPos
                            newZ = obj.stagePosition(end)+obj.findZStepSize;
                        else
                            newZ = obj.findZMaxPos;
                        end
                        
                        obj.moveStage([nan nan newZ], true);
                    elseif adjust == 1
                        newZ = obj.stagePosition(end)+150; %100;
                        obj.moveStage([nan nan newZ], true);
                    elseif adjust == -1
                        newZ = obj.stagePosition(end)-150; %100;
                        obj.moveStage([nan nan newZ], true);
                    end
                    % Let the stage move before starting again.
                    pause(0.5);
                    
                    obj.findZActive = ~obj.startNextColony();
                    % We have reached the end of the scan range and have
                    % not found the colony. Set the z position for this
                    % zTestColony to nan (don't know), update scan
                    % iteration to scan again.
                else
                    % Commented out the next three lines so that if the colony is not
                    % found it aborts and does not move on to the next colony
                    %                     obj.zTestColonies(obj.scanIter,3) = nan;
                    %                     obj.scanIter = obj.scanIter + 1;
                    %                     obj.findZActive = ~obj.startNextColony();
                    if obj.findZActive
                        obj.findZActive = false;
                    end
                    obj.status = 'Z position not found. Returning home...'; 
                    obj.moveStage([obj.homePosition(1:2) nan]); 
                    obj.abort(); 
                    s = sprintf('%d of %d', obj.scanIter, size(obj.zTestColonies,1));
                    obj.status = ['Z position of test colony ' s ' not found. Status: Idle.'];
                end
            end
        end
        
        function done = startNextColony(obj)
            N = size(obj.scanableColonyPositions,1);
            zTest = size(obj.zTestColonies,1);
            
            % Determine if we should be done
            if obj.bleachingModeActive && obj.bleachSingleMode
                done = obj.scanIter > 1;
            elseif obj.findZActive
                done = obj.scanIter > zTest;
                
            else
                done = (obj.scanIter > N);
            end
            
            if done
                if obj.findZActive
                   obj.interpColonyZs
                   obj.findZActive = false; 
                end
                obj.status = 'Returning home...';
                obj.moveStage([obj.homePosition(1:2) nan]);
                obj.abort();
            else
                if obj.bleachingModeActive
                    if obj.bleachSingleMode
                        % Update Bleach Power
                        obj.hSI.hBeams.powers = obj.bleachingPowers(obj.bleachPass);
                        
                        % Update Log File - only works with grab method
                        str = sprintf('Colony_%d_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%',...
                            1,1,obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
                        obj.hSI.hScan2D.logFileStem = str;
                        
                        % Update Status Bar
                        s = sprintf('%d of %d', obj.bleachPass, obj.totalBleachPasses);
                        obj.status = ['Photobleaching pass ' s];
                        pause(0.5);
                        drawnow('nocallbacks');
                        
                        % Start again
                        start(obj.hGrabTimer);
                    else
                        obj.hSI.hBeams.powers = obj.bleachingPowers(obj.bleachPass);
                        
                        % Dont move until bleach passes has finished....
                        if obj.bleachFinished
                            s = sprintf('(%d of %d)', obj.scanIter, N);
                            obj.status = ['Moving to next colony... ' s];
                            obj.moveStage(obj.scanableColonyPositions(obj.scanIter,1:3), true);
                            pause(0.25);
%                             % If current position is more than +/- 5um from
%                             % desired, re-target
%                             if any(obj.stagePosition(1:2) > obj.scanableColonyPositions(obj.scanIter,1:2) + 5) || any(obj.stagePosition(1:2) < obj.scanableColonyPositions(obj.scanIter,1:2) - 5)
%                                 obj.moveStage(obj.scanableColonyPositions(obj.scanIter,1:3), true);
%                                 pause(0.25);
%                             end
                            obj.bleachFinished = false;
                        end
                        
%                         str = sprintf('Colony_%d_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%', obj.scanIter,size(obj.scanableColonyPositions,1),obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
                        s = [sprintf('Colony_%%0%dd', numel(num2str(size(obj.scanableColonyPositions,1)))) '_of_%d_X%.2f_Y%.2f_Pass_%d_of_%d_at_%.2f%%'];
                        str = sprintf(s, 1,size(obj.scanableColonyPositions,1),obj.stagePosition(1), obj.stagePosition(2), obj.bleachPass, obj.totalBleachPasses, obj.hSI.hBeams.powers);
                        obj.hSI.hScan2D.logFileStem = str;
                        
                        s = sprintf('%d of %d', obj.bleachPass, obj.totalBleachPasses);
                        obj.status = ['Photobleaching pass ' s];
                        pause(0.5);
                        drawnow('nocallbacks');
                        
                        start(obj.hGrabTimer);
                    end
                    
                elseif obj.findZActive
                    % Update Log File?
                    
                    % Update Status bar?
                    s = sprintf('Searching for Z: Colony %d of %d', obj.scanIter, zTest);
                    obj.status = s;
                    % The colony has been found, move to the next colony 
                    % and the starting Z position.
                    if obj.colonyFound
                        s = sprintf('Colony %d of %d Found! Moving to next colony...', obj.scanIter-1, zTest);
                        obj.hSI.hScan2D.logFileStem = sprintf('Colony %d of %d', obj.scanIter, zTest);
                        obj.status = s;
                        obj.moveStage([obj.zTestColonies(obj.scanIter,1:2), obj.findZMinPos], true);
                        pause(0.25);
                    end
                    
                    % Update and start next scan
                    drawnow('nocallbacks');
                    start(obj.hGrabTimer);
                    
                else
                    s = sprintf('(%d of %d)', obj.scanIter, N);
                    obj.status = ['Moving to next colony... ' s];
                    %obj.moveStage([obj.scanableColonyPositions(obj.scanIter,1:2) nan]);
                    obj.moveStage(obj.scanableColonyPositions(obj.scanIter,1:3), true);
                    pause(0.25);
                    
%                     if any(obj.stagePosition(1:2) > obj.scanableColonyPositions(obj.scanIter,1:2) + 5) || any(obj.stagePosition(1:2) < obj.scanableColonyPositions(obj.scanIter,1:2) - 5)
%                         obj.moveStage(obj.scanableColonyPositions(obj.scanIter,1:3), true);
%                     end
%                     pause(0.25);

                    obj.status = ['Scanning... ' s];
                    drawnow('nocallbacks');
                    obj.hSI.hScan2D.trigIssueSoftwareAcq();
                end
            end
        end
        
        function addColony(obj,position)
            if isempty(obj.colonyPositions)
                obj.colonyPositions(end+1,:) = position;
            else
                newPosMat = repmat(position, size(obj.colonyPositions,1),1);
                diffs = newPosMat - obj.colonyPositions;
                diffs = diffs.^2;
                diffs = sum(diffs,2);
                diffs = (diffs.^0.5)./1e4;

                if any(diffs < 0.07)
%                     disp('Colony position already logged.');
%                    msgbox('Colony position already logged.');
                else
                    obj.colonyPositions(end+1,:) = position;
                end
            end
        end
        
        function addColonyFromGui(obj,position)
            obj.colonyPositions(end+1,:) = position;
        end
        
        function addTestColony(obj, position)
            if isempty(obj.zTestColonies)
                obj.zTestColonies(end+1,:) = position;
            else
                newPosMat = repmat(position, size(obj.zTestColonies,1),1);
                diffs = newPosMat - obj.zTestColonies;
                diffs = diffs.^2;
                diffs = sum(diffs,2);
                diffs = (diffs.^0.5)./1e4;

                if any(diffs < 0.1)
%                     disp('Colony position already logged.');
%                     msgbox('Colony position already logged.');
                else
                    obj.zTestColonies(end+1,:) = position;
                end
            end
        end
        
        function endOfAcq(obj,varargin)
            if obj.findZActive
                obj.handleZFind();
            end
            
            if obj.colonyScanning
                obj.scanIter = obj.scanIter + 1;
                obj.colonyScanning = ~obj.startNextColony();
            end
            
            if obj.bleachingModeActive
                if obj.bleachPass < obj.totalBleachPasses
                    obj.bleachPass = obj.bleachPass + 1;
                    obj.bleachingModeActive = ~obj.startNextColony();
                else
                    obj.bleachPass = 1;
                    obj.scanIter = obj.scanIter + 1;
                    obj.bleachFinished = true;
                    obj.bleachingModeActive = ~obj.startNextColony();
                end
            end
        end
        
        function getFrame(obj,varargin)
            try
                obj.lastLiveFrame = obj.hSpin.snapshot;
            catch
            end
        end
        
        function recreateIlluminatorEnableDOTask(obj)
            most.idioms.safeDeleteObj(obj.hTaskIlluminatorEnable);
            if ~obj.cfgLoading && ~isempty(obj.illuminatorDaq) && ~isempty(obj.illuminatorEnableDO)
                if most.idioms.isRioName(obj.illuminatorDaq)
                    obj.hTaskIlluminatorEnable = [];
                else
                    obj.hTaskIlluminatorEnable = most.util.safeCreateTask('NLIlluminatorEnableDOTask');
                    obj.hTaskIlluminatorEnable.createDOChan(obj.illuminatorDaq,obj.illuminatorEnableDO);
                    obj.illuminatorActive = obj.illuminatorActive;
                end
            end
        end
        
        function recreateIlluminatorIntensityAOTask(obj)
            most.idioms.safeDeleteObj(obj.hTaskIlluminatorIntensity);
            if ~obj.cfgLoading && ~isempty(obj.illuminatorDaq) && ~isempty(obj.illuminatorIntensityAOChan)
                if most.idioms.isRioName(obj.illuminatorDaq)
                    obj.hTaskIlluminatorIntensity = [];
                else
                    obj.hTaskIlluminatorIntensity = most.util.safeCreateTask('NLIlluminatorIntensityAOTask');
                    obj.hTaskIlluminatorIntensity.createAOVoltageChan(obj.illuminatorDaq,obj.illuminatorIntensityAOChan);
                    obj.illuminatorIntensityFraction = obj.illuminatorIntensityFraction;
                end
            end
        end
        
        function cfgLoadingComplete(obj)
            obj.recreateIlluminatorEnableDOTask();
            obj.recreateIlluminatorIntensityAOTask();
        end
        
        function [found, z, adjust] = detectZ(obj)            
            if strcmp(obj.scanMode,'line')
                % Pull Line Scan Data
                lastFramePointer = obj.hSI.hDisplay.lineScanLastFramePtr;
                imgDataStructRaw = obj.hSI.hDisplay.lineScanAvgDataBuffer;
                
                % Get the frame data
                frameData = imgDataStructRaw(:,lastFramePointer); 
                
                % Filter data a bit
                filteredData = filter((5000/numel(frameData)), [1 (5000/numel(frameData))-1], frameData);
                
                % Data if data is too low we can safely assume this is
                % noise, i.e. missed colony.
                if max(filteredData(:)) < 50
                    found = 0;
                    z = nan;
                    adjust = [];
                else
                    % Auto detect the noise floor and set as a threshold
                    threshold = rmsCalc(filteredData);
                    
                    % Get all the values above that noise floor, if colony
                    % is detected it should register as a large spike in
                    % the line scan data. 
                    valsAboveThreshold = find(filteredData >= threshold);
                    
                    % Find the start and end of the spike, this roughly
                    % determines the position of the colony in the 400um
                    % spiral scan ranges
                    start = valsAboveThreshold(1);
                    stop = valsAboveThreshold(end);
                    
                    % Binarization
                    data = filteredData;
                    data(start:stop) = 1;
                    data(1:start-1) = 0; 
                    data(stop+1:end) = 0;
                    
                    % Edge find
                    top = max(diff(data));
                    bottom = min(diff(data));

                    % The top of the colony should be the transition from 0
                    % to 1.
                    if (~isempty(top) && top == 1)
                        % We think we found the top but it might be a false
                        % positive...
                        topIdx = find(diff(data) == 1);
                        
                        % The top is detected too close to the start of the stack.
                        % It is likely a false positive
                        if topIdx <= numel(filteredData)*.10
                            topFound = false;
                        % The is a leading spike from 0 to 1 and it is not
                        % near enough to the edges that it might be a false
                        % positive, assume it is good. 
                        else
                            topFound = true;
                        end
                        
                    % Could not accurately identify a top
                    else
                        topFound = false;
                    end

                    % The bottom of a colony should be the transistion from
                    % 1 to 0
                    if (~isempty(bottom) && bottom == -1)
                        % We think we found the bottom but it might be a
                        % false positive.
                        bottomIdx = find(diff(data) == -1);
                        
                        % The bottom is detected too close to the end of the stack.
                        % It is likely a false positive
                        if bottomIdx >= numel(filteredData)*.90
                            bottomFound = false;
                            
                        % There is a falling edge that is not too close to
                        % the edge of the data sets that is might be a
                        % false positive, assume it is good.
                        else
                            bottomFound = true;
                        end
                        
                    % Could not identify the bottom of the colony
                    else
                        bottomFound = false;
                    end

                    % If both the top and bottom of the colony are found
                    % then we can assume we have found the colony.
                    if topFound && bottomFound
                        % The position in the data set in the physical
                        % position in the 400um scan range should have a
                        % linear relation. Meaning that if a spike occurs 
                        % in the first 25% of the data set then it means
                        % the colony was found in the first 25% of the scan
                        % range or ~100um in.
                        zTop = round((topIdx/numel(filteredData))*400) + obj.stagePosition(end);
                        zBottom = round((bottomIdx/numel(filteredData))*400) + obj.stagePosition(end);
                        zMid = median([zTop zBottom]);
                        found = true;
                        z = zMid - 200; %The colony peak should be approximately in the middle of the piezo scan.
                        adjust = [];
                        
                    % If only the top of the colony was found, no 1 -> 0
                    % translation found, then move a little deeper and scan
                    % again.
                    elseif topFound && ~bottomFound
                        found = false;
                        z = [];
                        % Flag to move deeper
                        adjust = 1;
                        
                    % Similarly if only the bottom of the colony was
                    % found, no 0 -> 1 translation, the move back a bit
                    elseif ~topFound && bottomFound
                        found = false;
                        z = [];
                        % Flag to move back
                        adjust = -1;
                        
                    % If neither are found we keep scanning across the
                    % total range
                    elseif ~topFound && ~bottomFound
%                         fprintf('cant find %d\n',i);
                        disp('Colony not found');
                        found = false;
                        z = [];
                        adjust = [];
                    end
                end
            end
        end
        
        function interpColonyZs(obj)
            % Scattered Interp - wont have enough Z data points?
            k=scatteredInterpolant(obj.zTestColonies(:,1), obj.zTestColonies(:,2), obj.zTestColonies(:,3));
            k.ExtrapolationMethod = 'nearest';

            t = obj.colonyPositions;
            t(:,3) = k(t(:, 1:2));
            obj.colonyPositions  = t;
        end
        
        function coloniesBySector = getColonyPositionBySector(obj, colonyPositions, sectorBounds)
            temp = struct('topLeft', [], 'topCenter', [], 'topRight', [], 'centerLeft', [],...
                'centerCenter', [], 'centerRight', [], 'bottomLeft', [], 'bottomCenter', [], 'bottomRight', []);

            % Get Left, Center, and Right colonies
            left_Indices = find(colonyPositions(1:end, 1) < -sectorBounds);
            center_Indices = find(colonyPositions(1:end, 1) > -sectorBounds & colonyPositions(1:end, 1) < sectorBounds);
            right_Indices = find(colonyPositions(1:end, 1) > sectorBounds);

            leftColonies = colonyPositions(left_Indices, 1:2);
            centerColonies = colonyPositions(center_Indices, 1:2);
            rightColonies = colonyPositions(right_Indices, 1:2);

            % Segment top 
            topLeft_Indices = find(leftColonies(1:end, 2) > sectorBounds);
            topCenter_Indices = find(centerColonies(1:end, 2) > sectorBounds);
            topRight_Indices = find(rightColonies(1:end, 2) > sectorBounds);

            topLeftColonies = leftColonies(topLeft_Indices, 1:2);
            topCenterColonies = centerColonies(topCenter_Indices, 1:2);
            topRightColonies = rightColonies(topRight_Indices, 1:2);

            % Segment middle
            centerLeft_Indices = find(leftColonies(1:end, 2) < sectorBounds & leftColonies(1:end, 2) > -sectorBounds);
            centerCenter_Indices = find(centerColonies(1:end, 2) < sectorBounds & centerColonies(1:end, 2) > -sectorBounds);
            centerRight_Indices = find(rightColonies(1:end, 2) < sectorBounds & rightColonies(1:end, 2) > -sectorBounds);

            centerLeftColonies = leftColonies(centerLeft_Indices, 1:2);
            centerCenterColonies = centerColonies(centerCenter_Indices, 1:2);
            centerRightColonies = rightColonies(centerRight_Indices, 1:2);

            % Segment bottom
            bottomLeft_Indices = find(leftColonies(1:end, 2) < -sectorBounds);
            bottomCenter_Indices = find(centerColonies(1:end, 2) < -sectorBounds);
            bottomRight_Indices = find(rightColonies(1:end, 2) < -sectorBounds);

            bottomLeftColonies = leftColonies(bottomLeft_Indices, 1:2);
            bottomCenterColonies = centerColonies(bottomCenter_Indices, 1:2);
            bottomRightColonies = rightColonies(bottomRight_Indices, 1:2);

            %Fill temp struct
            temp.topLeft = topLeftColonies;
            temp.topCenter = topCenterColonies;
            temp.topRight = topRightColonies;

            temp.centerLeft = centerLeftColonies;
            temp.centerCenter = centerCenterColonies;
            temp.centerRight = centerRightColonies;

            temp.bottomLeft = bottomLeftColonies;
            temp.bottomCenter = bottomCenterColonies;
            temp.bottomRight = bottomRightColonies;

            % Sub sectoring topLeft
            tL_indices = find(temp.topLeft(1:end,1) < -sectorBounds-10000 & temp.topLeft(1:end, 2) > sectorBounds + 10000);
            tL_colonies = temp.topLeft(tL_indices, 1:2);

            tR_indices = find(temp.topLeft(1:end,1) > -sectorBounds-10000 & temp.topLeft(1:end, 2) > sectorBounds + 10000);
            tR_colonies = temp.topLeft(tR_indices, 1:2);

            bL_indices = find(temp.topLeft(1:end,1) < -sectorBounds-10000 & temp.topLeft(1:end, 2) < sectorBounds + 10000);
            bL_colonies = temp.topLeft(bL_indices, 1:2);

            bR_indices = find(temp.topLeft(1:end,1) > -sectorBounds-10000 & temp.topLeft(1:end, 2) < sectorBounds + 10000);
            bR_colonies = temp.topLeft(bR_indices, 1:2);

            temp.topLeft = [];
            temp.topLeft.tL = [];
            temp.topLeft.tL = tL_colonies;
            temp.topLeft.tR = [];
            temp.topLeft.tR = tR_colonies;
            temp.topLeft.bL = [];
            temp.topLeft.bL = bL_colonies;
            temp.topLeft.bR = [];
            temp.topLeft.bR = bR_colonies;

            % Sub sectoring topRight
            tL_indices = find(temp.topRight(1:end,1) < sectorBounds+10000 & temp.topRight(1:end, 2) > sectorBounds + 10000);
            tL_colonies = temp.topRight(tL_indices, 1:2);

            tR_indices = find(temp.topRight(1:end,1) > sectorBounds+10000 & temp.topRight(1:end, 2) > sectorBounds + 10000);
            tR_colonies = temp.topRight(tR_indices, 1:2);

            bL_indices = find(temp.topRight(1:end,1) < sectorBounds+10000 & temp.topRight(1:end, 2) < sectorBounds + 10000);
            bL_colonies = temp.topRight(bL_indices, 1:2);

            bR_indices = find(temp.topRight(1:end,1) > sectorBounds+10000 & temp.topRight(1:end, 2) < sectorBounds + 10000);
            bR_colonies = temp.topRight(bR_indices, 1:2);

            temp.topRight = [];
            temp.topRight.tL = [];
            temp.topRight.tL = tL_colonies;
            temp.topRight.tR = [];
            temp.topRight.tR = tR_colonies;
            temp.topRight.bL = [];
            temp.topRight.bL = bL_colonies;
            temp.topRight.bR = [];
            temp.topRight.bR = bR_colonies;

            % Sub sectoring bottomLeft
            tL_indices = find(temp.bottomLeft(1:end,1) < -sectorBounds-10000 & temp.bottomLeft(1:end, 2) > -sectorBounds - 10000);
            tL_colonies = temp.bottomLeft(tL_indices, 1:2);

            tR_indices = find(temp.bottomLeft(1:end,1) > -sectorBounds-10000 & temp.bottomLeft(1:end, 2) > -sectorBounds - 10000);
            tR_colonies = temp.bottomLeft(tR_indices, 1:2);

            bL_indices = find(temp.bottomLeft(1:end,1) < -sectorBounds-10000 & temp.bottomLeft(1:end, 2) < -sectorBounds - 10000);
            bL_colonies = temp.bottomLeft(bL_indices, 1:2);

            bR_indices = find(temp.bottomLeft(1:end,1) > -sectorBounds-10000 & temp.bottomLeft(1:end, 2) < -sectorBounds - 10000);
            bR_colonies = temp.bottomLeft(bR_indices, 1:2);

            temp.bottomLeft = [];
            temp.bottomLeft.tL = [];
            temp.bottomLeft.tL = tL_colonies;
            temp.bottomLeft.tR = [];
            temp.bottomLeft.tR = tR_colonies;
            temp.bottomLeft.bL = [];
            temp.bottomLeft.bL = bL_colonies;
            temp.bottomLeft.bR = [];
            temp.bottomLeft.bR = bR_colonies;

            % Sub sectoring bottomRight
            tL_indices = find(temp.bottomRight(1:end,1) < sectorBounds+10000 & temp.bottomRight(1:end, 2) > -sectorBounds - 10000);
            tL_colonies = temp.bottomRight(tL_indices, 1:2);

            tR_indices = find(temp.bottomRight(1:end,1) > sectorBounds+10000 & temp.bottomRight(1:end, 2) > -sectorBounds - 10000);
            tR_colonies = temp.bottomRight(tR_indices, 1:2);

            bL_indices = find(temp.bottomRight(1:end,1) < sectorBounds+10000 & temp.bottomRight(1:end, 2) < -sectorBounds - 10000);
            bL_colonies = temp.bottomRight(bL_indices, 1:2);

            bR_indices = find(temp.bottomRight(1:end,1) > sectorBounds+10000 & temp.bottomRight(1:end, 2) < -sectorBounds - 10000);
            bR_colonies = temp.bottomRight(bR_indices, 1:2);

            temp.bottomRight = [];
            temp.bottomRight.tL = [];
            temp.bottomRight.tL = tL_colonies;
            temp.bottomRight.tR = [];
            temp.bottomRight.tR = tR_colonies;
            temp.bottomRight.bL = [];
            temp.bottomRight.bL = bL_colonies;
            temp.bottomRight.bR = [];
            temp.bottomRight.bR = bR_colonies;

            % Sub sectoring topCenter

            tL_indices = find(temp.topCenter(1:end,1) < 0 & temp.topCenter(1:end, 2) > sectorBounds + 10000);
            tL_colonies = temp.topCenter(tL_indices, 1:2);

            tR_indices = find(temp.topCenter(1:end,1) > 0 & temp.topCenter(1:end, 2) > sectorBounds + 10000);
            tR_colonies = temp.topCenter(tR_indices, 1:2);

            bL_indices = find(temp.topCenter(1:end,1) < 0 & temp.topCenter(1:end, 2) < sectorBounds + 10000);
            bL_colonies = temp.topCenter(bL_indices, 1:2);

            bR_indices = find(temp.topCenter(1:end,1) > 0 & temp.topCenter(1:end, 2) < sectorBounds + 10000);
            bR_colonies = temp.topCenter(bR_indices, 1:2);

            temp.topCenter = [];
            temp.topCenter.tL = [];
            temp.topCenter.tL = tL_colonies;
            temp.topCenter.tR = [];
            temp.topCenter.tR = tR_colonies;
            temp.topCenter.bL = [];
            temp.topCenter.bL = bL_colonies;
            temp.topCenter.bR = [];
            temp.topCenter.bR = bR_colonies;

            % Sub sectoring centerLeft

            tL_indices = find(temp.centerLeft(1:end,1) < -sectorBounds - 10000 & temp.centerLeft(1:end, 2) > 0);
            tL_colonies = temp.centerLeft(tL_indices, 1:2);

            tR_indices = find(temp.centerLeft(1:end,1) > -sectorBounds - 10000 & temp.centerLeft(1:end, 2) > 0);
            tR_colonies = temp.centerLeft(tR_indices, 1:2);

            bL_indices = find(temp.centerLeft(1:end,1) < -sectorBounds - 10000 & temp.centerLeft(1:end, 2) < 0);
            bL_colonies = temp.centerLeft(bL_indices, 1:2);

            bR_indices = find(temp.centerLeft(1:end,1) > -sectorBounds - 10000 & temp.centerLeft(1:end, 2) < 0);
            bR_colonies = temp.centerLeft(bR_indices, 1:2);

            temp.centerLeft = [];
            temp.centerLeft.tL = [];
            temp.centerLeft.tL = tL_colonies;
            temp.centerLeft.tR = [];
            temp.centerLeft.tR = tR_colonies;
            temp.centerLeft.bL = [];
            temp.centerLeft.bL = bL_colonies;
            temp.centerLeft.bR = [];
            temp.centerLeft.bR = bR_colonies;

            % Sub sectoring centerRight

            tL_indices = find(temp.centerRight(1:end,1) < sectorBounds + 10000 & temp.centerRight(1:end, 2) > 0);
            tL_colonies = temp.centerRight(tL_indices, 1:2);

            tR_indices = find(temp.centerRight(1:end,1) > sectorBounds + 10000 & temp.centerRight(1:end, 2) > 0);
            tR_colonies = temp.centerRight(tR_indices, 1:2);

            bL_indices = find(temp.centerRight(1:end,1) < sectorBounds + 10000 & temp.centerRight(1:end, 2) < 0);
            bL_colonies = temp.centerRight(bL_indices, 1:2);

            bR_indices = find(temp.centerRight(1:end,1) > sectorBounds + 10000 & temp.centerRight(1:end, 2) < 0);
            bR_colonies = temp.centerRight(bR_indices, 1:2);

            temp.centerRight = [];
            temp.centerRight.tL = [];
            temp.centerRight.tL = tL_colonies;
            temp.centerRight.tR = [];
            temp.centerRight.tR = tR_colonies;
            temp.centerRight.bL = [];
            temp.centerRight.bL = bL_colonies;
            temp.centerRight.bR = [];
            temp.centerRight.bR = bR_colonies;

            % Sub sectoring bottomCenter

            tL_indices = find(temp.bottomCenter(1:end,1) < 0 & temp.bottomCenter(1:end, 2) > -sectorBounds - 10000);
            tL_colonies = temp.bottomCenter(tL_indices, 1:2);

            tR_indices = find(temp.bottomCenter(1:end,1) > 0 & temp.bottomCenter(1:end, 2) > -sectorBounds - 10000);
            tR_colonies = temp.bottomCenter(tR_indices, 1:2);

            bL_indices = find(temp.bottomCenter(1:end,1) < 0 & temp.bottomCenter(1:end, 2) < -sectorBounds - 10000);
            bL_colonies = temp.bottomCenter(bL_indices, 1:2);

            bR_indices = find(temp.bottomCenter(1:end,1) > 0 & temp.bottomCenter(1:end, 2) < -sectorBounds - 10000);
            bR_colonies = temp.bottomCenter(bR_indices, 1:2);

            temp.bottomCenter = [];
            temp.bottomCenter.tL = [];
            temp.bottomCenter.tL = tL_colonies;
            temp.bottomCenter.tR = [];
            temp.bottomCenter.tR = tR_colonies;
            temp.bottomCenter.bL = [];
            temp.bottomCenter.bL = bL_colonies;
            temp.bottomCenter.bR = [];
            temp.bottomCenter.bR = bR_colonies;


            % Sub sectoring centerCenter

            tL_indices = find(temp.centerCenter(1:end,1) < 0 & temp.centerCenter(1:end, 2) > 0);
            tL_colonies = temp.centerCenter(tL_indices, 1:2);

            tR_indices = find(temp.centerCenter(1:end,1) > 0 & temp.centerCenter(1:end, 2) > 0);
            tR_colonies = temp.centerCenter(tR_indices, 1:2);

            bL_indices = find(temp.centerCenter(1:end,1) < 0 & temp.centerCenter(1:end, 2) < 0);
            bL_colonies = temp.centerCenter(bL_indices, 1:2);

            bR_indices = find(temp.centerCenter(1:end,1) > 0 & temp.centerCenter(1:end, 2) < 0);
            bR_colonies = temp.centerCenter(bR_indices, 1:2);

            temp.centerCenter = [];
            temp.centerCenter.tL = [];
            temp.centerCenter.tL = tL_colonies;
            temp.centerCenter.tR = [];
            temp.centerCenter.tR = tR_colonies;
            temp.centerCenter.bL = [];
            temp.centerCenter.bL = bL_colonies;
            temp.centerCenter.bR = [];
            temp.centerCenter.bR = bR_colonies;

            coloniesBySector = temp;
        end
        
        function testColonies = selectZTestColonies(obj,colonyPositions)
            testColonies = [];
            
            % FAILS IF NOT ENOUGH COLONIES!!!
            if size(colonyPositions, 1) < 12
               return;
            end

            % Flag for whether the select colonies are okay
            okay = false;
            % Variable to add okay colonies to.
            colonies = [];
            
            % Get some boundaries to help center selections
            xMin = min(colonyPositions(:, 1));
            xMax = max(colonyPositions(:, 1));
            yMin = min(colonyPositions(:, 2));
            yMax = max(colonyPositions(:, 2));

            while ~okay
                % Randomly Select a colony
                colIdx = randperm(size(colonyPositions,1), 1);
                colony = colonyPositions(colIdx, 1:2);

                % Verify colony in bounds
               if colony(1,1) > (xMax - 1000) || colony(1,1) < (xMin + 1000) || colony(1,2) > (yMax - 1000) || colony(1,2) < (yMin + 1000)
                   colonyInBounds = false;
               else 
                   colonyInBounds = true;
               end

               if colonyInBounds
                  okay = true;
                  colonies = [colonies; colony];
               end
            end
            
            testColonies = colonies;
        end
    end%
    
    %% PROP ACCESS
    methods
        function set.samplePosition(obj,v)
            if ~strcmp(v,obj.samplePosition)
                obj.moveStage([NaN NaN 0]);
            end
            
            switch v
                case 'camera'
                    obj.hZaber.moveCompleteAbsolute([obj.zaberCamPos NaN NaN]);
                    obj.samplePosition = v;
                    obj.moveStage([0 0 NaN]);
                    
                case 'scanner'
                    obj.hZaber.moveCompleteAbsolute([obj.zaberScanPos NaN NaN]);
                    obj.samplePosition = v;
                    obj.moveStage([0 0 NaN]);
                    
                otherwise
                    error('Invalid sample position');
            end
            
            obj.updateStagePosition();
        end
        
        function set.cameraLive(obj,v)
            obj.cameraLive = v;
            stop(obj.hTimer);
            obj.illuminatorActive = v;
            if v
                start(obj.hTimer);
            end
        end
        
        function set.illuminatorDaq(obj,v)
            obj.illuminatorDaq = v;
            obj.recreateIlluminatorEnableDOTask();
            obj.recreateIlluminatorIntensityAOTask();
        end
        
        function set.illuminatorEnableDO(obj,v)
            obj.illuminatorEnableDO = v;
            obj.recreateIlluminatorEnableDOTask();
        end
        
        function set.illuminatorIntensityAOChan(obj,v)
%             dbstack;
            obj.illuminatorIntensityAOChan = v;
            obj.recreateIlluminatorIntensityAOTask();
        end
        
        function set.illuminatorActive(obj,v)
            % sets active
            obj.illuminatorActive = logical(v);
            % get current intensity
            currentIntensity = obj.illuminatorIntensityFraction;
            % check devices
            if most.idioms.isRioName(obj.illuminatorDaq)
                % enable - doesnt seem to do anything
                obj.hFpgaDaq.hFpga.(['DIO' num2str(obj.illuminatorEnableDO)]) = logical(v);
                % sets intensity to current intensity - calls set function
                % which converst to voltage and outputs
                obj.illuminatorIntensityFraction = currentIntensity;%obj.illuminatorIntensityFraction;
            else
                if most.idioms.isValidObj(obj.hTaskIlluminatorEnable)
                    obj.hTaskIlluminatorEnable.writeDigitalData(logical(v));
                end
            end
%             obj.illuminatorIntensityFraction = 0.5;
%             obj.illuminatorIntensityFraction = inTen;
        end
        
        % Sets actual illuminator power by converting fractional (%) to
        % actual voltage value between 0 and 10.
        function set.illuminatorIntensityFraction(obj,v)
            obj.illuminatorIntensityFraction = min(max(v,0),1);
            if obj.illuminatorActive
                voltage = obj.illuminatorIntensityFraction*10;
            else
                voltage = 0;
            end
            if most.idioms.isRioName(obj.illuminatorDaq)
                obj.hFpgaDaq.aoSetValues(obj.illuminatorIntensityAOChan,voltage);
            else
                if most.idioms.isValidObj(obj.hTaskIlluminatorIntensity)
                    obj.hTaskIlluminatorIntensity.writeAnalogData(voltage);
                end
            end
        end
        
        function set.colonyPositions(obj,v)
            if isempty(v)
                obj.scanableColonyPositions = v;
                obj.oobColonyPositions = v;
            else
                cc = v - repmat([obj.dishCenter 0], size(v,1), 1);
                
                % check for potential objective collision with plate edge
                near_plate_edge=max(abs(cc(:,1:2)),[],2) >= (obj.dishSize/2 - obj.objectiveLensRadius);
                % check for in-bounds stage translation given the
                % scannerYPosOffset
                addressable=cc(:,1)+obj.scannerYPosOffset<49990; % limit is 50mm
                
                scp = ~near_plate_edge & addressable;
%                 assignin('base', 'scp', scp);
                obj.scanableColonyPositions = v(scp,:);
                obj.oobColonyPositions = v(~scp,:);
            end
            
            obj.colonyPositions = v;
        end
        
        function set.scannerYPosOffset(obj,v)
            obj.updateStagePosition();
            p = obj.stagePosition;
            obj.scannerYPosOffset = v;
            obj.moveStage(p);
        end
        
        function set.scannerXPosOffset(obj,v)
            obj.updateStagePosition();
            p = obj.stagePosition;
            obj.scannerXPosOffset = v;
            obj.moveStage(p);
        end
        
        function set.zaberScanPos(obj,v)
            if strcmp(obj.samplePosition, 'scanner')
                obj.hZaber.moveCompleteAbsolute([v NaN NaN]);
            end
            obj.zaberScanPos = v;
        end
        
        function set.zaberCamPos(obj,v)
            if strcmp(obj.samplePosition, 'camera')
                obj.hZaber.moveCompleteAbsolute([v NaN NaN]);
            end
            obj.zaberCamPos = v;
        end
        
        function set.scanMode(obj,v)
            assert(ismember(v, {'line' 'frame' 'point'}), 'Invalid scan mode');
            obj.scanMode = v;
        end
        
        function set.laserPower(obj,v)
            obj.hSI.hBeams.powers = v;
        end
        
        function v = get.laserPower(obj)
            v = obj.hSI.hBeams.powers;
        end

        function set.frameLaserPower(obj,v)
            obj.frameLaserPower = v;
            if strcmp(obj.scanMode,'frame')
                obj.laserPower = v;
            end
        end
        
        function set.lineLaserPower(obj,v)
            obj.lineLaserPower = v;
            if strcmp(obj.scanMode,'line') || strcmp(obj.scanMode,'point')
                obj.laserPower = v;
            end
        end
        
        function set.pointLaserPower(obj,v)
            obj.pointLaserPower = v;
            if strcmp(obj.scanMode,'point')
                obj.laserPower = v;
            end
        end
        
        function set.findZMinPos(obj, v)
           if v < 0 || v >= obj.findZMaxPos
              return;
           else
               obj.findZMinPos = v;
           end
        end
        
        function set.findZMaxPos(obj, v)
           if v > obj.maxSafeZ || v < 0 || v < obj.findZMinPos
               return;
           else
               obj.findZMaxPos = v;
           end
        end
        
        function set.findZStepSize(obj, v)
            if v > 400 || v < 0
                return;
            else
                obj.findZStepSize = v;
            end
        end
        
        function set.cameraExposureTime(obj, v)
            if v > 32.688
                v = 32.688;
            end
            if v < 0
                v = 0;
            end
            obj.hSpin.exposure_time_us = v*1e3;
        end
        
        function v = get.cameraExposureTime(obj)
            v = round(obj.hSpin.exposure_time_us/1e3,2);
        end
        
        function set.cameraGain(obj, v)
            if v < -7.7
                v = -7.7;
            end
            
            if v > 24
               v = 24; 
            end
            
            obj.hSpin.gain_dB = v;
        end
        
        function v = get.cameraGain(obj)
            v = round(obj.hSpin.gain_dB,2);
        end
        
        function set.colonyThreshold(obj, v)
%             if v > 1 || v < 0
%                return; 
%             end
            thFrac = min(max(v/65535,0),1);
            th = thFrac*65535;
            obj.colonyThreshold = th;
        end
        
        function set.colonyMinRadPx(obj, v)
           if v < 0 || v >= obj.colonyMaxRadPx 
               return;
           end
           obj.colonyMinRadPx = v;
        end
        
        function set.colonyMaxRadPx(obj, v)
           if v < 0 || v <= obj.colonyMinRadPx 
               return;
           end
           obj.colonyMaxRadPx = v;
        end
        
        function set.totalBleachPasses(obj, v)
            if v > numel(obj.bleachingPowers)
                return;
            else
                obj.totalBleachPasses = v;
            end
        end
        
        function set.bleachingPowers(obj, v)
           if numel(v) < obj.totalBleachPasses
              return;
           else
               obj.bleachingPowers = v;
           end
        end
        
%         function set.dishSize(obj, v)
%             
%         end
    end
end
function s = initCfgSchema()
    % si
    s.si.propSetName = 'ScanImage Info';
    s.si.mdf = {'ScanImage Machine Data File' 'siMdf' ''};
    
    % zaber
    s.zaber.propSetName = 'Zaber Stage Settings';
    s.zaber.comPort = {'Serial COM port' 'zaberComPort' 4};
    
    % illuminator
    s.illuminator.propSetName = 'Illuminator Info';
    s.illuminator.daqName = {'Illuminator DAQ name' 'illuminatorDaq' ''};
    s.illuminator.enableDOChan = {'Illuminator Enable DO Channel' 'illuminatorEnableDO' ''};
    s.illuminator.intensityAOChan = {'Illuminator DAQ name' 'illuminatorIntensityAOChan' 0};
end

function s = initMetaDataSchema()
    s.scanTime = {'Scan Time' 'scanTime' 0};
    s.scanSize = {'Scan Size' 'scanSize' 0};
    s.scanDepthRange = {'Scan Depth Range' 'scanDepthRange' 0};
    s.scanMode = {'Scan Mode' 'scanMode' ''};
    s.scannerResolution = {'Scanner Resolution (um/deg)' 'scannerResolution' 0};
    s.colonyPositions = {'Colony Positions' 'scanableColonyPositions' 0};
    s.laserPower = {'Laser Power' 'laserPower' 0};
end

function T=pixelsToStageTransform(imData,stagePositions)
    %% T=pixelsToStageTransform(imData,xData,yData)
    %
    % xData
    % yData
    %       The CData pulled from the surfaces (as cell arrays)
    %       These are in stage coordinates.
    %       Here, I just use the first vertex from each.
    %
    % imData
    %       A cell array with images corresponding to each stage position.
    % stagePositions
    %       A list of xy coords where the images were taken

    disp('Computing Pixels to Stage transform...');
    
    n=numel(imData(:));
%     pairs=enumerateAllPairs(n);
    pairs=enumerateSequentialPairs(n);
    stageDeltas=zeros(2,size(pairs,2));
    pixelDeltas=zeros(2,size(pairs,2));
    for ipair=1:size(pairs,2)
        pair=pairs(:,ipair);
        stageDeltas(:,ipair)=[...
            stagePositions(pair(2),1)-stagePositions(pair(1),1),...
            stagePositions(pair(2),2)-stagePositions(pair(1),2)];
        pixelDeltas(:,ipair)=phasecorrelation(imData{pair(1)},imData{pair(2)});
    end

    T=stageDeltas.*size(imData{1},1)/pixelDeltas;
    T(3,:) = 0;
    T(:,3) = 0;
    T(9) = 1;
    
    disp('... Done');
end

function pairs=enumerateAllPairs(n)
    %% pairs=enumerateAllPairs(n)
    %
    % This enumerates all pairs of tiles... probably not what we want
    % but works for 4 images...
    pairs=zeros(2,n*(n-1)./2);
    ipair=1;
    for i=1:n,
        for j=i:n,
            pairs(:,ipair)=[i j];
            ipair=ipair+1;
        end
    end
end

function pairs=enumerateSequentialPairs(n)
    %% pairs=enumerateSequentialPairs(n)
    pairs=repmat(1:(n-1),2,1);
    pairs(2,:)=pairs(2,:)+1;
end

function dr=phasecorrelation(a,b)
    %% dr=phasecorrelation(a,b)
    % a and b are images
    % dr is the estimated translation
    %
    % Example:
    %       dr=phasecorrelation(a,b);
    %       imshowpair(a,imtranslate(b,dr),'scaling','joint')
    a=padarray(a,size(a));
    b=padarray(b,size(b));
    
    a = single(a);
    a = a-mean(a(:));
    a = a./std(a(:));
    
    b = single(b);
    b = b-mean(b(:));
    b = b./std(b(:));

    fa=fft2(a);
    fb=fft2(b);
    fab=fa.*conj(fb);
    c=ifft2(fab./abs(fab));
    % fftshift gives the appropriate wrapping
    %    Want -w to w as translation range, for example
    %    Not 0 to 2*w
    % Need to subtract half image size to get deltas 
    %    relative to 0.
    % Subtract 1 bc matlab uses 1 as the base index
    [dy,dx]=find(fftshift(c)==max(c(:)));
    dy=dy-size(a,1)/2-1;
    dx=dx-size(a,2)/2-1;
    dr=[dx,dy];
end


