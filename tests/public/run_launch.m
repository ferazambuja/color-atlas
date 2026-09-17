function run_launch
% Launch from an unrelated folder; exercise the compatibility constructor.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(root); previous=pwd; restore=onCleanup(@()cd(previous)); %#ok<NASGU>
% These are the complete local runtime dependencies exercised by this check.
% Record them before constructing either app, then reject concurrent edits.
paths={'VERSION','launch_color_atlas.m','app/ColorAtlas.m', ...
    'app/ColorAtlasScience.m','app/ColorAtlas_v1_2.m','app/ColorAtlasHelp.html'};
sourcePaths=[paths {'tests/public/run_launch.m','tests/public/source_record.m','tests/public/hash_file.m'}];
sources=source_record(root,sourcePaths);
dependencies=struct('path',paths,'sha256',cell(size(paths)));
for k=1:numel(paths),dependencies(k).sha256=hash_file(fullfile(root,paths{k}));end
cd(tempdir); launchFolder=pwd;
app=launch_color_atlas(struct('model',"cam16"));
cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
assert(strcmp(pwd,launchFolder)); assert(app.State.model=="cam16");
assert(~isfile(fullfile(root,'app','m_camera.mat')));
app.showHelp(); assert(isvalid(app.HelpFigure));
html=findall(app.HelpFigure,'-isa','matlab.ui.control.HTML');
assert(isscalar(html) && strcmp(html.HTMLSource,fullfile(root,'app','ColorAtlasHelp.html')));
assert(isfile(html.HTMLSource) && strlength(string(fileread(html.HTMLSource)))>0);
delete(app);
legacy=ColorAtlas_v1_2; cleanLegacy=onCleanup(@()delete(legacy)); %#ok<NASGU>
assert(isa(legacy,'ColorAtlas')); assert(strcmp(pwd,launchFolder));
for k=1:numel(paths)
    assert(strcmp(dependencies(k).sha256,hash_file(fullfile(root,paths{k}))), ...
        'ColorAtlas:runtimeChanged','Runtime dependency changed during launch check: %s',paths{k});
end
sources=source_record(root,sourcePaths,sources);
r=struct('schemaVersion',2,'version',ColorAtlasScience.version(),'matlab',version, ...
    'runUTC',char(datetime('now','TimeZone','UTC')),'dependencies',dependencies,'sources',sources,'passed',true, ...
    'launchFromUnrelatedFolder',true,'cwdPreserved',true,'helpResourcesResolved',true, ...
    'cameraMatrixAbsent',true,'legacyConstructorDelegates',true);
out=fullfile(root,'validation','results');if ~isfolder(out),mkdir(out);end
fid=fopen(fullfile(out,'launch-results.json'),'w');
fprintf(fid,'%s\n',jsonencode(r,'PrettyPrint',true));fclose(fid);
end
