classdef NorthernLightsGui < handle
    
    properties (SetObservable)
        showCamHistogram = false;
        showColonies = true;
        
        camContrast = [0 2000];
        camExposureMillisec = [0 5000];
        autoScaleSaturationFraction = [.1 .01];
        
        scanDepthMn = 0;
        scanDepthMx = 400;
    end
    
    properties (Hidden)
        hNL;
        hFig;
        hFovPanel;
        hFovAxes;
        hScanAxes;
        hLis = event.listener.empty;
        hFovMenu;
        hLiveMenu;
        hSSMenu;
        hColonyMenu;
        
        h2pSettingsFrm;
        hScanControls;
        scanTimeFlow;
        scanSizeFlow;
        scanSlicesFlow;
        hFramePowerFlow;
        hLinePowerFlow;
        scanDepthFlow;
        hPointPowerFlow;
        hBleachPassFlow;
        hBleachControls;
        pbAbort;
        pbBleachSingle;
        pbBleachAll;
        
        etMotorX;
        etMotorY;
        etMotorZ;
        etNumColonies;
        etContrastWhite;
        etContrastBlack;
        
        pbFocus;
        pbScanSingle;
        pbScanAll;
        pbCalibrateFrame;
        pbCalibrateLine;
        pbCalibratePoint;
        
        hCamLiveSurf;
        hSSSurfs = matlab.graphics.primitive.Surface.empty;
        hFocusSurf;
        
        hXTicks = matlab.graphics.primitive.Text.empty;
        hYTicks = matlab.graphics.primitive.Text.empty;
        
        hColoniesDisp;
        hColoniesDispOob;
        hColoniesDispZTest;
        
        hStagePosC;
        hStagePosB;
        hStagePosL;
        
        hLeftViewFlow;
        hScanViewContrast;
        hDisp;
        
        snapDelete = false;
        
        camFlow;
    end
    
    properties (Hidden)
        maxFov = 100000;%15000;
        defaultFovSize = 100000;%9000;
        currentFovSize = 100000;%9000;
        currentFovPos = [0 0];
    end
    
    
    %% LIFECYCLE
    methods
        function obj = NorthernLightsGui(hNL)
            obj.hNL = hNL;
            
            
            obj.hFig = figure('numbertitle','off','name','NorthernLights Colony Scanner','menubar','none','units','pixels',...
                'position',most.gui.centeredScreenPos([1600 800]),'CloseRequestFcn',@obj.close,'visible','off','WindowScrollWheelFcn',@obj.scrollWheelFcn);
            
            obj.hFig.Colormap = [(0:.001:1)' (0:.001:1)' (0:.001:1)'];
            
            mainFlow = most.gui.uiflowcontainer('Parent',obj.hFig,'FlowDirection','LeftToRight','Margin',0.0001);
                leftFlowP = most.gui.uiflowcontainer('Parent',mainFlow,'FlowDirection','BottomUp', 'WidthLimits', 400,'Margin',0.0001);
                
                obj.hLeftViewFlow = most.gui.uiflowcontainer('Parent',leftFlowP,'FlowDirection','BottomUp','HeightLimits',[400 370]);
                    obj.hScanViewContrast = most.gui.constrastSlider('parent',obj.hLeftViewFlow, 'HeightLimits', 24,'visible','off');
                
                leftFlow = most.gui.uiflowcontainer('Parent',leftFlowP,'FlowDirection','TopDown','Margin',8);
                obj.hFovPanel = uipanel('parent',mainFlow,'bordertype','none');
                    obj.hFovAxes = axes('parent',obj.hFovPanel,'box','off','Color','k','GridColor',.9*ones(1,3),'ButtonDownFcn',@obj.mainViewPan,...
                        'xgrid','on','ygrid','on','GridAlpha',.25,'XTickLabel',[],'YTickLabel',[],'units','normalized','position',[0 0 1 1],'clim',obj.camContrast);
                    obj.hFovPanel.SizeChangedFcn = @obj.updateFovLims;
%                 scanFlow = most.gui.uiflowcontainer('Parent',mainFlow,'FlowDirection','TopDown', 'WidthLimits', 400);
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
%                         uipanel('parent',scanFlow,'bordertype','none','backgroundcolor','k');
            
            %% fov view graphics
            obj.hCamLiveSurf = surface('parent',obj.hFovAxes,'xdata',ones(2),'ydata',ones(2),'zdata',-ones(2),'CData',nan(2),...
                'FaceColor','texturemap','EdgeColor','b','visible','off','ButtonDownFcn',@obj.mainViewPan);
            obj.hColoniesDisp = line('parent',obj.hFovAxes,'xdata',nan,'ydata',nan,'zdata',nan,'LineStyle','none',...
                'MarkerEdgeColor','g','MarkerSize',15,'Marker','o','LineWidth',2);
            obj.hColoniesDispOob = line('parent',obj.hFovAxes,'xdata',nan,'ydata',nan,'zdata',nan,'LineStyle','none',...
                'MarkerEdgeColor','r','MarkerSize',15,'Marker','o','LineWidth',2);
            obj.hColoniesDispZTest = line('parent',obj.hFovAxes,'xdata',nan,'ydata',nan,'zdata',nan,'LineStyle','none',...
                'MarkerEdgeColor','b','MarkerSize',15,'Marker','o','LineWidth',2);
            obj.hStagePosC = line('parent',obj.hFovAxes,'xdata',0,'ydata',0,'zdata',0,'LineStyle','none',...
                'MarkerEdgeColor','g','MarkerSize',28,'Marker','+','LineWidth',1.5);
            obj.hStagePosB = line('parent',obj.hFovAxes,'xdata',0,'ydata',0,'zdata',0,'LineStyle','none',...
                'MarkerEdgeColor','g','MarkerSize',15,'Marker','s','LineWidth',1.5);
            obj.hStagePosL = line('parent',obj.hFovAxes,'xdata',[0 0],'ydata',[0 0],'zdata',[0 0],'Color','g','LineWidth',1.5);
            
            obj.hFocusSurf = surface('parent',obj.hFovAxes,'xdata',ones(2),'ydata',ones(2),'zdata',-0.9*ones(2),'CData',nan(2),...
                'FaceColor','texturemap','EdgeColor','g','visible','off','ButtonDownFcn',@obj.mainViewPan);
            
            %% fov menus
            obj.hFovMenu = handle(uicontextmenu('Parent',obj.hFig));
                uimenu('Parent',obj.hFovMenu,'Label','Move Stage Here','Callback',@obj.stageGoto);
                uimenu('Parent',obj.hFovMenu,'Label','Reset Transform','Callback',@obj.resetStageTransform);
                uimenu('Parent',obj.hFovMenu,'Label','Clear All Snap Shots','Callback',@obj.clearAllSS);
                uimenu('Parent',obj.hFovMenu,'Label','Add Colony Here','Callback',@obj.addColonyFromGui);%@obj.addColony);
                
            obj.hFovAxes.UIContextMenu = obj.hFovMenu;
            
            obj.hLiveMenu = handle(uicontextmenu('Parent',obj.hFig));
                uimenu('Parent',obj.hLiveMenu,'Label','Move Stage Here','Callback',@obj.stageGoto);
                uimenu('Parent',obj.hLiveMenu,'Label','Hide Live Image','Callback',@obj.hideLive,'Separator','on');
                uimenu('Parent',obj.hLiveMenu,'Label','Add Colony Here','Callback',@obj.addColonyFromGui);%@obj.addColony);
            obj.hCamLiveSurf.UIContextMenu = obj.hLiveMenu;
                
            obj.hSSMenu = handle(uicontextmenu('Parent',obj.hFig));
                uimenu('Parent',obj.hSSMenu,'Label','Move Stage Here','Callback',@obj.stageGoto);
                uimenu('Parent',obj.hSSMenu,'Label','Remove Snap Shot','Callback',@obj.removeSS,'Separator','on');
                uimenu('Parent',obj.hSSMenu,'Label','Clear All Snap Shots','Callback',@obj.clearAllSS);
                uimenu('Parent',obj.hSSMenu,'Label','Add Colony Here','Callback',@obj.addColonyFromGui,'Separator','on');%@obj.addColony,'Separator','on');
                uimenu('Parent',obj.hSSMenu,'Label','Auto Select Colonies','Callback',@obj.colonyAutoSelect);
            
            obj.hColonyMenu = handle(uicontextmenu('Parent',obj.hFig));
                uimenu('Parent',obj.hColonyMenu,'Label','Move Stage Here','Callback',@obj.stageGoto);
                uimenu('Parent',obj.hColonyMenu,'Label','Remove Colony','Callback',@obj.removeCol,'Separator','on');
                uimenu('Parent',obj.hColonyMenu,'Label','Add Colony as Test','Callback',@obj.addColonyAsTestColony);
                uimenu('Parent',obj.hColonyMenu,'Label','Remove Test Colony','Callback',@obj.removeTestCol);
            obj.hColoniesDisp.UIContextMenu = obj.hColonyMenu;
            obj.hColoniesDispOob.UIContextMenu = obj.hColonyMenu;
            obj.hColoniesDispZTest.UIContextMenu = obj.hColonyMenu;
            
            %% left bar frames
            f = frame(leftFlow,'SYSTEM STATUS',128);
            
            etStatus = most.gui.uicontrol('parent',f,'style','edit','Enable','inactive','string','Idle','BackgroundColor',.95*ones(1,3),'FontSize',10, 'HeightLimits', 24);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight');
            most.gui.staticText('Parent',f2,'String','Sample Position:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 106);
            rbCam = most.gui.uicontrol('parent',f2,'string','Camera (1P)','style','toggleButton','FontSize',10);
            rbScan = most.gui.uicontrol('parent',f2,'string','Scan (2P)','style','toggleButton','FontSize',10);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 30);
            most.gui.staticText('Parent',f2,'String','Stage Position:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 106);
            obj.etMotorX = most.gui.uicontrol('parent',f2,'string','0.0','style','edit','FontSize',10,'Callback',@obj.stageGotoRaw);
            obj.etMotorY = most.gui.uicontrol('parent',f2,'string','0.0','style','edit','FontSize',10,'Callback',@obj.stageGotoRaw);
            obj.etMotorZ = most.gui.uicontrol('parent',f2,'string','0.0','style','edit','FontSize',10,'Callback',@obj.stageGotoRaw);
            pbUpdateStage = most.gui.uicontrol('parent',f2,'string',char(8635),'FontSize',16, 'WidthLimits', 28);
            
            f = frame(leftFlow,'CAMERA (1P)',250);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Exposure Time (ms):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 120);
            etExposureTimeMillisec = most.gui.uicontrol('parent',f2,'style','edit','string',num2str(obj.hNL.cameraExposureTime),'FontSize',10, 'WidthLimits', 40);
            
            most.gui.staticText('Parent',f2,'String','Gain (dB):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 70);
            etCameraGain_dB = most.gui.uicontrol('parent',f2,'style','edit','string',num2str(obj.hNL.cameraGain),'FontSize',10, 'WidthLimits', 40);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Illuminator:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 120);
            etIlluminator = most.gui.uicontrol('parent',f2,'style','edit','string','50','FontSize',10, 'WidthLimits', 40);
            slIlluminator = most.gui.slider('parent',f2);
            
            p = most.gui.uipanel('parent',f,'Title','Display Contrast','FontSize',10, 'HeightLimits', 80);
            f1 = most.gui.uiflowcontainer('Parent',p,'FlowDirection','TopDown');
            f2 = most.gui.uiflowcontainer('Parent',f1,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Black:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 44);
            obj.etContrastBlack = most.gui.uicontrol('parent',f2,'style','edit','FontSize',10, 'WidthLimits', 44);
            most.gui.staticText('Parent',f2,'String','White:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 44);
            obj.etContrastWhite = most.gui.uicontrol('parent',f2,'style','edit','FontSize',10, 'WidthLimits', 44);
            obj.etContrastWhite.bindings = {obj 'camContrast' 'callback' @obj.changedCamContrast};
            most.gui.uipanel('parent',f2,'bordertype','none','WidthLimits',6);
            most.gui.uicontrol('parent',f2,'string','Auto','FontSize',10, 'WidthLimits', 40, 'callback', @obj.contrastAutoScale);
            most.gui.uipanel('parent',f2,'bordertype','none','WidthLimits',6);
            most.gui.uicontrol('parent',f2,'style','checkbox','string','Show Histogram','FontSize',10,'Bindings',{obj 'showCamHistogram' 'value'});
            most.gui.constrastSlider('parent',f1, 'HeightLimits', 24,'min',0,'max',2^16,'Bindings',{obj 'camContrast'});
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            cbTile = most.gui.uicontrol('parent',f2,'style','checkbox','string','Tiled Snap Shot','FontSize',10, 'WidthLimits', 120);
            most.gui.staticText('Parent',f2,'String','Tile Size:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 80);
            etTileSize = most.gui.uicontrol('parent',f2,'style','edit','FontSize',10, 'WidthLimits', 20,'String',2);
            most.gui.staticText('Parent',f2,'String','Tile Overlap (%):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 120);
            etOverlap = most.gui.uicontrol('parent',f2,'style','edit','FontSize',10, 'WidthLimits', 30,'String',25);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight');
            tbLive = most.gui.uicontrol('parent',f2,'string','Live','style','toggleButton','FontSize',10);
            pbSS = most.gui.uicontrol('parent',f2,'string','Snap Shot','FontSize',10);
            
            f = frame(leftFlow,'COLONY SELECTION',190);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Number of Scannable Colonies:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 176);
            most.gui.uipanel('parent',f2,'bordertype','none','WidthLimits',4);
            obj.etNumColonies = most.gui.uicontrol('parent',f2,'style','edit','string','0','FontSize',10, 'WidthLimits', 40,'enable','inactive','backgroundcolor',.95*ones(1,3));
            most.gui.uipanel('parent',f2,'bordertype','none','WidthLimits',12);
            most.gui.uicontrol('parent',f2,'style','checkbox','string','Show In Display','FontSize',10,'Bindings',{obj 'showColonies' 'value'});
            %% Find Colony Params
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Min Px Rad:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 67);
            etMinRadPx = most.gui.uicontrol('parent',f2,'style','edit','string','2','FontSize',9, 'WidthLimits', 40, 'callback', @obj.colonyAutoSelect);
            most.gui.staticText('Parent',f2,'String','Max Px Rad:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 72);
            etMaxRadPx = most.gui.uicontrol('parent',f2,'style','edit','string','12','FontSize',9, 'WidthLimits', 40, 'callback', @obj.colonyAutoSelect);
            most.gui.staticText('Parent',f2,'String','Threshold:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 61);
            etThreshold = most.gui.uicontrol('parent',f2,'style','edit','string','1.5e4','FontSize',9, 'WidthLimits', 40, 'callback', @obj.colonyAutoSelect);
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            
            slThreshold = most.gui.slider('parent',f2, 'min', 0, 'max', 65535);
            slThreshold.liveUpdate = false;
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            cbExclusion = most.gui.uicontrol('parent',f2,'style','checkbox','string','Toggle Exclusion Size','FontSize',10, 'WidthLimits', 240, 'callback', @obj.exclusionToggle);
                        
            %%
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.uicontrol('parent',f2,'string','Clear All','FontSize',10,'callback',@obj.removeAllColonies);
            most.gui.uicontrol('parent',f2,'string','Auto Select','FontSize',10, 'callback', @obj.colonyAutoSelect);
            
            f = frame(leftFlow, 'FIND Z POSITION', 98);
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            
            most.gui.staticText('Parent',f2,'String','Min Z Position:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 80);
            etMinZPos = most.gui.uicontrol('parent',f2,'style','edit','string','20','FontSize',8, 'WidthLimits', 40);
            
            most.gui.staticText('Parent',f2,'String','Max Z Position:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 85);
            etMaxZPos = most.gui.uicontrol('parent',f2,'style','edit','string','20','FontSize',8, 'WidthLimits', 40);
            
            most.gui.staticText('Parent',f2,'String','Z Step Size:','HorizontalAlignment','right','FontSize',9, 'WidthLimits', 75);
            etZStepSize = most.gui.uicontrol('parent',f2,'style','edit','string','20','FontSize',8, 'WidthLimits', 40);
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.uicontrol('parent',f2,'string','Start Z Find','FontSize',10, 'callback', @obj.colonyFindZ);
            most.gui.uicontrol('parent',f2,'string','Stop Z Find','FontSize',10, 'callback', @obj.abortColonyZFind);
            
            
            f = frame(leftFlow,'SCANNER (2P)',224);
            obj.h2pSettingsFrm = f.Parent.Parent;
            
            f2 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',f2,'String','Scan Mode:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 75);
            rbLine = most.gui.uicontrol('parent',f2,'string','Line (Spiral)','style','toggleButton','FontSize',10);
            rbFrame = most.gui.uicontrol('parent',f2,'string','Frame (Raster)','style','toggleButton','FontSize',10);
            rbPoint = most.gui.uicontrol('parent',f2,'string','Point (Bleach)','style','toggleButton','FontSize',10);
            
            obj.hFramePowerFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28, 'Visible', 'off');
            most.gui.staticText('Parent',obj.hFramePowerFlow,'String','Laser Power:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 82);
            etFramePower = most.gui.uicontrol('parent',obj.hFramePowerFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 30);
            slFramePower = most.gui.slider('parent',obj.hFramePowerFlow);%, 'WidthLimits', 150);
            obj.pbCalibrateFrame = most.gui.uicontrol('parent',obj.hFramePowerFlow,'string','Calibrate','FontSize',9, 'WidthLimits', 75, 'Callback',@obj.pbBeamsCalibrate);
            pbShowCurve = most.gui.uicontrol('parent',obj.hFramePowerFlow,'string','Show','FontSize',9, 'WidthLimits',45, 'Callback',@obj.showPowerCurve);
            
            obj.hLinePowerFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28, 'Visible', 'off');
            most.gui.staticText('Parent',obj.hLinePowerFlow,'String','Laser Power:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 82);
            etLinePower = most.gui.uicontrol('parent',obj.hLinePowerFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 30);
            slLinePower = most.gui.slider('parent',obj.hLinePowerFlow);
            obj.pbCalibrateLine = most.gui.uicontrol('parent',obj.hLinePowerFlow,'string','Calibrate','FontSize',9, 'WidthLimits', 75, 'Callback',@obj.pbBeamsCalibrate);
            pbShowCurve = most.gui.uicontrol('parent',obj.hLinePowerFlow,'string','Show','FontSize',9, 'WidthLimits',45, 'Callback',@obj.showPowerCurve);
            
            obj.scanDepthFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',obj.scanDepthFlow,'String','Scan Depth Range (um):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 150);
            etScanDepthMn = most.gui.uicontrol('parent',obj.scanDepthFlow,'style','edit','FontSize',10, 'WidthLimits', 60, 'Bindings', {obj 'scanDepthMn' 'value'});
            etScanDepthMx = most.gui.uicontrol('parent',obj.scanDepthFlow,'style','edit','FontSize',10, 'WidthLimits', 60, 'Bindings', {obj 'scanDepthMx' 'value'});
            
            obj.hPointPowerFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28, 'Visible', 'off');
            most.gui.staticText('Parent',obj.hPointPowerFlow,'String','Laser Power:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 82);
            etPointPower = most.gui.uicontrol('parent',obj.hPointPowerFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 30);
            slPointPower = most.gui.slider('parent',obj.hPointPowerFlow);
            obj.pbCalibratePoint = most.gui.uicontrol('parent',obj.hPointPowerFlow,'string','Calibrate','FontSize',9, 'WidthLimits', 75, 'Callback',@obj.pbBeamsCalibrate);
            pbShowCurve = most.gui.uicontrol('parent',obj.hPointPowerFlow,'string','Show','FontSize',9, 'WidthLimits',45, 'Callback',@obj.showPowerCurve);
            
            obj.scanTimeFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',obj.scanTimeFlow,'String','Scan Time per Colony (ms):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 168);
            etScanTime = most.gui.uicontrol('parent',obj.scanTimeFlow,'style','edit','string','2','FontSize',10, 'WidthLimits', 60);
            
            obj.hBleachPassFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',obj.hBleachPassFlow,'String','Num Passes:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 82);
            etNumPasses = most.gui.uicontrol('parent',obj.hBleachPassFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 30);
            most.gui.staticText('Parent',obj.hBleachPassFlow,'String','Pass Powers:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 82);
            etPassPower =  most.gui.uicontrol('parent',obj.hBleachPassFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 160);
            
            
            obj.scanSizeFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28);
            most.gui.staticText('Parent',obj.scanSizeFlow,'String','Scan Size (um):','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 168);
            etScanSize = most.gui.uicontrol('parent',obj.scanSizeFlow,'style','edit','string','800','FontSize',10, 'WidthLimits', 60);
            
            obj.scanSlicesFlow = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 28, 'Visible', 'off');
            most.gui.staticText('Parent',obj.scanSlicesFlow,'String','Number of slices:','HorizontalAlignment','right','FontSize',10, 'WidthLimits', 150);
            etScanSlices = most.gui.uicontrol('parent',obj.scanSlicesFlow,'style','edit','string','20','FontSize',10, 'WidthLimits', 60);
            
            obj.hScanControls = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 32);
            obj.pbFocus = most.gui.uicontrol('parent',obj.hScanControls,'string','Focus','FontSize',10, 'callback',@obj.pbStartFocus);
            obj.pbScanSingle = most.gui.uicontrol('parent',obj.hScanControls,'string','Scan Single','FontSize',10);
            obj.pbScanAll = most.gui.uicontrol('parent',obj.hScanControls,'string','Scan All','FontSize',10, 'callback',@obj.pbScanAllCb);
            
            obj.hBleachControls = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'HeightLimits', 32);
            obj.pbAbort = most.gui.uicontrol('parent',obj.hBleachControls,'string','Abort','FontSize',10, 'callback',@obj.pbAbortFcn);
            obj.pbBleachSingle = most.gui.uicontrol('parent',obj.hBleachControls,'string','Bleach Single','FontSize',10, 'callback', @obj.pbBleachSingleCb);
            obj.pbBleachAll = most.gui.uicontrol('parent',obj.hBleachControls,'string','Bleach All','FontSize',10, 'callback',@obj.pbBleachAllCb);
            
            
            f = frame(leftFlow,'FILE LOGGING',70);
            f1 = most.gui.uiflowcontainer('Parent',f,'FlowDirection','LeftToRight', 'margin', 0.0001, 'HeightLimits', 36);
            f2 = most.gui.uiflowcontainer('Parent',f1,'FlowDirection','LeftToRight');
            cbLogging = most.gui.uicontrol('parent',f2,'style','checkbox','string','Enable File Logging','FontSize',10);
            f2 = most.gui.uiflowcontainer('Parent',f1,'FlowDirection','RightToLeft');
            most.gui.uicontrol('parent',f2,'string','Set Logging Dir...','FontSize',10,'callback',@obj.setLogDir);
            
            
            
            obj.hFig.Visible = 'on';
            most.gui.figstate.maxfig(obj.hFig,1);
            
            if most.idioms.isValidObj(hNL)
                obj.hLis(end+1) = addlistener(hNL, 'ObjectBeingDestroyed', @(varargin)delete(obj));
                obj.hLis(end+1) = addlistener(hNL, 'lastLiveFrame', 'PostSet', @obj.liveFrameAcquired);
                obj.hLis(end+1) = addlistener(hNL, 'scanDepthRange', 'PostSet', @(varargin)etScanDepthMn.model2view());
                obj.hLis(end+1) = addlistener(hNL, 'scanDepthRange', 'PostSet', @(varargin)etScanDepthMx.model2view());
                obj.hLis(end+1) = addlistener(hNL, 'ssFrameData', 'PostSet', @obj.ssFrameAcquired);
                obj.hLis(end+1) = addlistener(hNL, 'cameraToStageTransform', 'PostSet', @obj.xformUpdated);
                obj.hLis(end+1) = addlistener(hNL, 'scanMode', 'PostSet', @obj.scanModeChanged);
                obj.hLis(end+1) = addlistener(hNL.hSI.hDisplay, 'chan1LUT', 'PostSet', @obj.contrastChanged);
                obj.hLis(end+1) = addlistener(hNL.hSI, 'acqState', 'PostSet', @obj.siStateChange);
                obj.hLis(end+1) = addlistener(hNL.hSI.hUserFunctions, 'frameAcquired', @obj.siFrameAcquired);
                
                obj.hScanViewContrast.min = round(obj.hNL.hSI.hChannels.channelLUTRange(1)/10);
                obj.hScanViewContrast.max = obj.hNL.hSI.hChannels.channelLUTRange(2);
                obj.hScanViewContrast.bindings = {obj.hNL.hSI.hDisplay 'chan1LUT'};
                obj.hScanViewContrast.integerVals = true;
                
                
                for hMtr = obj.hNL.hSI.hMotors.hMotor
                    obj.hLis(end+1) = hMtr.addlistener('LSCError',@obj.updateMotorErrorState);
                end
                
                obj.hLis(end+1) = addlistener(obj.hNL.hSI.hBeams, 'beamCalibratedStatus', 'PostSet', @obj.updateCalibrateButton);
                obj.hLis(end+1) = addlistener(obj.hNL.hSI.hBeams, 'beamCalibratedStatus', 'PostGet', @obj.updateCalibrateButton);
                obj.hLis(end+1) = addlistener(obj.hNL, 'colonyThreshold', 'PostSet', @obj.colonyAutoSelect);
                obj.hLis(end+1) = addlistener(obj.hNL, 'zTestColonies', 'PostSet', @obj.zTestColoniesChanged);
                obj.hLis(end+1) = addlistener(obj.hNL, 'dishSize', 'PostSet', @obj.colonyAutoSelect);
                
                etStatus.bindings = {hNL 'status' 'string'};
                obj.pbScanSingle.callback = @(varargin)obj.hNL.scanSingleColony();
                
                rbCam.bindings = {hNL 'samplePosition' 'match' 'camera'};
                rbScan.bindings = {hNL 'samplePosition' 'match' 'scanner'};
                
                rbFrame.bindings = {hNL 'scanMode' 'match' 'frame'};
                rbLine.bindings = {hNL 'scanMode' 'match' 'line'};
                rbPoint.bindings = {hNL 'scanMode', 'match' 'point'};
                
                tbLive.bindings = {hNL 'cameraLive' 'value'};
                pbSS.callback = @obj.takeSS;
                
                rbScan.bindings = {hNL 'samplePosition' 'match' 'scanner'};
                
                cbLogging.bindings = {hNL 'enableLogging' 'value'};
                
                etScanTime.bindings = {hNL 'scanTime' 'value'};
                etScanSize.bindings = {hNL 'scanSize' 'value'};
                etScanSlices.bindings = {hNL 'rasterNumSlices' 'value'};
                obj.etNumColonies.bindings = {hNL 'colonyPositions' 'callback' @obj.coloniesChanged};
                
                etFramePower.bindings = {hNL 'frameLaserPower' 'value'};
                slFramePower.bindings = {hNL 'frameLaserPower' 100};
                slFramePower.liveUpdate = false;
                
                etLinePower.bindings = {hNL 'lineLaserPower' 'value'};
                slLinePower.bindings = {hNL 'lineLaserPower' 100};
                slLinePower.liveUpdate = false;
                
                etPointPower.bindings = {hNL 'pointLaserPower' 'value'};
                slPointPower.bindings = {hNL 'pointLaserPower' 100};
                slPointPower.liveUpdate = false;
                
                obj.etMotorX.bindings = {hNL 'stagePosition' 'callback' @obj.stageMoved};
                obj.etMotorY.bindings = {hNL 'stageTarget' 'callback' @obj.stageMoved};
                pbUpdateStage.callback = @(varargin)obj.hNL.updateStagePosition();
                
                etIlluminator.bindings = {hNL 'illuminatorIntensityFraction' 'value' '%f' 'scaling' 100};
                slIlluminator.bindings = {hNL 'illuminatorIntensityFraction' 1};
                
                cbTile.bindings = {hNL 'enableSnapShotTile' 'value'};
                etTileSize.bindings = {hNL 'snapShotTileSize' 'value'};
                etOverlap.bindings = {hNL 'snapShotTileOverlap' 'value'};
                
                etMinZPos.bindings = {hNL 'findZMinPos' 'value'};
                etMaxZPos.bindings = {hNL 'findZMaxPos' 'value'};
                etZStepSize.bindings = {hNL 'findZStepSize' 'value'};
                
                etExposureTimeMillisec.bindings = {hNL 'cameraExposureTime' 'value'};
                etCameraGain_dB.bindings = {hNL 'cameraGain' 'value'};
                
                etMinRadPx.bindings = {hNL 'colonyMinRadPx' 'value'};
                etMaxRadPx.bindings = {hNL 'colonyMaxRadPx' 'value'};
                etThreshold.bindings = {hNL 'colonyThreshold' 'value' '%f'};
                slThreshold.bindings = {hNL 'colonyThreshold' 1};
                                
                etNumPasses.bindings = {hNL 'totalBleachPasses' 'value'};
                etPassPower.bindings = {hNL 'bleachingPowers' 'value'};
                
                obj.scanModeChanged();
            end
        end
        
        function delete(obj)
            most.idioms.safeDeleteObj(obj.hFig);
            most.idioms.safeDeleteObj(obj.hLis);
        end
        
        function close(obj,varargin)
            if strcmp('Yes',questdlg('Exit Colony Scanner?', 'Colony Scanner','Yes','No','No'))
                if most.idioms.isValidObj(obj.hNL)
                    obj.hNL.exit();
                else
                    delete(obj);
                end
            end
        end
    end
    
    %% USER METHODS
    methods
        function contrastAutoScale(obj,varargin)
            
            if obj.hNL.cameraLive
                pixels = obj.hCamLiveSurf.CData(:);
            else
                pixels = reshape([obj.hSSSurfs(:).CData],1,[]);
            end
            
            if ~isempty(pixels) && ~all(isnan(pixels))
                pixels = sort(pixels);
                N = numel(pixels);
                iblk = ceil(N*obj.autoScaleSaturationFraction(1));
                iwht = ceil(N*(1-obj.autoScaleSaturationFraction(2)));
                
                obj.camContrast = round([pixels(iblk) pixels(iwht)]);
            end
        end
    end
    
    %% INTERNAL METHODS
    methods
        function exclusionToggle(obj, varargin)
            if ~isempty(obj.hSSSurfs)
                tf = varargin{1}.Value;

                if tf
                    obj.hNL.dishSize = 81000; 
                else
                    obj.hNL.dishSize = 101000;
                end
            end
        end
        
        function coloniesChanged(obj, varargin)
            if most.idioms.isValidObj(obj.hNL)
                obj.etNumColonies.String = num2str(size(obj.hNL.scanableColonyPositions,1));
                
                
                cp = obj.hNL.scanableColonyPositions;
                N = size(cp,1);
                
                if N
                    xs = nan(2*N,1);
                    xs(1:2:end) = cp(:,1);
                    
                    ys = nan(2*N,1);
                    ys(1:2:end) = cp(:,2);
                    
                    zs = zeros(2*N,1);
                    
                    obj.hColoniesDisp.XData = xs;
                    obj.hColoniesDisp.YData = ys;
                    obj.hColoniesDisp.ZData = zs;
                    obj.hColoniesDisp.Visible = 'on';
                else
                    obj.hColoniesDisp.XData = nan;
                    obj.hColoniesDisp.YData = nan;
                    obj.hColoniesDisp.ZData = nan;
                    obj.hColoniesDisp.Visible = 'off';
                end
                
                
                cp = obj.hNL.oobColonyPositions;
                N = size(cp,1);
                
                if N
                    xs = nan(2*N,1);
                    xs(1:2:end) = cp(:,1);
                    
                    ys = nan(2*N,1);
                    ys(1:2:end) = cp(:,2);
                    
                    zs = zeros(2*N,1);
                    
                    obj.hColoniesDispOob.XData = xs;
                    obj.hColoniesDispOob.YData = ys;
                    obj.hColoniesDispOob.ZData = zs;
                    obj.hColoniesDispOob.Visible = 'on';
                else
                    obj.hColoniesDispOob.XData = nan;
                    obj.hColoniesDispOob.YData = nan;
                    obj.hColoniesDispOob.ZData = nan;
                    obj.hColoniesDispOob.Visible = 'off';
                end
            end
        end
        
        function zTestColoniesChanged(obj, varargin)
                cp = obj.hNL.zTestColonies;
                N = size(cp,1);
                
                if N
                    xs = nan(2*N,1);
                    xs(1:2:end) = cp(:,1);
                    
                    ys = nan(2*N,1);
                    ys(1:2:end) = cp(:,2);
                    
                    zs = zeros(2*N,1);
                    
                    obj.hColoniesDispZTest.XData = xs;
                    obj.hColoniesDispZTest.YData = ys;
                    obj.hColoniesDispZTest.ZData = zs;
                    obj.hColoniesDispZTest.Visible = 'on';
                else
                    obj.hColoniesDispZTest.XData = nan;
                    obj.hColoniesDispZTest.YData = nan;
                    obj.hColoniesDispZTest.ZData = nan;
                    obj.hColoniesDispZTest.Visible = 'off';
                end
        end
        
        function stageMoved(obj, varargin)
            t = obj.hNL.stageTarget;
            p = obj.hNL.stagePosition;
            
            obj.etMotorX.String = sprintf('%.1f',p(1));
            obj.etMotorY.String = sprintf('%.1f',p(2));
            obj.etMotorZ.String = sprintf('%.1f',p(3));
            
            obj.hStagePosC.XData = t(1);
            obj.hStagePosC.YData = t(2);
            obj.hStagePosB.XData = p(1);
            obj.hStagePosB.YData = p(2);
            obj.hStagePosL.XData = [t(1) p(1)];
            obj.hStagePosL.YData = [t(2) p(2)];
            obj.updateMotorErrorState();
        end
        
        function pbScanAllCb(obj, varargin)
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.scanAllColonies();
            end
        end
        
        function pbBleachSingleCb(obj, varargin)
            if most.idioms.isValidObj(obj.hNL)
              obj.hNL.bleachSingle(); 
           end
        end
        
        function pbBleachAllCb(obj, varargin)
           if most.idioms.isValidObj(obj.hNL)
              obj.hNL.startBleaching(); 
           end
        end
        
        function setLogDir(obj, varargin)
            d = uigetdir(obj.hNL.logFolder, 'Set Logging Directory...');
            if d ~= 0
                obj.hNL.logFolder = d;
            end
        end
        
        function pbStartFocus(obj, varargin)
            if most.idioms.isValidObj(obj.hNL)
                if strcmp(obj.hNL.hSI.acqState, 'idle')
                    obj.hNL.startFocus();
                else
%                     obj.hNL.findZActive = false;
                    obj.hNL.hSI.abort();
                end
            end
        end
        
        function pbAbortFcn(obj, varargin)
            if ~strcmp(obj.hNL.hSI.acqState, 'idle')
                obj.hNL.hSI.abort();
            end
        end
        
        function pbBeamsCalibrate(obj, varargin)
            obj.hNL.hSI.hBeams.beamsCalibrate;

        end
        
        function showPowerCurve(obj, varargin)
            obj.hNL.hSI.hBeams.beamsShowCalibrationCurve(1);
        end
        
        function updateCalibrateButton(obj, varargin)
           if obj.hNL.hSI.hBeams.beamCalibratedStatus
               obj.pbCalibrateFrame.String = 'Calibrated';
               obj.pbCalibrateFrame.hCtl.BackgroundColor = 'g';
               obj.pbCalibrateLine.String = 'Calibrated';
               obj.pbCalibrateLine.hCtl.BackgroundColor = 'g';
               obj.pbCalibratePoint.String = 'Calibrated';
               obj.pbCalibratePoint.hCtl.BackgroundColor = 'g';
           else
               obj.pbCalibrateFrame.String = 'Uncalibrated';
               obj.pbCalibrateFrame.hCtl.BackgroundColor = 'r';
               obj.pbCalibrateLine.String = 'Uncalibrated';
               obj.pbCalibrateLine.hCtl.BackgroundColor = 'r';
               obj.pbCalibratePoint.String = 'Uncalibrated';
               obj.pbCalibratePoint.hCtl.BackgroundColor = 'r';
           end
        end
        
        function siStateChange(obj, varargin)
            if most.idioms.isValidObj(obj.hNL)
                if strcmp(obj.hNL.hSI.acqState, 'idle')
                    obj.hFocusSurf.Visible = 'off';
                    obj.pbFocus.String = 'Focus';
                    obj.pbScanSingle.Enable = 'on';
                    obj.pbScanAll.Enable = 'on';
                    obj.pbFocus.hCtl.BackgroundColor = 0.94 * ones(1,3);
                else
                    obj.pbFocus.String = 'Abort';
                    obj.pbFocus.hCtl.BackgroundColor = 'y';
                    
                    obj.pbScanSingle.Enable = 'off';
                    obj.pbScanAll.Enable = 'off';
                    
                    obj.hFig.WindowButtonDownFcn = [];
                    
                    if ismember(obj.hNL.hSI.acqState, {'focus' 'grab' 'loop'})
%                         obj.hFocusSurf.CData = nan;
%                         obj.hFocusSurf.Visible = 'on';
                        most.idioms.safeDeleteObj(obj.hDisp);
                        obj.hFig.SizeChangedFcn = [];
                        
                        if strcmp(obj.hNL.hSI.hRoiManager.scanType, 'line')
                            obj.hDisp = scanimage.guis.LineScanDisplay(obj.hNL.hSI,obj.hLeftViewFlow,1);
                            obj.hDisp.hTimePlotAx.Visible = 'off';
                            obj.hDisp.hDataViewAx.Visible = 'off';
                        else
                            obj.hDisp = scanimage.mroi.RoiDisplay(obj.hNL.hSI,obj.hLeftViewFlow,1);
                            obj.hDisp.initialize(obj.hNL.hSI.hStackManager.zs,'no_transform','current');
                        end
                        obj.hDisp.CLim = obj.hNL.hSI.hChannels.channelLUT{1};
                        obj.hScanViewContrast.Visible = 'on';
                    end
                    
                    obj.hFig.WindowButtonMotionFcn = [];
                    obj.hFig.WindowScrollWheelFcn = @obj.scrollWheelFcn;
                end
            end
        end
        
        function takeSS(obj, varargin)
            if strcmp(obj.hNL.samplePosition, 'camera')
                obj.clearAllSS();
                obj.hideLive();
                obj.hNL.snapShot();
                obj.contrastAutoScale();
            else
                msgbox('Move Sample to Camera position before taking snap shots.');
            end
        end
        
        function changedCamContrast(obj,varargin)
            obj.etContrastWhite.String = num2str(obj.camContrast(2));
            obj.etContrastBlack.String = num2str(obj.camContrast(1));
        end
                
        function updateFovLims(obj,varargin)
            obj.hFovPanel.Units = 'pixels';
            p = obj.hFovPanel.Position;
            
            lm = 0.5 * obj.currentFovSize * p(3:4) / min(p(3:4));
            obj.hFovAxes.XLim = lm(1) * [-1 1] + obj.currentFovPos(1);
            obj.hFovAxes.YLim = lm(2) * [-1 1] + obj.currentFovPos(2);
            obj.hFovAxes.Units = 'normalized';
            obj.hFovAxes.Position = [0 0 1 1];
            
            obj.updateTickLabels();
        end
        
        function scanModeChanged(obj,varargin)
            isfr = strcmp(obj.hNL.scanMode, 'frame');
            isPt = strcmp(obj.hNL.scanMode, 'point');
            isln = strcmp(obj.hNL.scanMode,'line');
            
            % if line expand
            obj.h2pSettingsFrm.HeightLimits = (190 + 30*isln)*ones(1,2);
            
            obj.scanDepthFlow.Visible = tfMap(~isPt);
            obj.hPointPowerFlow.Visible = tfMap(isPt);
            obj.hBleachPassFlow.Visible = tfMap(isPt);
            obj.hBleachControls = tfMap(isPt);
            obj.hScanControls.Visible = tfMap(~isPt);
            
            obj.scanTimeFlow.Visible = tfMap(isln||isPt);
            obj.scanSizeFlow.Visible = tfMap(isln);
            obj.hLinePowerFlow.Visible = tfMap(isln);
            
            obj.scanSlicesFlow.Visible = tfMap(isfr);
            obj.hFramePowerFlow.Visible = tfMap(isfr);
        end
        
        function contrastChanged(obj,varargin)
            if most.idioms.isValidObj(obj.hDisp)
                obj.hDisp.CLim = obj.hNL.hSI.hChannels.channelLUT{1};
            end
        end
        
        function updateTickLabels(obj)
            marg = 90;
            
            tck = obj.hFovAxes.YTick;
            
            obj.hFovAxes.Units = 'pixels';
            p = obj.hFovAxes.Position;
            pix2xlim = diff(obj.hFovAxes.XLim) /  p(3);
            xp = obj.hFovAxes.XLim(1) + marg*pix2xlim;
            
            N = numel(tck);
            for i = 1:N
                if numel(obj.hYTicks) < i || ~most.idioms.isValidObj(obj.hYTicks(i))
                    obj.hYTicks(i) = text('parent',obj.hFovAxes,'fontsize',12,'color','w','HorizontalAlignment','right');
                end
                
                obj.hYTicks(i).Position = [xp tck(i)];
                obj.hYTicks(i).String = sprintf('%.3f mm',tck(i)/1000);
            end
            delete(obj.hYTicks(i+1:end));
            obj.hYTicks(i+1:end) = [];
            
            
            
            tck = obj.hFovAxes.XTick;
            tck(tck < (xp + 6*pix2xlim)) = [];
            
            yp = obj.hFovAxes.YLim(1) + marg / p(4) * diff(obj.hFovAxes.YLim);
            
            N = numel(tck);
            for i = 1:N
                if numel(obj.hXTicks) < i || ~most.idioms.isValidObj(obj.hXTicks(i))
                    obj.hXTicks(i) = text('parent',obj.hFovAxes,'fontsize',12,'color','w','Rotation',90,'HorizontalAlignment','right');
                end
                
                obj.hXTicks(i).Position = [tck(i) yp];
                obj.hXTicks(i).String = sprintf('%.3f mm',tck(i)/1000);
            end
            delete(obj.hXTicks(i+1:end));
            obj.hXTicks(i+1:end) = [];
        end
        
        function scrollWheelFcn(obj,~,evt)
            if mouseIsInAxes(obj.hFovAxes)
                opt = obj.hFovAxes.CurrentPoint([1 3]);
                obj.currentFovSize = obj.currentFovSize * 1.5^evt.VerticalScrollCount;
                obj.currentFovPos = obj.currentFovPos + opt - obj.hFovAxes.CurrentPoint([1 3]);
            end
            
            function tf = mouseIsInAxes(hAx)
                coords = hAx.CurrentPoint([1 3]);
                xlim = hAx.XLim;
                ylim = hAx.YLim;
                tf = (coords(1) > xlim(1)) && (coords(1) < xlim(2)) && (coords(2) > ylim(1)) && (coords(2) < ylim(2));
            end
        end
        
        function mainViewPan(obj,~,evt)
            persistent opt
            
            obj.hFig.WindowScrollWheelFcn = @obj.scrollWheelFcn;
            
            if strcmp(evt.EventName, 'Hit') && (evt.Button == 1)
                opt = obj.hFovAxes.CurrentPoint([1 3]);
                set(obj.hFig,'WindowButtonMotionFcn',@obj.mainViewPan,'WindowButtonUpFcn',@obj.mainViewPan);
            elseif strcmp(evt.EventName, 'WindowMouseMotion')
                obj.currentFovPos = obj.currentFovPos + opt - obj.hFovAxes.CurrentPoint([1 3]);
            else
                set(obj.hFig,'WindowButtonMotionFcn',[],'WindowButtonUpFcn',[]);
            end
        end
        
        function liveFrameAcquired(obj,varargin)
            p = obj.hNL.stagePosition;
            
            [xx, yy] = meshgrid([-.5 .5],[-.5 .5]);
            [surfMeshXX,surfMeshYY] = scanimage.mroi.util.xformMesh(xx,yy,obj.hNL.cameraToStageTransform);
            
            obj.hCamLiveSurf.XData = p(1) + surfMeshXX;
            obj.hCamLiveSurf.YData = p(2) + surfMeshYY;
            obj.hCamLiveSurf.CData = obj.hNL.lastLiveFrame;
            obj.hCamLiveSurf.UserData = p;
            obj.hCamLiveSurf.Visible = 'on';
        end
        
        function ssFrameAcquired(obj,varargin)
            if ~isempty(obj.hNL.ssFrameData) && obj.snapDelete == false
                p = obj.hNL.stagePosition;
                
                [xx, yy] = meshgrid([-.5 .5],[-.5 .5]);
                [surfMeshXX, surfMeshYY] = scanimage.mroi.util.xformMesh(xx,yy,obj.hNL.cameraToStageTransform);
                
                obj.hSSSurfs(end+1) = surface('parent',obj.hFovAxes,'xdata',p(1) + surfMeshXX,...
                    'ydata',p(2) + surfMeshYY,'zdata',-1.1 * ones(2),'CData',obj.hNL.ssFrameData{end},...
                    'FaceColor','texturemap','EdgeColor','c','ButtonDownFcn',@obj.mainViewPan,...
                    'UIContextMenu',obj.hSSMenu,'userdata',p);
            end
            obj.snapDelete = false;
        end
        
        function xformUpdated(obj,varargin)
            [xx, yy] = meshgrid([-.5 .5],[-.5 .5]);
            [surfMeshXX, surfMeshYY] = scanimage.mroi.util.xformMesh(xx,yy,obj.hNL.cameraToStageTransform);
            
            for h = [obj.hCamLiveSurf obj.hSSSurfs]
                p = h.UserData;
                h.XData = p(1) + surfMeshXX;
                h.YData = p(2) + surfMeshYY;
            end
        end
        
        function siFrameAcquired(obj,varargin)
            if strcmp(obj.hNL.hSI.hRoiManager.scanType, 'frame');
%                 p = obj.hNL.stagePosition;
%                 
%                 obj.hFocusSurf.XData = p(1) + obj.hNL.siFov * [-.5 .5; -.5 .5];
%                 obj.hFocusSurf.YData = p(2) + obj.hNL.siFov * [-.5 -.5; .5 .5];
%                 obj.hFocusSurf.CData = obj.hNL.hSI.hDisplay.lastFrame{1};
%                 obj.hFocusSurf.Visible = 'on';
                if most.idioms.isValidObj(obj.hDisp);
                    obj.hDisp.drawRoiData(obj.hNL.hSI.hDisplay.lastStripeData.roiData);
                end
            else
                if most.idioms.isValidObj(obj.hDisp);
                    obj.hDisp.updateDisplay(obj.hNL.hSI.hDisplay.lastStripeData);
                end
            end
        end
        
        function updateMotorErrorState(obj,varargin)
            edits = [obj.etMotorX obj.etMotorY obj.etMotorZ];
            for i = 1:min(numel(obj.hNL.hSI.hMotors.hMotor),3)
                updateSt(obj.hNL.hSI.hMotors.hMotor(i),edits(i));
            end
            
            function updateSt(hMtr,hEdit)
                if hMtr.lscErrPending
                    c = [1 .75 .75];
                else
                    c = 'w';
                end
                hEdit.hCtl.BackgroundColor = c;
            end
        end
        
        function stageGoto(obj,varargin)
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.moveStage([obj.hFovAxes.CurrentPoint([1 3]) nan]);
            end
        end
        
        function stageGotoRaw(obj,varargin)
            x = str2double(obj.etMotorX.String);
            y = str2double(obj.etMotorY.String);
            z = str2double(obj.etMotorZ.String);
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.moveStage([x y z],false);
            end
            
        end
        
        function resetStageTransform(obj, varargin)
           obj.hNL.cameraToStageTransform = [69135 0 0; 0 69135 0; 0 0 1];
        end
        
        function hideLive(obj,varargin)
            obj.hNL.lastLiveFrame = [];
            obj.hCamLiveSurf.Visible = 'off';
        end
        
        function removeSS(obj,varargin)
            obj.snapDelete = true;
            hand = gco(obj.hFig);
            f = obj.hSSSurfs == hand;
            if any(f)
                for i = 1:length(obj.hNL.ssFrameData)
                    if isequal(hand.CData, obj.hNL.ssFrameData{i})
                        obj.hNL.ssFrameData(i) = [];
                        break;
                    end
                    
                end
                
                for i = 1:length(obj.hSSSurfs)
                    if isequal(obj.hSSSurfs(i).CData, hand.CData)
                        most.idioms.safeDeleteObj(obj.hSSSurfs(i));
                        obj.hSSSurfs(i) = [];
                        break;
                    end
                end
            end
        end
        
        function removeCol(obj,varargin)
            cp = obj.hNL.colonyPositions(:,1:2);
            N = size(cp,1);
            
            cmp = abs(repmat(obj.hFovAxes.CurrentPoint([1 3]),N,1) - cp);
            rs = cmp(:,1).^2 + cmp(:,2).^2;
            [~,i] = min(rs);
            obj.hNL.colonyPositions(i,:) = [];
        end
        
        function removeAllColonies(obj,varargin)
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.colonyPositions = [];
                obj.hNL.zTestColonies = [];
            end
        end
        
        function clearAllSS(obj,varargin)
            obj.hNL.ssFrameData = {};
            most.idioms.safeDeleteObj(obj.hSSSurfs);
            obj.hSSSurfs = matlab.graphics.primitive.Surface.empty;
        end
        
        function addColonyFromGui(obj, varargin)
            obj.hNL.addColonyFromGui([obj.hFovAxes.CurrentPoint([1 3]) obj.hNL.stagePosition(3)]);
        end
        
        function addColonyAsTestColony(obj, varargin)
            cp = obj.hNL.colonyPositions(:,1:2);
            N = size(cp,1);
            
            cmp = abs(repmat(obj.hFovAxes.CurrentPoint([1 3]),N,1) - cp);
            rs = cmp(:,1).^2 + cmp(:,2).^2;
            [~,i] = min(rs);
            
            obj.hNL.addTestColony(obj.hNL.colonyPositions(i,:));
            obj.zTestColoniesChanged();
        end
                
        function removeTestCol(obj,varargin)
            if isempty(obj.hNL.zTestColonies)
                return;
            end
            cp = obj.hNL.zTestColonies(:,1:2);
            N = size(cp,1);
            
            cmp = abs(repmat(obj.hFovAxes.CurrentPoint([1 3]),N,1) - cp);
            rs = cmp(:,1).^2 + cmp(:,2).^2;
            [~,i] = min(rs);
            obj.hNL.zTestColonies(i,:) = [];
            obj.zTestColoniesChanged();
        end
        
        function colonyAutoSelect(obj, varargin)
            obj.removeAllColonies;
            hand = gco(obj.hFig);
            if isa(hand, 'matlab.graphics.primitive.Surface') && ~isempty(hand)
                autoSelectFromSurf(hand);
            else
                for h = obj.hSSSurfs
                    autoSelectFromSurf(h);
                end
            end           
            % The following autoselects test colonies.
%             sectoredColonyPositions = obj.hNL.getColonyPositionBySector(obj.hNL.scanableColonyPositions, 17000);
%             testColonies = [obj.hNL.selectZTestColonies(sectoredColonyPositions.topLeft.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topLeft.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.topLeft.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topLeft.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.topRight.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topRight.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.topRight.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topRight.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomLeft.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomLeft.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomLeft.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomLeft.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomRight.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomRight.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomRight.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomRight.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerLeft.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerLeft.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerLeft.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerLeft.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerRight.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerRight.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerRight.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerRight.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.topCenter.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topCenter.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.topCenter.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.topCenter.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomCenter.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomCenter.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomCenter.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.bottomCenter.bR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerCenter.tL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerCenter.tR);...
%                 obj.hNL.selectZTestColonies(sectoredColonyPositions.centerCenter.bL);obj.hNL.selectZTestColonies(sectoredColonyPositions.centerCenter.bR);...
%                 ];
% 
%             obj.hNL.zTestColonies = [testColonies(:, 1:2), zeros(size(testColonies,1),1)];

            
            function autoSelectFromSurf(hS)
                C1 = [hS.XData(1,1) hS.YData(1,1)];
                C2 = [hS.XData(2,2) hS.YData(2,2)];
                midX = (C1(1) + C2(1))/2;
                midY = (C1(2) + C2(2))/2;
                coords = [midX midY];
                obj.hNL.autoSelect(hS.CData, coords);
            end

        end
        
        function colonyFindZ(obj, varargin)
           if strcmp(obj.hNL.samplePosition, 'camera')
               warndlg('Please move sample to 2P side before proceeding.');
           else
%                obj.hNL.findZ();
               obj.hNL.startZFind();
           end
        end
        
        function abortColonyZFind(obj, varargin)
           obj.hNL.findZActive = false;
           obj.hNL.hSI.abort();
        end
    end
    
    %% PROP ACCESS METHODS
    methods
        function set.camContrast(obj,v)
            v = min(uint16(v),2^16-2);
            v(2) = max(v(1)+1,v(2));
            obj.camContrast = v;
            obj.hFovAxes.CLim = v;
        end
        
        function set.currentFovSize(obj,v)
            obj.currentFovSize = max(min(v,obj.maxFov),obj.maxFov/1000);
            obj.currentFovPos = obj.currentFovPos;
        end
        
        function set.currentFovPos(obj,v)
            mxPos = (obj.maxFov-obj.currentFovSize);
            obj.currentFovPos = max(min(v,mxPos),-mxPos);
            obj.updateFovLims();
        end
        
        function set.showColonies(obj,v)
            obj.hColoniesDisp.Visible = tfMap(v);
            obj.hColoniesDispOob.Visible = tfMap(v);
            obj.showColonies = v;
        end
        
        function v = get.scanDepthMn(obj)
            if most.idioms.isValidObj(obj.hNL)
                v = obj.hNL.scanDepthRange(1);
            else
                v = obj.scanDepthMn;
            end
        end
        
        function set.scanDepthMn(obj,v)
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.scanDepthRange(1) = v;
            else
                obj.scanDepthMn = v;
            end
        end
        
        function v = get.scanDepthMx(obj)
            if most.idioms.isValidObj(obj.hNL)
                v = obj.hNL.scanDepthRange(2);
            else
                v = obj.scanDepthMx;
            end
        end
        
        function set.scanDepthMx(obj,v)
            if most.idioms.isValidObj(obj.hNL)
                obj.hNL.scanDepthRange(2) = v;
            else
                obj.scanDepthMx = v;
            end
        end
    end
end

function f = frame(parent,name,height)
    opPanel = uipanel('parent',parent,'Bordertype','none');
    set(opPanel, 'HeightLimits', height * ones(1,2));
    f = most.gui.uiflowcontainer('Parent',opPanel,'FlowDirection','TopDown','BackgroundColor',.4*ones(1,3),'Margin',4);
    titleBar(f,name);
    
    f = most.gui.uiflowcontainer('Parent',f,'FlowDirection','TopDown');
end

function titleBar(parent,title)
    t = most.gui.staticText('parent',parent,'BackgroundColor',.4*ones(1,3),'string',title,'FontSize',10,'HorizontalAlignment', 'center','HeightLimits',20);
    t.hTxt.FontWeight = 'bold';
    t.hTxt.Color = 'w';
end

function t = tfMap(v)
    if v
        t = 'on';
    else
        t = 'off';
    end
end
