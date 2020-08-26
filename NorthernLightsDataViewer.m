classdef NorthernLightsDataViewer < handle
    
    properties
        ssImgData;
        metadata;
    end
    
    properties (Hidden)
        hFig;
        hFovPanel;
        hFovAxes;
        
        colonyCursor;
        colonyCursorBox;
        
        maxFov = 100000;%15000;
        defaultFovSize = 100000;%9000;
        currentFovSize = 100000;%9000;
        currentFovPos = [0 0];
        
        selBox;
    end
    
    properties (Hidden, SetObservable)
        colonyGoto = 0;
    end
    
    
    %% Lifecycle
    methods
        function obj = NorthernLightsDataViewer(dataDir)
            if nargin < 1
                dataDir = uigetdir(pwd, 'Select Dataset Directory...');
            end
            
            obj.ssImgData = load(fullfile(dataDir,'SnapShotImages.mat'));
            obj.metadata = most.json.loadjson(fullfile(dataDir,'NorthernLightsCfg.meta.txt'));
            
            obj.hFig = figure('numbertitle','off','name','NorthernLights Data Viewer','units','pixels','menubar','none',...
                'position',most.gui.centeredScreenPos([1600 800],'pixels'),'CloseRequestFcn',@(varargin)obj.delete);
            
            mainFlow = most.gui.uiflowcontainer('Parent',obj.hFig,'FlowDirection','TopDown','Margin',0.0001);
            obj.hFovPanel = uipanel('parent',mainFlow,'bordertype','none');
            obj.hFovAxes = axes('parent',obj.hFovPanel,'box','off','Color','k','GridColor',.9*ones(1,3),'ButtonDownFcn',@obj.mainViewHit,...
                        'xgrid','on','ygrid','on','GridAlpha',.25,'XTickLabel',[],'YTickLabel',[],'units','normalized','position',[0 0 1 1]);
            obj.hFovPanel.SizeChangedFcn = @obj.updateFovLims;
            obj.hFig.WindowScrollWheelFcn = @obj.scrollWheelFcn;
            
            bottomFlow = most.gui.uiflowcontainer('Parent',mainFlow,'FlowDirection','LeftToRight','HeightLimits',30);
            most.gui.staticText('Parent',bottomFlow,'String','Colony #:','HorizontalAlignment','left','FontSize',10, 'WidthLimits', 60);
            most.gui.uicontrol('parent',bottomFlow,'style','edit','FontSize',10, 'WidthLimits', 40,'Bindings',{obj 'colonyGoto' 'value'});
            most.gui.uicontrol('parent',bottomFlow,'string','Goto','FontSize',10,'WidthLimits',40,'callback',@(varargin)obj.gotoColony);
            
            if iscell(obj.ssImgData.imageData{1})
                ims = obj.ssImgData.imageData{1};
            else
                ims = obj.ssImgData.imageData;
            end
            
            if iscell(obj.ssImgData.stagePositions{1})
                posns = obj.ssImgData.stagePositions{1}(end-numel(ims)+1:end);
            else
                posns = obj.ssImgData.stagePositions;
            end
            
            obj.colonyCursor = line('xdata',0,'ydata',0,'parent',obj.hFovAxes,'Marker','+','Color','r','MarkerSize',20,'linewidth',2,'visible','off','hittest','off');
            
            for i=1:numel(ims)
                p = posns{i};
            
                [xx, yy] = meshgrid([-.5 .5],[-.5 .5]);
                [surfMeshXX,surfMeshYY] = scanimage.mroi.util.xformMesh(xx,yy,obj.ssImgData.cameraToStageTransform);

                surface('parent',obj.hFovAxes,'xdata',p(1) + surfMeshXX,...
                    'ydata',p(2) + surfMeshYY,'zdata',-1.1 * ones(2),'CData',ims{i},...
                    'FaceColor','texturemap','EdgeColor','c','hittest','off');
            end
            colormap gray;
        end
        
        function delete(obj)
            delete(obj.hFig);
        end
    end
    
    %% User methods
    methods
        function gotoColony(obj,i)
            if nargin < 2
                i = obj.colonyGoto;
            end
            
            obj.selBox = [];
            
            i = i(i <= numel(obj.metadata.colonyPositions));
            
            if any(~i) || isempty(i)
                obj.colonyCursor.Visible = 'off';
            else
                p = obj.metadata.colonyPositions(i,:);
                n = numel(i);
                px = [p(:,1) nan(n,1)]';
                py = [p(:,2) nan(n,1)]';
                obj.colonyCursor.XData = px(:);
                obj.colonyCursor.YData = py(:);
                obj.colonyCursor.ZData = 5*ones(n*2,1);
                obj.colonyCursor.Visible = 'on';
            end
        end
    end
    
    %% Internal Methods
    methods (Hidden)
        function updateFovLims(obj,varargin)
            obj.hFovPanel.Units = 'pixels';
            p = obj.hFovPanel.Position;
            
            lm = 0.5 * obj.currentFovSize * p(3:4) / min(p(3:4));
            obj.hFovAxes.XLim = lm(1) * [-1 1] + obj.currentFovPos(1);
            obj.hFovAxes.YLim = lm(2) * [-1 1] + obj.currentFovPos(2);
            obj.hFovAxes.Units = 'normalized';
            obj.hFovAxes.Position = [0 0 1 1];
            
            %obj.updateTickLabels();
        end
        
        function scrollWheelFcn(obj,~,evt)
            opt = obj.hFovAxes.CurrentPoint([1 3]);
            obj.currentFovSize = obj.currentFovSize * 1.5^evt.VerticalScrollCount;
            obj.currentFovPos = obj.currentFovPos + opt - obj.hFovAxes.CurrentPoint([1 3]);
        end
        
        function mainViewHit(obj,~,evt)
            if strcmp(evt.EventName, 'Hit') && (evt.Button == 1) && ismember('shift',obj.hFig.CurrentModifier)
                obj.mainViewColonySel([],evt);
            elseif strcmp(evt.EventName, 'Hit') && (evt.Button == 1)
                obj.mainViewPan([],evt);
            end
        end
        
        function mainViewPan(obj,~,evt)
            persistent opt
            
            if strcmp(evt.EventName, 'Hit')
                opt = obj.hFovAxes.CurrentPoint([1 3]);
                set(obj.hFig,'WindowButtonMotionFcn',@obj.mainViewPan,'WindowButtonUpFcn',@obj.mainViewPan);
            elseif strcmp(evt.EventName, 'WindowMouseMotion')
                obj.currentFovPos = obj.currentFovPos + opt - obj.hFovAxes.CurrentPoint([1 3]);
            else
                set(obj.hFig,'WindowButtonMotionFcn',[],'WindowButtonUpFcn',[]);
            end
        end
        
        function mainViewColonySel(obj,~,evt)
            persistent p1
            persistent colonies
            
            dragTolerance = 1e5;
            distTolerance = 1e6;
            
            if strcmp(evt.EventName, 'Hit')
                p1 = obj.hFovAxes.CurrentPoint([1 3]);
                obj.selBox = [];
                set(obj.hFig,'WindowButtonMotionFcn',@obj.mainViewColonySel,'WindowButtonUpFcn',@obj.mainViewColonySel);
            elseif strcmp(evt.EventName, 'WindowMouseMotion')
                p2 = obj.hFovAxes.CurrentPoint([1 3]);
                if sum(abs(p1-p2).^2) > dragTolerance
                    xs = [p1(1) p2(1)];
                    ys = [p1(2) p2(2)];
                    
                    colonies = find((obj.metadata.colonyPositions(:,1) >= min(xs)) & (obj.metadata.colonyPositions(:,1) <= max(xs)) &...
                        (obj.metadata.colonyPositions(:,2) >= min(ys)) & (obj.metadata.colonyPositions(:,2) <= max(ys)));
                    
                    obj.gotoColony(colonies);
                    obj.selBox = [p1 p2];
                else
                    obj.selBox = [];
                end
            else
                set(obj.hFig,'WindowButtonMotionFcn',[],'WindowButtonUpFcn',[]);
                if isempty(obj.selBox)
                    dists = repmat(obj.hFovAxes.CurrentPoint([1 3]),size(obj.metadata.colonyPositions,1),1) - obj.metadata.colonyPositions(:,[1 2]);
                    rs = sum(dists .* dists,2);
                    [y,i] = min(rs);
                    if y < distTolerance
                        obj.colonyGoto = i;
                        obj.gotoColony();
                        fprintf('Nearest colony to mouse click is #%d\n',i);
                    else
                        obj.gotoColony(0);
                    end
                else
                    if numel(colonies)
                        fprintf('Colonies within selected region: %s\n',strjoin(arrayfun(@(n){num2str(n)},colonies),', '));
                    end
                end
            end
        end
    end
    
    %% Prop access
    methods
        function set.currentFovSize(obj,v)
            obj.currentFovSize = max(min(v,obj.maxFov),obj.maxFov/1000);
            obj.currentFovPos = obj.currentFovPos;
        end
        
        function set.currentFovPos(obj,v)
            mxPos = (obj.maxFov-obj.currentFovSize);
            obj.currentFovPos = max(min(v,mxPos),-mxPos);
            obj.updateFovLims();
        end
        
        function set.selBox(obj,v)
            if isempty(v)
                if ~isempty(obj.colonyCursorBox)
                    obj.colonyCursorBox.Visible = 'off';
                end
            else
                xd = repmat([v(1) v(3)],2,1);
                yd = repmat([v(2);v(4)],1,2);
                if isempty(obj.colonyCursorBox)
                    obj.colonyCursorBox = surface('parent',obj.hFovAxes,'xdata',xd,'ydata',yd,'zdata',ones(2),...
                    'FaceColor','r','EdgeColor','r','hittest','off','FaceAlpha',.2,'linewidth',1);
                else
                    obj.colonyCursorBox.Visible = 'on';
                    obj.colonyCursorBox.XData = xd;
                    obj.colonyCursorBox.YData = yd;
                end
            end
            obj.selBox = v;
        end
    end
end