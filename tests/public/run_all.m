function run_all
% Run the supplied MATLAB checks and record this complete suite invocation.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'tests','public'));
paths={'VERSION','app/ColorAtlas.m','app/ColorAtlasHelp.html','app/ColorAtlasScience.m','app/ColorAtlas_v1_2.m','launch_color_atlas.m','tests/fixtures/cvd.json','tests/fixtures/inverse-a.json','tests/fixtures/inverse-b.json','tests/fixtures/manual-d.json','tests/public/cvd_adapter.m','tests/public/hash_file.m','tests/public/inverse_adapter.m','tests/public/run_all.m','tests/public/run_cvd.m','tests/public/run_domains.m','tests/public/run_input_contract.m','tests/public/run_inverse.m','tests/public/run_launch.m','tests/public/run_preview.m','tests/public/run_ui.m','tests/public/source_record.m'};
sources=source_record(root,paths);
run_inverse(@inverse_adapter);
run_cvd(@cvd_adapter);
run_domains;
run_preview;
run_ui;
run_launch;
report=run_input_contract;
file=fullfile(root,'validation','results','input-contract-results.json');
fid=fopen(file,'w');assert(fid>=0);fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));fclose(fid);
source_record(root,paths,sources);
outputs=source_record(root,{'validation/results/cvd-results.json','validation/results/domain-results.json','validation/results/input-contract-results.json','validation/results/inverse-results.json','validation/results/launch-results.json','validation/results/preview-results.json','validation/results/ui-results.json'});
report=struct('schemaVersion',1,'version',ColorAtlasScience.version(),'passed',true, ...
    'runUTC',char(datetime('now','TimeZone','UTC')),'sources',sources,'outputs',outputs);
file=fullfile(root,'validation','results','suite-results.json');
fid=fopen(file,'w');assert(fid>=0);cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
fprintf('MATLAB observations complete. Run tests/public/compare_all.py next.\n');
end
