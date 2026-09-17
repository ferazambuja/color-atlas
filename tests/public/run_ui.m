function run_ui()
% Native UI integration checks for controls, geometry and window lifetime.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'app'));
sourcePaths={'VERSION','app/ColorAtlasScience.m','app/ColorAtlas.m','app/ColorAtlasHelp.html', ...
    'tests/public/run_ui.m','tests/public/source_record.m','tests/public/hash_file.m'};
sources=source_record(root,sourcePaths);
out=fullfile(root,'validation','results'); if ~isfolder(out),mkdir(out);end
rows=struct('name',{},'passed',{},'detail',{});
routes=struct('model',{},'plane',{},'samples',{},'drawable',{},'invalid',{},'passed',{});
dimensions=struct('width',{},'height',{},'plot',{},'axes',{},'controls',{},'contained',{},'overlap',{},'passed',{});
sidebar=struct;
app=[]; sentinel=[];
beforeDefaultKey=get(groot,'DefaultFigureWindowKeyPressFcn');
sourceSHAStart=hashFile(fullfile(root,'app','ColorAtlas.m'));
try
    sentinel=uifigure('Visible','off','Name','Color Atlas independent UI sentinel');
    sentinelCleanup=onCleanup(@()closeHandle(sentinel)); %#ok<NASGU>
    sentinel.WindowKeyPressFcn=@(~,~)disp('sentinel keyboard callback');
    sentinelCallback=sentinel.WindowKeyPressFcn;
    app=ColorAtlas(); app.UIFigure.Visible='off'; drawnow;
    appCleanup=onCleanup(@()closeHandle(app)); %#ok<NASGU>
    record('versioned window',contains(string(app.UIFigure.Name),ColorAtlasScience.version()),app.UIFigure.Name);
    record('window title names the developer',contains(string(app.UIFigure.Name),'Fernando Voltolini de Azambuja'),app.UIFigure.Name);
    record('visible full-name credit',strcmp(app.AuthorLabel.Text,'by Fernando Voltolini de Azambuja') && ...
        strcmp(app.AuthorLabel.Visible,'on') && contrast(app.AuthorLabel.FontColor,app.AuthorLabel.Parent.BackgroundColor)>=4.5, ...
        'Compact developer credit remains distinct from scientific plot labels');
    record('supported vision modes',isequal(sort(string(app.VisionDropDown.ItemsData)), ...
        sort(["trichromat","protan","deutan","tritan"])),'Declared vision keys are available exactly once');
    record('supported appearance models',isequal(sort(string(app.ModelDropDown.ItemsData)), ...
        sort(["cielab","ciecam02","cam16","hellwig2022","hellwig2022cat02"])),'Declared model keys are available exactly once');
    record('native keyboard isolation',isempty(app.UIFigure.WindowKeyPressFcn) && ...
        isequal(sentinel.WindowKeyPressFcn,sentinelCallback) && isequal(get(groot,'DefaultFigureWindowKeyPressFcn'),beforeDefaultKey), ...
        'No app/global key handler intercepts numeric editing or changes another figure');

    % Drive the actual native ValueChangedFcn callbacks, not only setState.
    models=string(app.ModelDropDown.ItemsData);
    for model=models
        change(app.ModelDropDown,model);
        planes=string(app.PlaneDropDown.ItemsData);
        for plane=planes
            try
                change(app.PlaneDropDown,plane); A=app.Atlas;
                drawable=A.status=="displayable" | A.status=="clipped-preview";
                finite=all(isfinite(A.rgbDisplay(drawable,:)),'all') && isreal(A.rgbDisplay);
                bounds=all(A.rgbDisplay(drawable,:)>=0 & A.rgbDisplay(drawable,:)<=1,'all');
                ok=any(drawable) && finite && bounds && app.State.model==model && app.State.plane==plane;
                routes(end+1)=struct('model',char(model),'plane',char(plane),'samples',numel(A.status), ...
                    'drawable',sum(drawable),'invalid',sum(A.status=="model-invalid"),'passed',ok); %#ok<AGROW>
                record("route "+model+" / "+plane,ok,sprintf('%d drawable / %d samples',sum(drawable),numel(A.status)));
            catch e
                record("route "+model+" / "+plane,false,e.identifier+": "+e.message);
            end
        end
    end
    record('all model-plane routes covered',numel(routes)==39,sprintf('%d routes',numel(routes)));

    app.setState(struct('model',"cam16",'plane',"J-h-C",'constant',50,'space',"srgb",'white',"d65",'vision',"trichromat"));
    for space=string(app.SpaceDropDown.ItemsData)
        change(app.SpaceDropDown,space); assertAtlas("gamut "+space);
    end
    change(app.SpaceDropDown,"srgb");
    for white=string(app.WhiteDropDown.ItemsData)
        change(app.WhiteDropDown,white); assertAtlas("white "+white);
    end
    change(app.WhiteDropDown,"d65");
    for vision=string(app.VisionDropDown.ItemsData)
        change(app.VisionDropDown,vision); assertAtlas("vision "+vision);
    end
    change(app.VisionDropDown,"trichromat");

    % The UI must preserve the scientific layer's gamut/preview distinction.
    app.setState(struct('model',"cielab",'plane',"L-h-C",'constant',50,'space',"prophoto-rgb"));
    A=app.Atlas; P=ColorAtlasScience.previewCells(A.XYZ,app.State.space,app.State.white);
    record('wide-gamut preview states retained',isequal(P.status,A.status) && any(A.status=="clipped-preview"), ...
        sprintf('%d clipped preview cells',sum(A.status=="clipped-preview")));
    app.setState(struct('vision',"tritan")); A=app.Atlas;
    P=ColorAtlasScience.previewCells(A.XYZ,app.State.space,app.State.white);
    record('selected gamut follows simulated XYZ',isequal(A.status,P.status) && ...
        max(abs(A.originalXYZ(:)-A.XYZ(:)),[],'omitnan')>1e-3,'Projected XYZ is the stated gamut input');

    % Every enabled viewing parameter has its advertised effect.
    app.setState(struct('model',"cam16",'plane',"J-h-C",'constant',50,'space',"srgb", ...
        'vision',"trichromat",'white',"d65",'laMode',"explicit",'La',20,'Lw',100,'Yb',20,'dMode',"automatic"));
    record('explicit La controls',on(app.LaSpinner) && ~on(app.LwSpinner) && ~on(app.DSpinner),'La editable; derived Lw and manual D disabled');
    base=app.Atlas.originalXYZ; change(app.LaSpinner,40);
    record('La effect',difference(base,app.Atlas.originalXYZ)>1e-6,sprintf('actual La %.5g',app.Atlas.La));
    change(app.LaModeDropDown,"derived");
    record('derived La controls',~on(app.LaSpinner) && on(app.LwSpinner),'Derived mode exposes Lw');
    change(app.LwSpinner,300);
    record('Lw derives La',abs(app.Atlas.La-60)<1e-12,sprintf('La %.5g',app.Atlas.La));
    change(app.YbSpinner,50);
    record('Yb derives La and background',abs(app.Atlas.La-150)<1e-12 && ...
        max(abs(app.Atlas.backgroundXYZ-whitepoint('d65')*.5))<1e-12,'La = Lw*Yb/100; background Y = Yb/100');
    change(app.LaModeDropDown,"explicit"); change(app.LaSpinner,20); change(app.YbSpinner,20);
    base=app.Atlas.originalXYZ; oldD=app.Atlas.D;
    change(app.SurroundDropDown,"dark");
    record('surround and automatic D effect',difference(base,app.Atlas.originalXYZ)>1e-6 && abs(app.Atlas.D-oldD)>1e-3,'Dark surround changes model and automatic D');
    change(app.DModeDropDown,"manual"); change(app.DSpinner,.3);
    record('manual D control',on(app.DSpinner) && abs(app.Atlas.D-.3)<1e-12,'Manual D is operative');
    change(app.SurroundDropDown,"average");
    record('manual D remains authoritative',abs(app.Atlas.D-.3)<1e-12,'Surround does not override explicit D');
    change(app.DModeDropDown,"automatic");
    record('automatic D equation',abs(app.Atlas.D-(1-exp((-20-42)/92)/3.6))<1e-13,'F=1, La=20');

    app.setState(struct('model',"hellwig2022",'plane',"Q-h-C",'La',200,'constant',1e6));
    highQ=app.Atlas.Qwhite; record('Q initial clamp',abs(app.State.constant-highQ)<1e-12,'Fixed Q clamps to current reference-white sampling limit');
    change(app.LaSpinner,.1); lowQ=app.Atlas.Qwhite;
    record('Q condition change clamps state and controls',lowQ<highQ && abs(app.State.constant-lowQ)<1e-12 && ...
        abs(app.ConstantSlider.Limits(2)-lowQ)<1e-12 && abs(app.ConstantSpinner.Value-lowQ)<1e-12,'No stale Q after La change');
    app.setState(struct('plane',"h-C-Q",'constant',180));
    record('Q axis shares current scale',abs(app.Atlas.y(end)-app.Atlas.Qwhite)<1e-12,'Q sampling agrees with reference-white brightness');
    change(app.ModelDropDown,"cielab");
    record('CAM to Lab resets safely',app.State.model=="cielab" && all(isfinite(app.ConstantSlider.Limits)) && ...
        ~on(app.LaSpinner) && ~on(app.LwSpinner) && ~on(app.YbSpinner) && ~on(app.DModeDropDown) && on(app.BackgroundSpinner), ...
        'CAM controls disabled; Lab background active');
    change(app.BackgroundSpinner,20); y20=app.Atlas.backgroundXYZ(2);
    change(app.BackgroundSpinner,80); y80=app.Atlas.backgroundXYZ(2);
    record('CIELAB background direction',y80>y20 && abs(y20-lab2xyz([20 0 0],'WhitePoint','d65')*[0;1;0])<1e-12,'Direct background L* increases luminance');
    change(app.ConstantSpinner,90); a=app.State.constant;
    change(app.ConstantSlider,120);
    record('fixed value callbacks synchronize',a==90 && app.State.constant==120 && app.ConstantSpinner.Value==120,'Slider and numeric value agree');
    cb=app.ConstantSlider.ValueChangingFcn;cb(app.ConstantSlider,struct('Value',123.5));drawnow;
    record('slider drag preview synchronizes',app.State.constant==123.5 && app.ConstantSpinner.Value==123.5,'Native ValueChangingFcn path');

    % Cell coordinates, geometry, gaps and invalid-cell inspection.
    app.setState(struct('model',"cam16",'plane',"C-h-J",'constant',30,'La',20,'space',"srgb"));
    A=app.Atlas; indices=[1 ceil(numel(A.X)/2) numel(A.X)];
    for index=indices
        record("hit center "+index,app.hitTest(A.X(index),A.Y(index))==index,'First, interior and last sample coordinates');
    end
    index=sub2ind([numel(A.y),numel(A.x)],10,10); hx=diff(A.x(1:2))*A.cellFraction/2; hy=diff(A.y(1:2))*A.cellFraction/2;
    edges=[-hx*.999999 0;hx*.999999 0;0 -hy*.999999;0 hy*.999999];
    edgeOk=true;
    for k=1:4,edgeOk=edgeOk && app.hitTest(A.X(index)+edges(k,1),A.Y(index)+edges(k,2))==index;end
    record('cell edge stays in same sample',edgeOk,'Four points just inside cell edges');
    record('intercell gap has no sample',app.hitTest(mean(A.x(1:2)),A.y(1))==0,'Horizontal gap');
    record('outside and nonfinite hit has no sample',app.hitTest(A.x(1)-2*hx,A.y(1))==0 && app.hitTest(NaN,0)==0,'Outside bounds and NaN');
    record('hue seam unique',numel(A.x)==36 && numel(unique(mod(A.x,360)))==36 && A.x(end)==350,'0:10:350');
    invalid=find(A.status=="model-invalid",1);
    record('invalid cell exists for inspection',~isempty(invalid),'Zero J with positive C');
    if ~isempty(invalid)
        app.selectCell(invalid);
        record('invalid cell classified in inspector',contains(join(string(app.SelectionLabel.Text),' '),'model invalid') && ...
            app.snapshot().selectedIndex==invalid,'No neighboring valid sample substituted');
    end
    outside=find(A.status=="outside-selected-gamut",1);
    record('outside-gamut cell exists for inspection',~isempty(outside),'The inspector fixture must exercise this status');
    if ~isempty(outside)
        app.selectCell(outside);
        record('outside-gamut cell classified',contains(join(string(app.SelectionLabel.Text),' '),'outside selected gamut') && ...
            app.snapshot().selectedIndex==outside,'Inspector classifies the selected sample');
    end
    app.selectCell(0); record('gap clears inspector',app.snapshot().selectedIndex==0,'No selection');
    patchHandles=findobj(app.UIAxes,'Type','patch'); geometryOk=true;
    renderedIndices=[]; centerTolerance=1e-10;
    for ph=patchHandles'
        V=ph.Vertices; F=ph.Faces;
        centers=zeros(size(F,1),2);
        for vertex=1:size(F,2),centers=centers+V(F(:,vertex),1:2)/size(F,2);end
        for k=1:size(centers,1)
            index=app.hitTest(centers(k,1),centers(k,2));
            if index==0,geometryOk=false;continue;end
            geometryOk=geometryOk && max(abs(centers(k,:)-[A.X(index) A.Y(index)]))<=centerTolerance;
            renderedIndices(end+1)=index; %#ok<AGROW>
        end
    end
    drawable=find(A.status=="displayable" | A.status=="clipped-preview");
    geometryOk=geometryOk && isequal(sort(renderedIndices(:)),drawable(:));
    record('rendered patch centers match samples exactly',geometryOk && ~isempty(patchHandles), ...
        'Every drawable sample has one patch centered on its coordinates; no shifted, duplicate or missing cells');
    marks=findobj(app.UIAxes,'Type','line'); contrastOk=true; markContrasts=[];
    for mh=marks'
        if ~isempty(mh.XData)
            ratio=contrast(mh.Color,app.UIAxes.Color);markContrasts(end+1)=ratio; %#ok<AGROW>
            contrastOk=contrastOk && ratio>=3;
        end
    end
    record('non-color status marks contrast',contrastOk && ~isempty(markContrasts),sprintf('Minimum %.4g:1',min(markContrasts)));
    labelContrast=contrast(app.SelectionLabel.FontColor,app.SelectionLabel.BackgroundColor);
    record('inspector active text contrast',labelContrast>=4.5,sprintf('%.4g:1',labelContrast));

    % Primary sidebar controls and notes must fit without scrolling at launch.
    app.setState(struct('model',"cielab",'plane',"L-h-C",'constant',50));
    app.UIFigure.Position=[100 100 1180 800]; drawnow; settleLayout();
    scroll(app.Sidebar,'top'); pause(.3); drawnow;
    panel=getpixelposition(app.Sidebar.Parent,true);
    bg=getpixelposition(app.BackgroundSpinner,true);
    sideChildren=app.Sidebar.Children; sideRects=zeros(numel(sideChildren),4);
    for k=1:numel(sideChildren),sideRects(k,:)=getpixelposition(sideChildren(k),true);end
    fits=all(sideRects(:,1)>=panel(1)-1 & sideRects(:,2)>=panel(2)-1 & ...
        sideRects(:,1)+sideRects(:,3)<=panel(1)+panel(3)+1 & ...
        sideRects(:,2)+sideRects(:,4)<=panel(2)+panel(4)+1);
    overlap=false;
    for a=1:size(sideRects,1),for b=a+1:size(sideRects,1)
        dx=min(sideRects(a,1)+sideRects(a,3),sideRects(b,1)+sideRects(b,3))-max(sideRects(a,1),sideRects(b,1));
        dy=min(sideRects(a,2)+sideRects(a,4),sideRects(b,2)+sideRects(b,4))-max(sideRects(a,2),sideRects(b,2));
        overlap=overlap || (dx>1 && dy>1);
    end,end
    sidebar=struct('panel',panel,'backgroundControl',bg,'children',sideRects,'contained',fits,'overlap',overlap);
    record('CIELAB background visible at default size',on(app.BackgroundSpinner) && ...
        bg(2)>=panel(2) && bg(2)+bg(4)<=panel(2)+panel(4),'Entire active control visible without scrolling at 1180x800');
    record('default sidebar controls and notes contained',fits && ~overlap,'All sidebar children fit without overlap at 1180x800');

    % Native grid layout sizing, including the declared narrow working window.
    app.setState(struct('model',"hellwig2022cat02",'plane',"h-C-J"));
    sizes=[900 650;1100 720;1440 900];
    for k=1:size(sizes,1)
        app.UIFigure.Position=[100 100 sizes(k,:)]; drawnow;
        if ~isempty(app.UIFigure.SizeChangedFcn),app.UIFigure.SizeChangedFcn(app.UIFigure,struct());drawnow;end
        settleLayout();
        fig=app.UIFigure.Position; plot=getpixelposition(app.PlotGrid,true); ax=getpixelposition(app.UIAxes,true);
        controls={app.ModelLabel,app.ConditionsLabel,app.StatusLabel,app.ConstantSpinner,app.ConstantSlider,app.SelectionLabel};
        headerControls=findall(app.AuthorLabel.Parent.Parent,'-property','Text');
        controls=[controls num2cell(headerControls(:)')];
        contained=true; overlap=false; rects=zeros(numel(controls),4);
        for j=1:numel(controls)
            rects(j,:)=getpixelposition(controls{j},true);
            r=rects(j,:); contained=contained && all(r(3:4)>0) && r(1)>=-1 && r(2)>=-1 && r(1)+r(3)<=fig(3)+1 && r(2)+r(4)<=fig(4)+1;
        end
        % Controls nested in different rows must not overlap one another.
        for a=1:size(rects,1),for b=a+1:size(rects,1)
            dx=min(rects(a,1)+rects(a,3),rects(b,1)+rects(b,3))-max(rects(a,1),rects(b,1));
            dy=min(rects(a,2)+rects(a,4),rects(b,2)+rects(b,4))-max(rects(a,2),rects(b,2));
            overlap=overlap || (dx>1 && dy>1);
        end,end
        ok=contained && ~overlap && ax(3)>200 && ax(4)>100 && strcmp(app.Sidebar.Scrollable,'on');
        dimensions(k)=struct('width',sizes(k,1),'height',sizes(k,2),'plot',plot,'axes',ax,'controls',rects,'contained',contained,'overlap',overlap,'passed',ok); %#ok<AGROW>
        record(sprintf('layout %dx%d',sizes(k,:)),ok,'Main controls contained and separate; sidebar intentionally scrollable');
        credit=getpixelposition(app.AuthorLabel,true);
        record(sprintf('credit fits %dx%d',sizes(k,:)),credit(3)>=300 && credit(4)>=18, ...
            'Single-line full-name credit has room at the tested font size; header leaves are checked for overlap');
    end

    app.setState(struct('model',"cielab",'plane',"L-h-C",'constant',50));
    app.UIFigure.Position=[100 100 900 650]; drawnow;
    if ~isempty(app.UIFigure.SizeChangedFcn),app.UIFigure.SizeChangedFcn(app.UIFigure,struct());drawnow;end
    settleLayout();
    scroll(app.Sidebar,'bottom'); pause(.3); drawnow;
    panel=getpixelposition(app.Sidebar.Parent,true); bg=getpixelposition(app.BackgroundSpinner,true);
    sidebar.narrowPanel=panel; sidebar.narrowBackgroundAfterScroll=bg;
    record('narrow sidebar background reachable by scrolling',on(app.BackgroundSpinner) && ...
        bg(2)>=panel(2) && bg(2)+bg(4)<=panel(2)+panel(4),'Active Background L* control is fully visible after scrolling at 900x650');

    app.showHelp(); drawnow; firstHelp=app.HelpFigure; firstHelp.Visible='off';
    html=findall(firstHelp,'-isa','matlab.ui.control.HTML');
    record('help opens local resource',isscalar(html) && isfile(html.HTMLSource),'App-relative guide');
    app.showHelp(); app.HelpFigure.Visible='off';
    record('help reuses existing window',isequal(firstHelp,app.HelpFigure),'One owned guide window');
    delete(firstHelp); app.showHelp(); drawnow; app.HelpFigure.Visible='off';
    record('help reopens after close',isvalid(app.HelpFigure) && ~isequal(firstHelp,app.HelpFigure),'Fresh guide window');
    lastHelp=app.HelpFigure; appFigure=app.UIFigure; delete(app); app=[];
    record('app closes owned windows only',~isvalid(lastHelp) && ~isvalid(appFigure) && isvalid(sentinel) && ...
        isequal(sentinel.WindowKeyPressFcn,sentinelCallback),'Main and guide closed; unrelated figure preserved');
catch e
    record('unexpected UI test exception',false,e.identifier+": "+e.message);
end
sha=hashFile(fullfile(root,'app','ColorAtlas.m'));
record('tested UI source stayed unchanged',strcmp(sourceSHAStart,sha),'File hash checked before and after integration run');
sources=source_record(root,sourcePaths,sources);
report=struct('matlab',version,'runUTC',char(datetime('now','TimeZone','UTC')),'sourceSHA256',sha, ...
    'sources',sources, ...
    'checks',numel(rows),'failures',sum(~[rows.passed]),'results',rows,'routes',routes,'dimensions',dimensions,'sidebar',sidebar, ...
    'scope','Programmatic native callbacks and graphics geometry; rendered visual inspection is separate');
fid=fopen(fullfile(out,'ui-results.json'),'w');fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));fclose(fid);
fprintf('V2 native UI checks: %d; failures: %d; model/plane routes: %d\n',numel(rows),report.failures,numel(routes));
if report.failures>0,disp(rows(~[rows.passed]));end
assert(report.failures==0,'ColorAtlas:uiRegression','Native UI integration regression failed.');

    function record(name,passed,detail)
        rows(end+1)=struct('name',char(name),'passed',logical(passed),'detail',char(detail));
    end
    function change(control,value)
        if isstring(value),value=char(value);end
        control.Value=value; cb=control.ValueChangedFcn;cb(control,struct('Value',value));drawnow;
    end
    function tf=on(control),tf=strcmp(control.Enable,'on');end
    function d=difference(a,b),d=max(abs(a(:)-b(:)),[],'omitnan');end
    function assertAtlas(name)
        A=app.Atlas;drawn=A.status=="displayable" | A.status=="clipped-preview";
        record(name,any(drawn) && all(isfinite(A.rgbDisplay(drawn,:)),'all'),sprintf('%d drawn cells',sum(drawn)));
    end
    function ratio=contrast(a,b)
        rgb=[a;b];linear=rgb/12.92;mask=rgb>.04045;linear(mask)=((rgb(mask)+.055)/1.055).^2.4;
        y=linear*[.2126;.7152;.0722];ratio=(max(y)+.05)/(min(y)+.05);
    end
    function settleLayout()
        % uifigure grid geometry arrives asynchronously from the UI renderer;
        % drawnow alone can return the preceding window's nested layout.
        fig=app.UIFigure.Position;pad=app.RootGrid.Padding;
        expected=[fig(3)-sum(pad([1 3]))-app.RootGrid.ColumnSpacing-app.RootGrid.ColumnWidth{1}, ...
            fig(4)-sum(pad([2 4]))-app.RootGrid.RowSpacing-app.RootGrid.RowHeight{1}];
        previous=[];stable=0;
        for attempt=1:50
            pause(.1);drawnow;
            r=getpixelposition(app.PlotGrid,true);
            state=[r getpixelposition(app.ModelLabel,true) getpixelposition(app.UIAxes,true) getpixelposition(app.SelectionLabel,true)];
            if max(abs(r(3:4)-expected))<1 && isequal(state,previous),stable=stable+1;else,stable=0;end
            if stable>=2,return;end
            previous=state;
        end
        error('ColorAtlas:layoutTimeout','UI layout did not settle to the current window dimensions.');
    end
end

function closeHandle(h)
if ~isempty(h) && isvalid(h),delete(h);end
end

function sha=hashFile(file)
fid=fopen(file,'rb');bytes=fread(fid,Inf,'*uint8');fclose(fid);
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
sha=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));
end
