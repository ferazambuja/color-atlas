function run_cvd(simulate)
% Run independent fixtures through the supplied cvd_adapter function handle.
% Only the maintained adapter file is accepted; anonymous, alternate and
% shadowed functions must not produce results attributed to the app source.
arguments
    simulate (1,1) function_handle
end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
adapter=functions(simulate);
expectedAdapter=fullfile(root,'tests/public/cvd_adapter.m');
assert(strcmp(adapter.type,'simple') && strcmp(adapter.function,'cvd_adapter') && ...
    isfield(adapter,'file') && isfile(adapter.file) && ...
    strcmp(char(java.io.File(adapter.file).getCanonicalPath()),char(java.io.File(expectedAdapter).getCanonicalPath())), ...
    'ColorAtlas:cvdAdapter','Use the supplied cvd_adapter function handle from this source tree.');
addpath(fullfile(root,'app'));
paths = { ...
    'VERSION'; ...
    'app/ColorAtlasScience.m'; ...
    'tests/public/cvd_adapter.m'; ...
    'tests/public/hash_file.m'; ...
    'tests/public/run_cvd.m'; ...
    'tests/public/source_record.m'; ...
    'tests/fixtures/cvd.json'; ...
    };
sources = source_record(root, paths);
core=fullfile(root,'app','ColorAtlasScience.m'); sourceSHA256=hash_file(core);
out=fullfile(root,'validation','results');
f=jsondecode(fileread(fullfile(root,'tests','fixtures','cvd.json')));
rows=repmat(struct('id',0,'XYZ',[],'error',''),numel(f.cases),1);
for i=1:numel(f.cases)
    c=f.cases(i);rows(i).id=c.id;
    try
        y=simulate(c.mode,c.XYZ(:)',c.white(:)');
        if ~isreal(y),rows(i).error='Complex XYZ';else,rows(i).XYZ=y(:)';end
    catch err,rows(i).error=[err.identifier ': ' err.message];end
end
assert(strcmp(sourceSHA256,hash_file(core)),'Core changed during numerical run.');
sources = source_record(root, paths, sources);
r=struct('sources',sources,'sourceSHA256',sourceSHA256,'matlab',version,'adapter',func2str(simulate),'results',rows);
fid=fopen(fullfile(out,'cvd-results.json'),'w');fprintf(fid,'%s\n',jsonencode(r));fclose(fid);
fprintf('V2 CVD comparisons: %d\n',numel(rows));
end
