function report = run_input_contract()
% Public-input regressions. Returns results without rewriting retained artifacts.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'app'));
sourcePaths={'VERSION','app/ColorAtlasScience.m','app/ColorAtlas.m', ...
    'tests/public/run_input_contract.m','tests/public/source_record.m','tests/public/hash_file.m'};
sources=source_record(root,sourcePaths);
rows = struct('name',{},'passed',{},'detail',{});
w = [95.047 100 108.883];
sp = struct('J',50,'C',30,'h',120);

% Appearance text must not become character codes or parsed numbers. Arrays
% must be real numeric vectors; matrix flattening and empty batches are errors.
badValues = {'50',"50",{'50'},true,[],[10 20;30 40],struct('x',50)};
for model = ColorAtlasScience.MODELS
    for field = ["J","C","h"]
        for k = 1:numel(badValues)
            a = sp; a.(field) = badValues{k};
            rejected(model+" rejects malformed "+field+" / "+k, ...
                @()ColorAtlasScience.inverseCAM(model,a,w),"ColorAtlas:appearance");
        end
    end
    rejected(model+" rejects incompatible vector lengths", ...
        @()ColorAtlasScience.inverseCAM(model,struct('J',[40 50],'C',[10 20 30],'h',120),w),"ColorAtlas:appearance");
    rejected(model+" rejects complex correlates", ...
        @()ColorAtlasScience.inverseCAM(model,struct('J',50,'C',30+1i,'h',120),w),"ColorAtlas:complexAppearance");

    % Valid row and column vectors retain scalar broadcasting and numerical identity.
    a = struct('J',single([40 50]),'C',uint8(30),'h',int16([120;150]));
    [xyz,st] = ColorAtlasScience.inverseCAM(model,a,w,'La',uint8(20));
    reference = zeros(2,3);
    for k = 1:2
        reference(k,:) = ColorAtlasScience.inverseCAM(model, ...
            struct('J',double(a.J(k)),'C',30,'h',double(a.h(k))),w);
    end
    record(model+" preserves numeric vector broadcasting",all(st=="valid") && ...
        isequal(size(xyz),[2 3]) && max(abs(xyz-reference),[],'all')<1e-12,"");

    % Nonfinite numeric rows have an intentional per-row status contract.
    [xyz,st] = ColorAtlasScience.inverseCAM(model, ...
        struct('J',[50;NaN;Inf;0],'C',[30;30;30;0],'h',120),w,'D',NaN);
    record(model+" preserves nonfinite row isolation and black", ...
        all(st([1 4])=="valid") && all(st(2:3)=="not-finite") && ...
        all(isfinite(xyz(1,:))) && all(isnan(xyz(2:3,:)),'all') && ...
        isequal(xyz(4,:),[0 0 0]),join(st,','));
end

% Reject malformed arguments at their validators, not through unrelated failures.
direct = {
    'inverse white text', @()ColorAtlasScience.inverseCAM('cam16',sp,'abc'), 'MATLAB:validators:mustBeNumeric'
    'inverse La text', @()ColorAtlasScience.inverseCAM('cam16',sp,w,'La','2'), 'MATLAB:validators:mustBeNumeric'
    'inverse Yb text', @()ColorAtlasScience.inverseCAM('cam16',sp,w,'Yb','2'), 'MATLAB:validators:mustBeNumeric'
    'inverse Yw text', @()ColorAtlasScience.inverseCAM('cam16',sp,w,'Yw','2'), 'MATLAB:validators:mustBeNumeric'
    'inverse D text', @()ColorAtlasScience.inverseCAM('cam16',sp,w,'D','1'), 'MATLAB:validators:mustBeNumeric'
    'white brightness white text', @()ColorAtlasScience.whiteBrightness('cam16','abc'), 'MATLAB:validators:mustBeNumeric'
    'white brightness La text', @()ColorAtlasScience.whiteBrightness('cam16',w,'La','2'), 'MATLAB:validators:mustBeNumeric'
    'preview XYZ text', @()ColorAtlasScience.previewCells('abc','srgb','d65'), 'MATLAB:validators:mustBeNumeric'
    'projection XYZ text', @()ColorAtlasScience.simulateDichromat('tritan','abc',w), 'MATLAB:validators:mustBeNumeric'
    'projection white text', @()ColorAtlasScience.simulateDichromat('tritan',[.2 .3 .1],'abc'), 'MATLAB:validators:mustBeNumeric'
    'background text', @()ColorAtlasScience.backgroundXYZ('cam','d65','2'), 'MATLAB:validators:mustBeNumeric'
    'CIELAB L text', @()ColorAtlasScience.cielabToXYZ('50',30,120,'d65'), 'ColorAtlas:appearance'
    'CIELAB matrix', @()ColorAtlasScience.cielabToXYZ([40 50;60 70],30,120,'d65'), 'ColorAtlas:appearance'
    'legacy white text', @()ColorAtlasScience.inverse_CAM16(sp,'abc'), 'MATLAB:validators:mustBeNumeric'
    'legacy La text', @()ColorAtlasScience.inverse_CAM16(sp,w,'adaptingLuminance','2'), 'MATLAB:validators:mustBeNumeric'
    'legacy Lw text', @()ColorAtlasScience.inverse_CAM16(sp,w,'whiteLuminance','2'), 'MATLAB:validators:mustBeNumeric'
    'legacy Yb text', @()ColorAtlasScience.inverse_CAM16(sp,w,'relativeBackgroundLuminance','2'), 'MATLAB:validators:mustBeNumeric'
    'legacy Yw text', @()ColorAtlasScience.inverse_CAM16(sp,w,'relativeReferenceWhite','2'), 'MATLAB:validators:mustBeNumeric'
    'legacy D text', @()ColorAtlasScience.inverse_CAM16(sp,w,'D','1'), 'MATLAB:validators:mustBeNumeric'
    };
for k=1:size(direct,1),rejected(direct{k,1},direct{k,2},direct{k,3});end
xyz = ColorAtlasScience.cielabToXYZ(uint8([40 50]),uint8(30),int16(120),'d65');
ref = lab2xyz([40 30*cosd(120) 30*sind(120);50 30*cosd(120) 30*sind(120)],'WhitePoint','d65');
record('CIELAB numeric classes preserve vector values',max(abs(xyz-ref),[],'all')<1e-12,"");

app = ColorAtlas();
cleanup = onCleanup(@()delete(app)); %#ok<NASGU>
app.UIFigure.Visible='off';
app.selectCell(12);
before=app.snapshot();
controls=controlValues(app);
fields={'model','plane','space','white','vision','surround','laMode','dMode'};
for k=1:numel(fields)
    f=fields{k};
    bad={repmat(app.State.(f),1,2),repmat(char(app.State.(f)),2,1),string(missing),42};
    for j=1:numel(bad)
        changes=struct('La',30); changes.(f)=bad{j};
        rejected("state rejects nonscalar/nontext "+f+" / "+j,@()app.setState(changes),"ColorAtlas:state");
        record("state transaction preserved "+f+" / "+j, ...
            isequaln(before,app.snapshot()) && isequaln(controls,controlValues(app)),"");
    end
end
badChanges={struct('space','prophoto-rgb','La',NaN), ...
    struct('model','cielab','constant',[40 50]), ...
    struct('model','cam16','plane','invalid','La',30), ...
    struct('La',30,'unknown',1)};
badChangeErrors=["MATLAB:expectedFinite","MATLAB:expectedScalar","ColorAtlas:plane","ColorAtlas:state"];
for k=1:numel(badChanges)
    rejected("state rejects invalid multifield change / "+k,@()app.setState(badChanges{k}),badChangeErrors(k));
    record("multifield rejection preserves snapshot / "+k, ...
        isequaln(before,app.snapshot()) && isequaln(controls,controlValues(app)),"");
end
rejected('planeSpecs rejects model array',@()app.planeSpecs(["cielab" "cam16"]),"ColorAtlas:state");
rejected('selection rejects text index',@()app.selectCell('1'),"ColorAtlas:selection");
rejected('hit test rejects text coordinate',@()app.hitTest('1',0),"ColorAtlas:coordinates");
record('nonfinite hit still returns gap',app.hitTest(NaN,0)==0,"");

% Confirm successful transactions still reconcile model/plane and render.
app.setState(struct('model','cielab','space','prophoto-rgb','constant',50));
record('valid mixed character state commits and renders',app.State.model=="cielab" && ...
    app.State.plane=="h-C-L" && app.State.space=="prophoto-rgb" && ...
    app.State.constant==50 && isequaln(app.Atlas.state,app.State),"");
app.setState(struct('model',"cam16",'plane',"J-h-C",'La',30,'constant',50));
record('valid scalar string state commits and renders',app.State.model=="cam16" && ...
    app.State.plane=="J-h-C" && app.Atlas.La==30 && app.State.constant==50 && ...
    isequaln(app.Atlas.state,app.State),"");
sources=source_record(root,sourcePaths,sources);
report=struct('version',ColorAtlasScience.version(),'matlab',version, ...
    'runUTC',char(datetime('now','TimeZone','UTC')),'sources',sources, ...
    'checks',numel(rows),'failures',sum(~[rows.passed]),'results',rows);
fprintf('Public-input checks: %d; failures: %d\n',report.checks,report.failures);
if report.failures>0,disp(string({rows(~[rows.passed]).name})');end
assert(report.failures==0,'ColorAtlas:inputRegression','Public-input regression failed.');

    function rejected(name,call,expectedIdentifier)
        id="";
        try,call();catch e,id=string(e.identifier);end
        record(name,id==string(expectedIdentifier),"expected "+expectedIdentifier+"; actual "+id);
    end
    function record(name,passed,detail)
        rows(end+1)=struct('name',char(name),'passed',logical(passed),'detail',char(detail));
    end
end

function values=controlValues(app)
values={app.ModelDropDown.Value,app.PlaneDropDown.Value,app.SpaceDropDown.Value, ...
    app.WhiteDropDown.Value,app.VisionDropDown.Value,app.SurroundDropDown.Value, ...
    app.LaModeDropDown.Value,app.LaSpinner.Value,app.LwSpinner.Value,app.YbSpinner.Value, ...
    app.DModeDropDown.Value,app.DSpinner.Value,app.BackgroundSpinner.Value, ...
    app.ConstantSpinner.Value,app.ConstantSlider.Value,app.SelectionLabel.Text};
end
