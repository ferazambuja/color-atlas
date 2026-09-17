function run_inverse(inverse)
% Independent fixtures for the supplied inverse_adapter function handle.
% Only the maintained adapter file is accepted; anonymous, alternate and
% shadowed functions must not produce results attributed to the app source.
arguments
    inverse (1,1) function_handle
end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
adapter=functions(inverse);
expectedAdapter=fullfile(root,'tests/public/inverse_adapter.m');
assert(strcmp(adapter.type,'simple') && strcmp(adapter.function,'inverse_adapter') && ...
    isfield(adapter,'file') && isfile(adapter.file) && ...
    strcmp(char(java.io.File(adapter.file).getCanonicalPath()),char(java.io.File(expectedAdapter).getCanonicalPath())), ...
    'ColorAtlas:inverseAdapter','Use the supplied inverse_adapter function handle from this source tree.');
addpath(fullfile(root,'app'));
paths = { ...
    'VERSION'; ...
    'app/ColorAtlasScience.m'; ...
    'tests/public/hash_file.m'; ...
    'tests/public/inverse_adapter.m'; ...
    'tests/public/run_inverse.m'; ...
    'tests/public/source_record.m'; ...
    'tests/fixtures/inverse-b.json'; ...
    'tests/fixtures/inverse-a.json'; ...
    'tests/fixtures/manual-d.json'; ...
    };
sources = source_record(root, paths);
core=fullfile(root,'app','ColorAtlasScience.m'); sourceSHA256=hash_file(core);
out=fullfile(root,'validation','results'); if ~isfolder(out),mkdir(out);end
science=jsondecode(fileread(fullfile(root,'tests','fixtures','inverse-a.json')));
referenceB=jsondecode(fileread(fullfile(root,'tests','fixtures','inverse-b.json')));
manual=jsondecode(fileread(fullfile(root,'tests','fixtures','manual-d.json')));
branches={'JC','JM','Js','QC','QM','Qs'};
n=numel(science.cases)+6*numel(referenceB.cases)+numel(manual.cases);
results=repmat(struct('id','','XYZ',[],'error',''),n,1); k=0;
for i=1:numel(science.cases)
    c=science.cases(i); D=NaN;if c.forcedD,D=1;end
    k=k+1;results(k)=call(inverse,sprintf('referenceA:%d',c.id), ...
        strrep(c.model,'inverse_',''),c.appearance,c.white(:)',c.La,c.Yb,D,c.surround);
end
for i=1:numel(referenceB.cases)
    c=referenceB.cases(i);w=referenceB.whites.(c.white)(:)'*100;
    D=NaN;if isnumeric(c.D),D=c.D;end
    for bi=1:6
        branch=branches{bi};s=struct(branch(1),c.(branch(1)),branch(2),c.(branch(2)),'h',c.h);
        k=k+1;results(k)=call(inverse,sprintf('referenceB:%d:%s',c.id,branch), ...
            c.model,s,w,c.La,c.Yb,D,c.condition);
    end
end
for i=1:numel(manual.cases)
    c=manual.cases(i);k=k+1;
    results(k)=call(inverse,sprintf('manual:%d',c.id),c.model,c.appearance, ...
        c.white(:)',c.La,c.Yb,c.D,c.surround);
end
assert(k==n);
published=struct([]);k=0;
for i=1:numel(referenceB.published)
    c=referenceB.published(i);D=NaN;if isnumeric(c.D),D=c.D;end
    for bi=1:6
        branch=branches{bi};s=struct(branch(1),c.(branch(1)),branch(2),c.(branch(2)),'h',c.h);
        k=k+1;row=call(inverse,sprintf('published:%d:%s',c.id,branch), ...
            c.model,s,c.XYZw(:)',c.La,c.Yb,D,c.condition);
        row.expectedXYZ=c.XYZ(:)';row.source=c.source;
        if isempty(row.XYZ),row.maxError=NaN;else,row.maxError=max(abs(row.XYZ-row.expectedXYZ));end
        if k==1,published=row;else,published(k)=row;end
    end
end
assert(strcmp(sourceSHA256,hash_file(core)),'Core changed during numerical run.');
sources = source_record(root, paths, sources);
report=struct('sources',sources,'sourceSHA256',sourceSHA256,'matlab',version,'runUTC',char(datetime('now','TimeZone','UTC')), ...
    'inverseAdapter',func2str(inverse),'results',results,'published',published);
fid=fopen(fullfile(out,'inverse-results.json'),'w');fprintf(fid,'%s\n',jsonencode(report));fclose(fid);
fprintf('V2 independent inverse calls: %d; published examples: %d\n',n,numel(published));
end

function row=call(inverse,id,model,s,w,la,yb,D,surround)
row=struct('id',id,'XYZ',[],'error','');
try
    xyz=inverse(model,s,w,la,yb,D,surround);
    if ~isreal(xyz),row.error='Complex XYZ';else,row.XYZ=xyz(:)';end
catch err,row.error=[err.identifier ': ' err.message];end
end
