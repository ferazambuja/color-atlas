function run_domains()
% Regression checks for numerical input types, domains and status results.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'app'));
sourcePaths={'VERSION','app/ColorAtlasScience.m','tests/public/run_domains.m', ...
    'tests/public/source_record.m','tests/public/hash_file.m'};
sources=source_record(root,sourcePaths);
out = fullfile(root, 'validation','results');
if ~isfolder(out), mkdir(out); end
rows = struct('name', {}, 'passed', {}, 'status', {}, 'errorIdentifier', {}, 'XYZ', {});
w = [95.047 100 108.883];
sp = struct('J', 50, 'C', 30, 'h', 120);
models = ColorAtlasScience.MODELS;
for model = models
    errors = {
        'complex J', @() ColorAtlasScience.inverseCAM(model, struct('J',50+1i,'C',30,'h',120), w), 'ColorAtlas:complexAppearance'
        'complex C', @() ColorAtlasScience.inverseCAM(model, struct('J',50,'C',30+1i,'h',120), w), 'ColorAtlas:complexAppearance'
        'complex h', @() ColorAtlasScience.inverseCAM(model, struct('J',50,'C',30,'h',120+1i), w), 'ColorAtlas:complexAppearance'
        'D positive Inf', @() ColorAtlasScience.inverseCAM(model, sp, w, 'D', Inf), 'ColorAtlas:invalidAdaptation'
        'D negative Inf', @() ColorAtlasScience.inverseCAM(model, sp, w, 'D', -Inf), 'ColorAtlas:invalidAdaptation'
        'overflow Yb/Yw', @() ColorAtlasScience.inverseCAM(model, sp, w, 'Yw', realmin*.01), 'ColorAtlas:invalidViewingCondition'
        'subnormal La', @() ColorAtlasScience.inverseCAM(model, sp, w, 'La', realmin*eps), 'ColorAtlas:invalidViewingCondition'
        'overflow La', @() ColorAtlasScience.inverseCAM(model, sp, w, 'La', realmax), 'ColorAtlas:invalidViewingCondition'
        'overflow white normalization', @() ColorAtlasScience.inverseCAM(model, sp, [1 realmin*.01 1]), 'ColorAtlas:invalidViewingCondition'
        'whiteBrightness invalid conditions', @() ColorAtlasScience.whiteBrightness(model, w, 'Yw', realmin*.01), 'ColorAtlas:invalidViewingCondition'
        };
    for i = 1:size(errors, 1)
        id = '';
        try, errors{i, 2}(); catch e, id = e.identifier; end
        record(model + ": " + errors{i,1}, strcmp(id, errors{i,3}), "", id, []);
    end

    % Preserve finite low-luminance exploration; no arbitrary 0.1 cd/m2 floor.
    [xyz, st, p] = ColorAtlasScience.inverseCAM(model, sp, w, 'La', 1e-6);
    record(model + ": finite low La", st == "valid" && isreal(xyz) && all(isfinite(xyz)), st, '', xyz);
    [xyz, st, p] = ColorAtlasScience.inverseCAM(model, sp, w, 'D', NaN);
    expectedD = 1 - exp((-20-42)/92)/3.6;
    record(model + ": automatic D preserved", st == "valid" && abs(p.D-expectedD) < 1e-14, st, '', xyz);

    % A bad row must not contaminate valid neighbors, including exact black.
    batch = struct('J', [50;0;NaN;-1], 'C', [30;0;30;30], 'h', 120);
    [xyz, st] = ColorAtlasScience.inverseCAM(model, batch, w);
    ok = all(st(1:2) == "valid") && all(isfinite(xyz(1:2,:)), 'all') && ...
        isequal(xyz(2,:), [0 0 0]) && all(st(3:4) ~= "valid") && all(isnan(xyz(3:4,:)), 'all');
    record(model + ": row isolation and black", ok, join(st, ','), '', xyz);

    % Scaling can overflow after valid response inversion; exercise the final guard.
    [xyz, st] = ColorAtlasScience.inverseCAM(model, struct('J',10000,'C',0,'h',120), w*1e305, 'D', 1);
    record(model + ": final overflow is nonfinite", st == "not-finite" && all(isnan(xyz)), st, '', xyz);

    if startsWith(model, "hellwig")
        [xyz, st] = ColorAtlasScience.inverseCAM(model, struct('J',0,'M',40,'h',120), w, 'D', 1);
        record(model + ": signed zero-J preimage preserved", ...
            st == "valid" && isreal(xyz) && all(isfinite(xyz)) && any(xyz < 0), st, '', xyz);
    end
end

% Direct entry points also reject complex XYZ instead of calling it a real stimulus.
direct = {
    'preview complex XYZ', @() ColorAtlasScience.previewCells([.2 .3+.1i .1], "srgb", "d65"), 'MATLAB:validators:mustBeReal'
    'CVD complex XYZ', @() ColorAtlasScience.simulateDichromat("tritan", [.2 .3+.1i .1], w), 'MATLAB:validators:mustBeReal'
    'CIELAB complex C', @() ColorAtlasScience.cielabToXYZ(50,30+1i,120,'d65'), 'ColorAtlas:complexAppearance'
    };
for i = 1:size(direct,1)
    id = '';
    try, direct{i,2}(); catch e, id = e.identifier; end
    record(direct{i,1}, strcmp(id,direct{i,3}), "", id, []);
end

% The anchor itself should lie in the tritan projection plane in the declared HPE basis.
anchor = [5.795001 16.93 61.62];
[xyz, wing] = ColorAtlasScience.simulateDichromat("tritan", anchor, w);
record('CIE 485 nm precision and invariance', wing == 485 && max(abs(xyz-anchor)) < 1e-10, "", '', xyz);
id = '';
try, ColorAtlasScience.simulateDichromat("tritan", [.2 .3 .1], anchor); catch e, id = e.identifier; end
record('degenerate CVD projection white', strcmp(id, 'ColorAtlas:invalidDichromatWhite'), "", id, []);

% Check the CAM16 low-J numerical reference.
[xyz, st] = ColorAtlasScience.inverseCAM("cam16", struct('J',1,'C',1,'h',120), w, 'D', 1);
expected = [.02269325068 .02484824872 .02239575646];
record('CAM16 low-J reference', st == "valid" && max(abs(xyz-expected)) < 1e-10, st, '', xyz);

sources=source_record(root,sourcePaths,sources);
sha=hash_file(fullfile(root,'app','ColorAtlasScience.m'));
report = struct('matlab', version, 'runUTC', char(datetime('now','TimeZone','UTC')), ...
    'sourceSHA256', sha, 'sources',sources,'checks', numel(rows), 'failures', sum(~[rows.passed]), 'results', rows);
fid = fopen(fullfile(out, 'domain-results.json'), 'w');
fprintf(fid, '%s\n', jsonencode(report, 'PrettyPrint', true)); fclose(fid);
fprintf('V2 numerical domain checks: %d; failures: %d\n', numel(rows), report.failures);
if report.failures > 0, disp(string({rows(~[rows.passed]).name})'); end
assert(report.failures == 0, 'ColorAtlas:domainRegression', 'Numerical domain regression failed.');

    function record(name, passed, status, errorIdentifier, XYZ)
        rows(end+1) = struct('name', char(name), 'passed', logical(passed), ...
            'status', char(status), 'errorIdentifier', errorIdentifier, 'XYZ', XYZ);
    end
end
