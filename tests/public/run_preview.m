function report = run_preview()
%RUN_PREVIEW Independent public-contract tests for Color Atlas 2 preview/controls.
% Run: matlab -batch "addpath('tests/public'); run_preview"
% See ../README.md for references, scope and tolerances.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'app'));
sourcePaths={'VERSION','app/ColorAtlasScience.m','tests/public/run_preview.m', ...
    'tests/public/source_record.m','tests/public/hash_file.m'};
sources=source_record(root,sourcePaths);
rows = struct('id', {}, 'passed', {}, 'maxError', {}, 'tolerance', {}, ...
    'actual', {}, 'expected', {});
spaces = ["srgb", "linear-rgb", "adobe-rgb-1998", "prophoto-rgb"];
whites = ["d65", "d50", "a"];

% The same physical XYZ must have one sRGB preview independent of the selected
% data encoding. A nonneutral example exposes wrong primaries as well as gamma.
xyz = [0.25 0.40 0.10; 0.20 0.15 0.30];
for w = whites
    expectedPreview = xyz2rgb(xyz, 'ColorSpace', 'srgb', 'WhitePoint', char(w));
    for space = spaces
        p = ColorAtlasScience.previewCells(xyz, space, w);
        prefix = "encoding/" + w + "/" + space;
        near(prefix + "/preview", p.rgbPreview, expectedPreview, 2e-12);
        near(prefix + "/selected", p.rgbSelected, ...
            xyz2rgb(xyz, 'ColorSpace', char(space), 'WhitePoint', char(w)), 2e-12);
        if space ~= "srgb"
            yes(prefix + "/distinct-encoding", max(abs(p.rgbSelected-p.rgbPreview), [], 'all') > 0.01);
        end
    end
end

% CIELAB L*=50 neutral: Y=((50+16)/116)^3, encoded sRGB is about .4663,
% not the linear .1842 value. Decoding the displayed result must recover L*=50.
y50 = (66/116)^3;
midgray = y50 * whitepoint('d65');
linear = ColorAtlasScience.previewCells(midgray, "linear-rgb", "d65");
near("gray50/linear-values", linear.rgbSelected, repmat(y50, 1, 3), 2e-6);
near("gray50/display-srgb", linear.rgbDisplay, repmat(1.055*y50^(1/2.4)-0.055, 1, 3), 2e-6);
labDisplay = rgb2lab(linear.rgbDisplay);
near("gray50/display-Lab", labDisplay, [50 0 0], 2e-4);
yes("gray50/not-dark-linear-preview", max(abs(linear.rgbDisplay-linear.rgbSelected)) > 0.25);

% Independent explicit Bradford matrix, separate from the app and MATLAB's
% internal adaptation function. Conversion after adaptation uses the D65 API.
B = [0.8951 0.2664 -0.1614; -0.7502 1.7135 0.0367; 0.0389 -0.0685 1.0296];
for w = ["d50", "a"]
    sourceWhite = whitepoint(char(w));
    targetWhite = whitepoint('d65');
    coneScale = (B*targetWhite') ./ (B*sourceWhite');
    adapted = (B \ (coneScale .* (B*xyz')))';
    expected = xyz2rgb(adapted, 'ColorSpace', 'srgb', 'WhitePoint', 'd65');
    for space = spaces
        p = ColorAtlasScience.previewCells(xyz, space, w);
        near("Bradford/" + w + "/" + space, p.rgbPreview, expected, 2e-12);
    end
    neutral = ColorAtlasScience.previewCells(sourceWhite*.2, "srgb", w);
    near("Bradford/" + w + "/neutral", neutral.rgbDisplay, ...
        repmat(1.055*.2^(1/2.4)-.055, 1, 3), 2e-6);
end

% Closed gamut boundaries include black and the selected white. 1e-6 is a
% declared encoded-RGB tolerance, not a physical color-measurement precision.
for w = whites
    for space = spaces
        p = ColorAtlasScience.previewCells([zeros(1,3); whitepoint(char(w))], space, w);
        labels("boundary/"+w+"/"+space, p.status, ["displayable"; "displayable"]);
        near("boundary/"+w+"/"+space+"/display", p.rgbDisplay, [0 0 0; 1 1 1], 2e-6);
    end
end

% Construct encoded sRGB boundary probes through the public primary matrix
% and the standard sRGB EOTF; do not feed out-of-range RGB into rgb2xyz.
tol = 1e-6;
encoded = [-tol/2 .5 .5; 1+tol/2 .5 .5; -2*tol .5 .5; 1+2*tol .5 .5];
decoded = encoded/12.92;
high = encoded > .04045;
decoded(high) = ((encoded(high)+.055)/1.055).^2.4;
primaryXYZ = rgb2xyz(eye(3), 'ColorSpace', 'linear-rgb');
p = ColorAtlasScience.previewCells(decoded*primaryXYZ, "srgb", "d65");
labels("boundary/tolerance", p.status, ["displayable"; "displayable"; ...
    "outside-selected-gamut"; "outside-selected-gamut"]);
near("boundary/raw-values-preserved", p.rgbSelected, encoded, 2e-12);
near("boundary/display-clamped-only-after-classification", p.rgbDisplay(1:2,:), ...
    [0 .5 .5; 1 .5 .5], 2e-12);
yes("boundary/outside-not-drawn", all(isnan(p.rgbDisplay(3:4,:)), 'all'));

% Wide-gamut green must remain classified in its selected space even while
% the fixed sRGB preview needs clipping. Nonfinite XYZ must never be drawn.
for space = ["adobe-rgb-1998", "prophoto-rgb"]
    wideGreen = rgb2xyz([0 1 0], 'ColorSpace', char(space), 'WhitePoint', 'd65');
    p = ColorAtlasScience.previewCells(wideGreen, space, "d65");
    labels("status/"+space+"/clipped", p.status, "clipped-preview");
    % Adobe's fractional gamma amplifies ~1e-16 linear matrix residuals at
    % zero to ~4e-8 encoded RGB; this remains below the declared 1e-6 gamut tolerance.
    near("status/"+space+"/selected-green", p.rgbSelected, [0 1 0], 1e-7);
    yes("status/"+space+"/raw-preview-outside", any(p.rgbPreview < 0 | p.rgbPreview > 1));
    near("status/"+space+"/clipped-display", p.rgbDisplay, max(0,min(1,p.rgbPreview)), 0);
    q = ColorAtlasScience.previewCells(wideGreen, "srgb", "d65");
    labels("status/"+space+"/outside-srgb", q.status, "outside-selected-gamut");
    yes("status/"+space+"/outside-hidden", all(isnan(q.rgbDisplay)));
end
invalid = ColorAtlasScience.previewCells([NaN 0 0; Inf 0 0; 0 -Inf 0], "srgb", "d65");
labels("status/nonfinite-model-invalid", invalid.status, repmat("model-invalid",3,1));
yes("status/nonfinite-hidden", all(isnan(invalid.rgbDisplay), 'all'));
[badXYZ, badStatus] = ColorAtlasScience.inverseCAM("cam16", struct('J',0,'C',40,'h',120), [95.047 100 108.883]);
labels("status/zero-J-positive-C", badStatus, "zero-lightness-chromatic");
p = ColorAtlasScience.previewCells(badXYZ/100, "srgb", "d65");
labels("status/invalid-inverse-to-preview", p.status, "model-invalid");

% Background luminance is Yb/Yw for CAM, while LAB exposes actual L*. Analytic
% CIELAB inverse-neutral equations cover both sides of the L*=8 transition.
for w = whites
    white = whitepoint(char(w));
    for ratio = [.05 .1 .2 .5 1]
        background = ColorAtlasScience.backgroundXYZ("cam",w,ratio);
        near("background/CAM/"+w+"/"+ratio, background, ratio*white, 2e-14);
        near("background/CAM-Y/"+w+"/"+ratio, background(2), ratio, 2e-14);
    end
    for L = [0 2 8 20 50 80 100]
        if L <= 8, expectedY = L*(27/24389); else, expectedY = ((L+16)/116)^3; end
        background = ColorAtlasScience.backgroundXYZ("lab",w,L);
        near("background/Lab/"+w+"/"+L, background, expectedY*white, 2e-14);
        near("background/Lab-roundtrip/"+w+"/"+L, xyz2lab(background,'WhitePoint',char(w)), [L 0 0], 2e-11);
    end
end

% These Qw constants were generated by independent Colour 0.4.7 forward
% models, not this inverse or its conditionParameters function. The fourth
% condition checks Yb/Yw=10/200, equivalent to Colour's Yb=5 with Ywhite=100.
models = ["ciecam02" "cam16" "hellwig2022" "hellwig2022cat02"];
whiteRows = [95.047 100 108.883; 96.422 100 82.521; 109.85 100 35.585; 95.047 100 108.883];
La = [20 .1 318.31 50]; Yb = [20 5 20 10]; Yw = [100 100 100 200];
surround = ["average" "dim" "dark" "average"]; F = [1 .9 .8 1];
qw = [170.9169489348575 81.4561537535265 398.3938230363231 265.5785181389187; ...
      170.92939721196294 81.43440952225694 398.07090157448977 265.5927724562818; ...
      91.92068876938342 49.516945680681594 176.18334480252167 104.14710040893885; ...
      91.91315034583516 49.532910488522184 176.33862516975435 104.14103941169792];
for m = 1:numel(models)
    model = models(m);
    for v = 1:4
        opts = {'La',La(v),'Yb',Yb(v),'Yw',Yw(v),'surround',surround(v)};
        actualQw = ColorAtlasScience.whiteBrightness(model,whiteRows(v,:),opts{:});
        near("Qw/"+model+"/"+v, actualQw, qw(m,v), 2e-10);
        [xyzJ,statusJ,info] = ColorAtlasScience.inverseCAM(model,struct('J',25,'C',20,'h',60),whiteRows(v,:),opts{:});
        expectedD = min(1,max(0,F(v)*(1-exp(-(La(v)+42)/92)/3.6)));
        near("automatic-D/"+model+"/"+v, info.D, expectedD, 2e-15);
        near("relative-background/"+model+"/"+v, info.n, Yb(v)/Yw(v), 2e-15);
        if m<=2, targetQ=qw(m,v)*.5;else,targetQ=qw(m,v)*.25;end
        [xyzQ,statusQ] = ColorAtlasScience.inverseCAM(model,struct('Q',targetQ,'C',20,'h',60),whiteRows(v,:),opts{:});
        labels("Q-sampling/"+model+"/"+v+"/J-valid",statusJ,"valid");
        labels("Q-sampling/"+model+"/"+v+"/Q-valid",statusQ,"valid");
        near("Q-sampling/"+model+"/"+v+"/XYZ",xyzQ,xyzJ,2e-10);
    end
    appearance = struct('J',60,'C',30,'h',80);
    [d0, s0, i0] = ColorAtlasScience.inverseCAM(model,appearance,whiteRows(3,:),'D',0);
    [d5, s5, i5] = ColorAtlasScience.inverseCAM(model,appearance,whiteRows(3,:),'D',.5);
    [d1, s1, i1] = ColorAtlasScience.inverseCAM(model,appearance,whiteRows(3,:),'D',1);
    labels("manual-D/"+model+"/valid",[s0;s5;s1],repmat("valid",3,1));
    near("manual-D/"+model+"/values",[i0.D i5.D i1.D],[0 .5 1],0);
    yes("manual-D/"+model+"/changes-XYZ",norm(d0-d1)>1e-3 && norm(d0-d5)>1e-3 && norm(d5-d1)>1e-3);
    [auto,~,info] = ColorAtlasScience.inverseCAM(model,appearance,whiteRows(3,:));
    [manual,~] = ColorAtlasScience.inverseCAM(model,appearance,whiteRows(3,:),'D',info.D);
    near("manual-D/"+model+"/matches-auto-value",manual,auto,2e-12);
end

sources=source_record(root,sourcePaths,sources);
sourceHash=hash_file(fullfile(root,'app','ColorAtlasScience.m'));
report = struct('matlab',version,'runUTC',char(datetime('now','TimeZone','UTC')), ...
    'sourceSHA256',sourceHash,'sources',sources,'scope','public core preview, background and viewing-condition contracts', ...
    'checkCount',numel(rows),'passed',all([rows.passed]),'failedCount',sum(~[rows.passed]),'checks',rows);
out = fullfile(root,'validation','results','preview-results.json');
if ~isfolder(fileparts(out)),mkdir(fileparts(out));end
fid = fopen(out,'w'); cleaner = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
fprintf('Preview/control science checks: %d passed, %d failed.\n',sum([rows.passed]),sum(~[rows.passed]));
if ~report.passed
    disp(string({rows(~[rows.passed]).id})');
end
assert(report.passed, 'ColorAtlas:previewTests', 'Preview/control checks failed; inspect validation/results/preview-results.json');

    function near(id,actual,expected,tolerance)
        err = max(abs(actual-expected),[],'all');
        push(id,all(isfinite(actual),'all') && isequal(size(actual),size(expected)) && err<=tolerance,err,tolerance,actual,expected);
    end
    function labels(id,actual,expected)
        push(id,isequal(string(actual),string(expected)),NaN,NaN,actual,expected);
    end
    function yes(id,passed)
        push(id,logical(passed),NaN,NaN,logical(passed),true);
    end
    function push(id,passed,err,tolerance,actual,expected)
        rows(end+1)=struct('id',char(id),'passed',logical(passed),'maxError',err, ...
            'tolerance',tolerance,'actual',actual,'expected',expected);
    end
end
