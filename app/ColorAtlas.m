classdef ColorAtlas < handle
%COLORATLAS Interactive appearance-model atlas with an explicit sRGB preview.
% Public automation: setState(struct), refresh, planeSpecs, hitTest, selectCell,
% snapshot, resetDefaults and showHelp. State and Atlas retain the exact inputs
% and sampled numerical data. A returned hit index of zero means a cell gap.
    properties (SetAccess = private)
        State
        Atlas
    end
    properties
        UIFigure
        RootGrid
        Sidebar
        PlotGrid
        UIAxes
        TitleLabel
        AuthorLabel
        ModelDropDown
        PlaneDropDown
        SpaceDropDown
        WhiteDropDown
        VisionDropDown
        SurroundDropDown
        LaModeDropDown
        LaSpinner
        LwSpinner
        YbSpinner
        DModeDropDown
        DSpinner
        BackgroundSpinner
        ConstantSpinner
        ConstantSlider
        ConstantLabel
        ModelLabel
        ConditionsLabel
        StatusLabel
        SelectionLabel
        HelpFigure
    end
    properties (Access = private)
        Busy = false
        SelectedIndex = 0
        SelectionOutline = gobjects(0)
        Chrome = [0.075 0.086 0.106]
        Panel = [0.11 0.125 0.15]
        Text = [0.91 0.93 0.96]
        Muted = [0.68 0.73 0.80]
        Field = [0.165 0.184 0.22]
        Accent = [0.35 0.72 0.91]
    end
    methods
        function app = ColorAtlas(varargin)
            app.State = app.defaults();
            app.createUI();
            if ~isempty(varargin), app.setState(varargin{1}); else, app.refresh(); end
            app.UIFigure.Visible = 'on';
        end
        function delete(app)
            if ~isempty(app.HelpFigure) && isvalid(app.HelpFigure), delete(app.HelpFigure); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.UIFigure.CloseRequestFcn = [];
                delete(app.UIFigure);
            end
        end
        function resetDefaults(app)
            app.State = app.defaults();
            app.SelectedIndex = 0;
            app.refresh();
        end
        function setState(app, changes)
            % Supply one or more named State fields. Changing model/plane resets
            % the fixed attribute to that plane's default unless constant is given.
            assert(isstruct(changes) && isscalar(changes), 'ColorAtlas:state', 'Expected a scalar state struct.');
            s = app.State;
            names = fieldnames(changes);
            for k = 1:numel(names)
                assert(isfield(s, names{k}), 'ColorAtlas:state', 'Unknown state field %s.', names{k});
                s.(names{k}) = changes.(names{k});
            end
            textFields = {'model','plane','space','white','vision','surround','laMode','dMode'};
            % Validate the proposed state before changing the app or its controls.
            % mustBeMember alone accepts arrays of otherwise valid enum values.
            for k = 1:numel(textFields)
                s.(textFields{k}) = app.scalarText(s.(textFields{k}),textFields{k});
            end
            specs = app.planeSpecs(s.model);
            keys = string({specs.key});
            if ~any(keys == s.plane)
                assert(isfield(changes,'model') && ~isfield(changes,'plane'), 'ColorAtlas:plane', 'Plane is not supported by this model.');
                s.plane = keys(1);
            end
            spec = specs(find(keys == s.plane, 1));
            if (isfield(changes,'model') || isfield(changes,'plane')) && ~isfield(changes,'constant')
                s.constant = app.attributeDefault(spec.fixed);
            end
            app.validateState(s);
            app.State = s;
            app.SelectedIndex = 0;
            app.refresh();
        end
        function specs = planeSpecs(app, model)
            model = app.scalarText(model,'model');
            if model == "cielab"
                rows = {'h-C-L','h','C','L','L','C'; 'L-h-C','L','h','C','L','C'; 'C-h-L','C','h','L','L','C'};
            else
                assert(any(model == ColorAtlasScience.MODELS), 'ColorAtlas:model','Unknown appearance model.');
                rows = {'h-C-J','h','C','J','J','C'; 'J-h-C','J','h','C','J','C'; ...
                    'C-h-J','C','h','J','J','C'; 'M-h-J','M','h','J','J','M'; ...
                    's-h-J','s','h','J','J','s'; 'Q-h-C','Q','h','C','Q','C'; ...
                    'h-M-J','h','M','J','J','M'; 'h-s-J','h','s','J','J','s'; 'h-C-Q','h','C','Q','Q','C'};
            end
            specs = struct('key',{},'fixed',{},'x',{},'y',{},'tone',{},'chroma',{},'label',{});
            for k = 1:size(rows,1)
                specs(k) = struct('key',rows{k,1},'fixed',rows{k,2},'x',rows{k,3}, ...
                    'y',rows{k,4},'tone',rows{k,5},'chroma',rows{k,6}, ...
                    'label',sprintf('Fixed %s  |  %s x %s',rows{k,2},rows{k,3},rows{k,4}));
            end
        end
        function refresh(app)
            if app.Busy, return; end
            app.Busy = true;
            cleanup = onCleanup(@()app.finishRefresh()); %#ok<NASGU>
            s = app.State;
            isLab = s.model == "cielab";
            La = s.La;
            if s.laMode == "derived", La = s.Lw * s.Yb / 100; end
            D = s.D;
            if s.dMode == "automatic", D = NaN; end
            white = whitepoint(char(s.white));
            args = {'La',La,'Yb',s.Yb,'Yw',100,'surround',s.surround,'D',D};
            Qwhite = NaN;
            if ~isLab, Qwhite = ColorAtlasScience.whiteBrightness(s.model,white*100,args{:}); end
            specs = app.planeSpecs(s.model);
            spec = specs(find(string({specs.key}) == s.plane,1));
            limits = app.attributeLimits(spec.fixed,Qwhite);
            app.State.constant = min(max(s.constant,limits(1)),limits(2));
            s = app.State;
            x = app.samples(spec.x,Qwhite); y = app.samples(spec.y,Qwhite);
            [X,Y] = meshgrid(x,y);
            n = numel(X);
            a = struct; a.(spec.fixed) = repmat(s.constant,n,1);
            a.(spec.x) = X(:); a.(spec.y) = Y(:);
            if isLab
                XYZ = ColorAtlasScience.cielabToXYZ(a.L,a.C,a.h,char(s.white));
                modelStatus = repmat("valid",n,1);
                bgXYZ = ColorAtlasScience.backgroundXYZ("lab",s.white,s.backgroundL);
                actualD = NaN;
            else
                [XYZ,modelStatus,info] = ColorAtlasScience.inverseCAM(s.model,a,white*100,args{:});
                XYZ = XYZ/100;
                actualD = info.D;
                bgXYZ = ColorAtlasScience.backgroundXYZ("cam",s.white,s.Yb/100);
            end
            originalXYZ = XYZ;
            if s.vision ~= "trichromat"
                XYZ = ColorAtlasScience.simulateDichromat(s.vision,XYZ,white);
            end
            P = ColorAtlasScience.previewCells(XYZ,s.space,s.white);
            bgP = ColorAtlasScience.previewCells(bgXYZ,"srgb",s.white);
            bg = min(max(bgP.rgbPreview,0),1);
            app.Atlas = struct('X',X(:),'Y',Y(:),'x',x,'y',y,'XYZ',XYZ,'originalXYZ',originalXYZ, ...
                'modelStatus',modelStatus,'status',P.status,'rgbSelected',P.rgbSelected, ...
                'rgbPreview',P.rgbPreview,'rgbDisplay',P.rgbDisplay,'spec',spec,'appearance',a, ...
                'backgroundXYZ',bgXYZ,'backgroundRGB',bg,'Qwhite',Qwhite, ...
                'La',La,'D',actualD,'cellFraction',0.9,'state',s);
            app.syncControls(limits,spec);
            app.drawAtlas();
        end
        function index = hitTest(app,x,y)
            index = 0;
            assert(isnumeric(x) && isreal(x) && isscalar(x) && ...
                isnumeric(y) && isreal(y) && isscalar(y), ...
                'ColorAtlas:coordinates','Hit-test coordinates must be real numeric scalars.');
            if isempty(app.Atlas) || ~isfinite(x) || ~isfinite(y), return; end
            [dx,col] = min(abs(app.Atlas.x-x));
            [dy,row] = min(abs(app.Atlas.y-y));
            hx = diff(app.Atlas.x(1:2))*app.Atlas.cellFraction/2;
            hy = diff(app.Atlas.y(1:2))*app.Atlas.cellFraction/2;
            if dx <= hx && dy <= hy
                index = sub2ind([numel(app.Atlas.y),numel(app.Atlas.x)],row,col);
            end
        end
        function selectCell(app,index)
            assert(isnumeric(index) && isreal(index) && isscalar(index) && isfinite(index) && index == fix(index) && index >= 0 && index <= numel(app.Atlas.X), ...
                'ColorAtlas:selection','Select an existing sample index, or zero for no selection.');
            app.SelectedIndex = index;
            delete(app.SelectionOutline(isgraphics(app.SelectionOutline)));
            app.SelectionOutline = gobjects(0);
            if index == 0
                app.SelectionLabel.Text = {'Select a cell to inspect its coordinates and numerical values.', ...
                    'Empty atlas regions are classified samples; gaps have no sample.'};
                return
            end
            A = app.Atlas;
            w = diff(A.x(1:2))*A.cellFraction; h = diff(A.y(1:2))*A.cellFraction;
            pos = [A.X(index)-w/2,A.Y(index)-h/2,w,h];
            app.SelectionOutline(1) = rectangle(app.UIAxes,'Position',pos,'EdgeColor',[0 0 0],'LineWidth',3,'HitTest','off');
            app.SelectionOutline(2) = rectangle(app.UIAxes,'Position',pos,'EdgeColor',[1 1 1],'LineWidth',1,'HitTest','off');
            statusText = replace(A.status(index),'-',' ');
            if A.status(index) == "model-invalid", statusText = statusText + " (" + A.modelStatus(index) + ")"; end
            rgb = A.rgbSelected(index,:); xyz = A.XYZ(index,:);
            app.SelectionLabel.Text = {sprintf('Requested: %s = %.4g   |   %s = %.4g   |   %s = %.4g',A.spec.x,A.X(index),A.spec.y,A.Y(index),A.spec.fixed,app.State.constant), ...
                sprintf('%s   |   XYZ (Yw=1): %.5g  %.5g  %.5g',statusText,xyz), ...
                sprintf('%s RGB: %.5g  %.5g  %.5g',app.State.space,rgb)};
        end
        function data = snapshot(app)
            data = struct('version',ColorAtlasScience.version(),'state',app.State,'atlas',app.Atlas,'selectedIndex',app.SelectedIndex);
        end
        function showHelp(app)
            if ~isempty(app.HelpFigure) && isvalid(app.HelpFigure), app.HelpFigure.Visible='on'; figure(app.HelpFigure); return; end
            app.HelpFigure = uifigure('Name','Color Atlas | Model and preview guide','Position',[150 120 760 700],'Color',app.Chrome);
            theme(app.HelpFigure,'dark');
            layout = uigridlayout(app.HelpFigure,[1 1],'Padding',[0 0 0 0]);
            uihtml(layout,'HTMLSource',fullfile(fileparts(mfilename('fullpath')),'ColorAtlasHelp.html'));
        end
    end
    methods (Access = private)
        function finishRefresh(app), app.Busy = false; end
        function s = defaults(~)
            s = struct('model',"ciecam02",'plane',"h-C-J",'space',"srgb",'white',"d65", ...
                'vision',"trichromat",'surround',"average",'laMode',"explicit",'La',20,'Lw',100, ...
                'Yb',20,'dMode',"automatic",'D',1,'backgroundL',50,'constant',180);
        end
        function value = scalarText(~,value,name)
            assert((isstring(value) && isscalar(value) && ~ismissing(value)) || ...
                (ischar(value) && isrow(value) && ~isempty(value)), ...
                'ColorAtlas:state','State field %s must be a character row or scalar string.',name);
            value = string(value);
        end
        function validateState(~,s)
            mustBeMember(s.space,["srgb","adobe-rgb-1998","prophoto-rgb","linear-rgb"]);
            mustBeMember(s.white,["d65","d50","d55","a","c","e"]);
            mustBeMember(s.vision,["trichromat","protan","deutan","tritan"]);
            mustBeMember(s.surround,["average","dim","dark"]);
            mustBeMember(s.laMode,["explicit","derived"]); mustBeMember(s.dMode,["automatic","manual"]);
            fields = {'La','Lw','Yb','D','backgroundL','constant'};
            for k=1:numel(fields), validateattributes(s.(fields{k}),{'double'},{'real','finite','scalar'}); end
            assert(s.La>=0.1 && s.La<=10000 && s.Lw>=1 && s.Lw<=10000 && s.Yb>=0.1 && s.Yb<=100, ...
                'ColorAtlas:conditions','Conditions are outside the app exploration ranges.');
            assert(s.D>=0 && s.D<=1 && s.backgroundL>=0 && s.backgroundL<=100,'ColorAtlas:conditions','Invalid adaptation or Lab background.');
        end
        function v = attributeDefault(~,a)
            if strcmp(a,'h'), v=180; else, v=50; end
        end
        function lim = attributeLimits(~,a,Qwhite)
            switch a
                case 'h', lim=[0 360];
                case 'Q', lim=[0 Qwhite];
                otherwise, lim=[0 100];
            end
        end
        function v = samples(app,a,Qwhite)
            lim=app.attributeLimits(a,Qwhite);
            if strcmp(a,'h'), v=0:10:350; else, v=linspace(lim(1),lim(2),21); end
        end
        function controlChanged(app,field,value)
            if ~app.Busy, app.setState(struct(field,value)); end
        end
        function sliderChanging(app,value)
            if app.Busy, return; end
            app.State.constant=value;
            app.refresh();
            drawnow limitrate;
        end
        function atlasClick(app)
            point=app.UIAxes.CurrentPoint;
            app.selectCell(app.hitTest(point(1,1),point(1,2)));
        end
        function syncControls(app,limits,spec)
            s=app.State; isLab=s.model=="cielab";
            app.ModelDropDown.Value=char(s.model);
            specs=app.planeSpecs(s.model);
            app.PlaneDropDown.Items={specs.label}; app.PlaneDropDown.ItemsData={specs.key}; app.PlaneDropDown.Value=char(s.plane);
            app.SpaceDropDown.Value=char(s.space); app.WhiteDropDown.Value=char(s.white);
            app.VisionDropDown.Value=char(s.vision); app.SurroundDropDown.Value=char(s.surround);
            app.LaModeDropDown.Value=char(s.laMode); app.LaSpinner.Value=s.La; app.LwSpinner.Value=s.Lw;
            app.YbSpinner.Value=s.Yb; app.DModeDropDown.Value=char(s.dMode); app.DSpinner.Value=s.D;
            app.BackgroundSpinner.Value=s.backgroundL;
            camControls={app.SurroundDropDown,app.LaModeDropDown,app.YbSpinner,app.DModeDropDown};
            for k=1:numel(camControls), camControls{k}.Enable=matlab.lang.OnOffSwitchState(~isLab); end
            app.LaSpinner.Enable=matlab.lang.OnOffSwitchState(~isLab && s.laMode=="explicit");
            app.LwSpinner.Enable=matlab.lang.OnOffSwitchState(~isLab && s.laMode=="derived");
            app.DSpinner.Enable=matlab.lang.OnOffSwitchState(~isLab && s.dMode=="manual");
            app.BackgroundSpinner.Enable=matlab.lang.OnOffSwitchState(isLab);
            app.ConstantSpinner.Limits=limits; app.ConstantSpinner.Value=s.constant;
            app.ConstantSlider.Limits=limits; app.ConstantSlider.Value=s.constant;
            app.ConstantSlider.MajorTicks=linspace(limits(1),limits(2),6); app.ConstantSlider.MinorTicks=[];
            app.ConstantLabel.Text=sprintf('Fixed %s',app.attributeLabel(spec.fixed));
            app.ModelLabel.Text=ColorAtlasScience.modelLabel(s.model);
            if isLab
                app.ConditionsLabel.Text=sprintf('%s adopted white  |  Background L* %.1f  |  sRGB preview',upper(s.white),s.backgroundL);
            else
                app.ConditionsLabel.Text=sprintf('%s  |  La %.3g cd/m²  |  Yb %.3g / 100  |  D %.3f  |  sRGB preview',upper(s.white),app.Atlas.La,s.Yb,app.Atlas.D);
            end
        end
        function label=attributeLabel(~,a)
            switch a
                case 'L', label='L* · lightness'; case 'J', label='J · lightness';
                case 'Q', label='Q · brightness'; case 'C', label='C · chroma';
                case 'M', label='M · colorfulness'; case 's', label='s · saturation';
                case 'h', label='h · hue angle (°)';
            end
        end
        function drawAtlas(app)
            A=app.Atlas; ax=app.UIAxes;
            cla(ax); app.SelectionOutline=gobjects(0);
            ax.Color=A.backgroundRGB; ax.XColor=app.Muted; ax.YColor=app.Muted;
            hold(ax,'on');
            good=A.status=="displayable"; clipped=A.status=="clipped-preview";
            app.patchCells(good,A.rgbDisplay(good,:),'none',0.5);
            app.patchCells(clipped,A.rgbDisplay(clipped,:),[1 0.65 0.22],1.1);
            % Missing cells remain visible as selectable, classified samples. A
            % neutral dot means outside the selected gamut, a cross model-invalid.
            outside=A.status=="outside-selected-gamut"; invalid=A.status=="model-invalid";
            % Choose the higher-contrast black/white status mark using sRGB
            % relative luminance. This changes annotations, never patch colors.
            linearBG=A.backgroundRGB/12.92;
            nonlinear=A.backgroundRGB>0.04045;
            linearBG(nonlinear)=((A.backgroundRGB(nonlinear)+0.055)/1.055).^2.4;
            backgroundY=linearBG*[0.2126;0.7152;0.0722];
            markerColor=[0 0 0];
            if 1.05/(backgroundY+0.05) > (backgroundY+0.05)/0.05, markerColor=[1 1 1]; end
            plot(ax,A.X(outside),A.Y(outside),'.','Color',markerColor,'MarkerSize',3,'HitTest','off');
            plot(ax,A.X(invalid),A.Y(invalid),'x','Color',markerColor,'MarkerSize',3,'HitTest','off');
            hx=diff(A.x(1:2))/2; hy=diff(A.y(1:2))/2;
            ax.XLim=[A.x(1)-hx A.x(end)+hx]; ax.YLim=[A.y(1)-hy A.y(end)+hy];
            xlabel(ax,app.attributeLabel(A.spec.x),'Color',app.Text,'FontSize',13);
            ylabel(ax,app.attributeLabel(A.spec.y),'Color',app.Text,'FontSize',13);
            if strcmp(A.spec.x,'h'), ax.XTick=0:60:350; else, ax.XTick=linspace(A.x(1),A.x(end),6); end
            if strcmp(A.spec.y,'h'), ax.YTick=0:60:350; else, ax.YTick=linspace(A.y(1),A.y(end),6); end
            ax.YDir='normal'; ax.XGrid='off'; ax.YGrid='off'; ax.Box='off';
            ax.Toolbar.Visible='off'; disableDefaultInteractivity(ax);
            app.StatusLabel.Text={sprintf('%d displayable   ·   %d clipped   ·   %d outside gamut   ·   %d invalid',sum(good),sum(clipped),sum(outside),sum(invalid)), ...
                'Orange edge: clipped sRGB preview    · outside selected gamut    × model invalid'};
            app.selectCell(0);
        end
        function patchCells(app,mask,rgb,edge,width)
            indices=find(mask); if isempty(indices), return; end
            A=app.Atlas; n=numel(indices);
            hx=diff(A.x(1:2))*A.cellFraction/2; hy=diff(A.y(1:2))*A.cellFraction/2;
            x=A.X(indices); y=A.Y(indices);
            vertices=[x-hx y-hy; x+hx y-hy; x+hx y+hy; x-hx y+hy];
            faces=[(1:n)' (1:n)'+n (1:n)'+2*n (1:n)'+3*n];
            patch(app.UIAxes,'Vertices',vertices,'Faces',faces,'FaceVertexCData',rgb,'FaceColor','flat', ...
                'EdgeColor',edge,'LineWidth',width,'ButtonDownFcn',@(~,~)app.atlasClick());
        end
        function createUI(app)
            app.UIFigure=uifigure('Name',['Color Atlas ' ColorAtlasScience.version() ' | by Fernando Voltolini de Azambuja'], ...
                'Position',[100 100 1180 800],'Color',app.Chrome,'Visible','off','AutoResizeChildren','off', ...
                'CloseRequestFcn',@(~,~)delete(app));
            theme(app.UIFigure,'dark');
            app.RootGrid=uigridlayout(app.UIFigure,[2 2],'RowHeight',{58,'1x'}, ...
                'ColumnWidth',{310,'1x'},'Padding',[18 12 18 14],'RowSpacing',12,'ColumnSpacing',18,'BackgroundColor',app.Chrome);
            header=uigridlayout(app.RootGrid,[1 4],'ColumnWidth',{'1x',90,126,76},'Padding',[0 0 0 0],'BackgroundColor',app.Chrome);
            header.Layout.Row=1; header.Layout.Column=[1 2];
            titleGrid=uigridlayout(header,[2 1],'RowHeight',{30,20},'RowSpacing',2, ...
                'Padding',[0 0 0 0],'BackgroundColor',app.Chrome);
            app.TitleLabel=uilabel(titleGrid,'Text','COLOR ATLAS','FontSize',23,'FontWeight','bold','FontColor',app.Text);
            app.AuthorLabel=uilabel(titleGrid,'Text','by Fernando Voltolini de Azambuja', ...
                'FontSize',13,'FontColor',app.Muted);
            uilabel(header,'Text',['v' ColorAtlasScience.version()],'FontSize',13,'FontColor',app.Muted);
            uibutton(header,'Text','Reset defaults','FontSize',13,'BackgroundColor',app.Field,'FontColor',app.Text,'ButtonPushedFcn',@(~,~)app.resetDefaults());
            uibutton(header,'Text','Guide','FontSize',13,'BackgroundColor',app.Field,'FontColor',app.Text,'ButtonPushedFcn',@(~,~)app.showHelp());
            sidePanel=uipanel(app.RootGrid,'BorderType','none','BackgroundColor',app.Panel); sidePanel.Layout.Row=2; sidePanel.Layout.Column=1;
            % Keep all controls and notes visible at the default window size.
            heights={22,24,30,24,30,4,22,30,30,30,4,22,30,30,30,30,30,30,30,4,22,30,52};
            app.Sidebar=uigridlayout(sidePanel,[numel(heights) 2],'RowHeight',heights,'ColumnWidth',{110,'1x'}, ...
                'Padding',[14 8 14 8],'RowSpacing',4,'ColumnSpacing',10,'Scrollable','on','BackgroundColor',app.Panel);
            app.section('ATLAS',1);
            app.fullLabel('Appearance model',2);
            app.ModelDropDown=app.dropdown(3,'model',{'CIELAB','CIECAM02','CAM16 · Li 2017','Hellwig 2022','Hellwig / CAT02 composition'}, ...
                {'cielab','ciecam02','cam16','hellwig2022','hellwig2022cat02'},true);
            app.fullLabel('Plane · fixed attribute and axes',4);
            sp=app.planeSpecs(app.State.model);
            app.PlaneDropDown=app.dropdown(5,'plane',{sp.label},{sp.key},true);
            app.section('COLOR AND VISION',7);
            app.rowLabel('Selected gamut',8); app.SpaceDropDown=app.dropdown(8,'space',{'sRGB','Adobe RGB','ProPhoto','Linear sRGB'}, ...
                {'srgb','adobe-rgb-1998','prophoto-rgb','linear-rgb'},false);
            app.rowLabel('Adopted white',9); app.WhiteDropDown=app.dropdown(9,'white',{'D65','D50','D55','A','C','E'},{'d65','d50','d55','a','c','e'},false);
            app.rowLabel('Vision model',10); app.VisionDropDown=app.dropdown(10,'vision',{'Trichromat','Protan (HPE)','Deutan (HPE)','Tritan (HPE)'}, ...
                {'trichromat','protan','deutan','tritan'},false);
            app.section('VIEWING CONDITIONS',12);
            app.rowLabel('Surround',13); app.SurroundDropDown=app.dropdown(13,'surround',{'Average','Dim','Dark'},{'average','dim','dark'},false);
            app.rowLabel('La source',14); app.LaModeDropDown=app.dropdown(14,'laMode',{'Explicit La','From Lw'},{'explicit','derived'},false);
            app.rowLabel('La · cd/m²',15); app.LaSpinner=app.spinner(15,'La',[0.1 10000],1);
            app.rowLabel('Lw · cd/m²',16); app.LwSpinner=app.spinner(16,'Lw',[1 10000],10);
            app.rowLabel('Yb · Yw = 100',17); app.YbSpinner=app.spinner(17,'Yb',[0.1 100],1);
            app.rowLabel('Adaptation D',18); app.DModeDropDown=app.dropdown(18,'dMode',{'Automatic','Manual'},{'automatic','manual'},false);
            app.rowLabel('Manual D',19); app.DSpinner=app.spinner(19,'D',[0 1],0.05);
            app.section('CIELAB BACKGROUND',21);
            app.rowLabel('Background L*',22); app.BackgroundSpinner=app.spinner(22,'backgroundL',[0 100],5);
            app.fullLabel({'sRGB preview · CVD uses HPE', ...
                'CAM background: Yb/Yw','Derived La = Lw × Yb/100'},23,true);
            app.PlotGrid=uigridlayout(app.RootGrid,[6 1],'RowHeight',{42,24,'1x',46,90,98}, ...
                'Padding',[0 0 0 0],'RowSpacing',8,'BackgroundColor',app.Chrome);
            app.PlotGrid.Layout.Row=2; app.PlotGrid.Layout.Column=2;
            app.ModelLabel=uilabel(app.PlotGrid,'FontColor',app.Text,'FontSize',17,'FontWeight','bold','WordWrap','on');
            app.ConditionsLabel=uilabel(app.PlotGrid,'FontColor',app.Muted,'FontSize',12);
            app.UIAxes=uiaxes(app.PlotGrid,'FontSize',12,'Color',[.5 .5 .5],'XColor',app.Muted,'YColor',app.Muted, ...
                'ButtonDownFcn',@(~,~)app.atlasClick());
            app.UIAxes.Layout.Row=3;
            app.StatusLabel=uilabel(app.PlotGrid,'FontColor',app.Muted,'FontSize',11,'WordWrap','on');
            constant=uigridlayout(app.PlotGrid,[2 2],'RowHeight',{30,38},'ColumnWidth',{'1x',115}, ...
                'Padding',[2 0 2 8],'RowSpacing',8,'BackgroundColor',app.Chrome);
            app.ConstantLabel=uilabel(constant,'FontColor',app.Text,'FontSize',14,'FontWeight','bold');
            app.ConstantSpinner=uispinner(constant,'Limits',[0 350],'Value',180,'Step',1,'FontSize',14,'FontColor',app.Text,'BackgroundColor',app.Field, ...
                'ValueChangedFcn',@(src,~)app.controlChanged('constant',src.Value));
            app.ConstantSlider=uislider(constant,'Limits',[0 350],'Value',180,'FontColor',app.Muted,'FontSize',11, ...
                'ValueChangingFcn',@(~,event)app.sliderChanging(event.Value),'ValueChangedFcn',@(src,~)app.controlChanged('constant',src.Value));
            app.ConstantSlider.Layout.Row=2; app.ConstantSlider.Layout.Column=[1 2];
            app.SelectionLabel=uilabel(app.PlotGrid,'FontColor',app.Text,'FontSize',12,'WordWrap','on', ...
                'BackgroundColor',app.Panel,'VerticalAlignment','center');
            app.UIFigure.SizeChangedFcn=@(~,~)app.resize();
            app.resize();
        end
        function resize(app)
            if app.UIFigure.Position(3)<1020, app.RootGrid.ColumnWidth={280,'1x'}; else, app.RootGrid.ColumnWidth={310,'1x'}; end
        end
        function section(app,text,row)
            label=uilabel(app.Sidebar,'Text',text,'FontColor',app.Accent,'FontSize',11,'FontWeight','bold');
            label.Layout.Row=row; label.Layout.Column=[1 2];
        end
        function fullLabel(app,text,row,wrap)
            if nargin<4, wrap=false; end
            label=uilabel(app.Sidebar,'Text',text,'FontColor',app.Muted,'FontSize',13,'WordWrap',matlab.lang.OnOffSwitchState(wrap));
            label.Layout.Row=row; label.Layout.Column=[1 2];
        end
        function rowLabel(app,text,row)
            label=uilabel(app.Sidebar,'Text',text,'FontColor',app.Text,'FontSize',13);
            label.Layout.Row=row; label.Layout.Column=1;
        end
        function dd=dropdown(app,row,field,items,data,full)
            dd=uidropdown(app.Sidebar,'Items',items,'ItemsData',data,'FontSize',13,'FontColor',app.Text,'BackgroundColor',app.Field, ...
                'ValueChangedFcn',@(src,~)app.controlChanged(field,src.Value));
            dd.Layout.Row=row;
            if full, dd.Layout.Column=[1 2]; else, dd.Layout.Column=2; end
            dd.Tooltip=strjoin(string(items),newline);
        end
        function sp=spinner(app,row,field,limits,step)
            sp=uispinner(app.Sidebar,'Limits',limits,'Value',app.State.(field),'Step',step,'FontSize',13, ...
                'FontColor',app.Text,'BackgroundColor',app.Field,'ValueDisplayFormat','%.3g', ...
                'ValueChangedFcn',@(src,~)app.controlChanged(field,src.Value));
            sp.Layout.Row=row; sp.Layout.Column=2;
        end
    end
end
