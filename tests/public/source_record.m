function records = source_record(root, paths, before)
%SOURCE_RECORD Capture exact test dependencies, or verify they stayed unchanged.
% records=source_record(root,paths) is called before any observations.
% source_record(root,paths,records) checks those inputs again before writing.
% Include this helper and hash_file.m in paths, plus VERSION, the runner,
% runtime code, adapters and every retained fixture consumed by the runner.
paths = cellstr(string(paths));
assert(numel(unique(paths)) == numel(paths),'ColorAtlas:dependencyRecord','Duplicate dependency paths.');
records = struct('path',paths(:),'sha256',cell(numel(paths),1));
for k = 1:numel(paths)
    p = paths{k};
    assert(~isempty(p) && ~startsWith(p,filesep) && ~any(strcmp(strsplit(p,'/'),'..')), ...
        'ColorAtlas:dependencyRecord','Dependencies must be relative paths within the source root.');
    records(k).sha256 = hash_file(fullfile(root,p));
end
if nargin == 3
    assert(isstruct(before) && numel(before)==numel(records) && ...
        isfield(before,'path') && isfield(before,'sha256'), ...
        'ColorAtlas:dependencyRecord','Malformed initial dependency record.');
    [oldPaths,oldOrder]=sort(string({before.path}));
    [newPaths,newOrder]=sort(string({records.path}));
    assert(isequal(oldPaths,newPaths) && ...
        isequal(string({before(oldOrder).sha256}),string({records(newOrder).sha256})), ...
        'ColorAtlas:dependenciesChanged','Test dependencies changed during execution; discard observations and rerun.');
    records = before;
end
end
