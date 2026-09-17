"""Complete numerical/software checks from one recorded MATLAB suite run."""
from pathlib import Path
import json
import math
import runpy

from provenance import (RUN_PATHS, COMPARE_PATHS, RUNTIME_PATHS, SUITE_PATHS,
                        RESULT_PATHS, capture_sources, validate_sources, require, sha)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'validation/results'

def read(name):
    return json.loads((OUT/name).read_text())

version=(ROOT/'VERSION').read_text().strip()
suite=read('suite-results.json')
require(suite.get('schemaVersion')==1 and suite.get('passed') is True and
        suite.get('version')==version, 'Missing or stale complete MATLAB suite record')
validate_sources(ROOT, suite.get('sources'), SUITE_PATHS, 'run_all')
validate_sources(ROOT, suite.get('outputs'), RESULT_PATHS, 'run_all observations')
# Comparators validate observation/fixture dependencies before computing a
# summary. They never relabel results from an earlier version or test revision.
for script in ['compare_inverse.py', 'compare_cvd.py']:
    runpy.run_path(str(Path(__file__).with_name(script)), run_name='__main__')

inverse=read('inverse-summary.json')
cvd=read('cvd-summary.json')
for key,summary in [('inverse',inverse),('cvd',cvd)]:
    validate_sources(ROOT, summary.get('sources'), COMPARE_PATHS[key], key+' comparison')
require(inverse['version']==cvd['version']==version, 'Numerical result version is stale')
require(inverse['total']==55512 and cvd['count']==6615, 'Incomplete numerical comparisons')
require(inverse['failed']==cvd['failed']==0 and not inverse['failures'] and not cvd['failures'],
        'Numerical comparisons failed')
require(sum(row['count'] for row in inverse['modelResults'].values())==55512 and
        all(row['failed']==0 and math.isfinite(row['maxErrorXYZ']) and row['maxErrorXYZ']<=1e-7
            for row in inverse['modelResults'].values()), 'Inverse errors exceed tolerance')
require(inverse['publishedExampleCount']==12 and math.isfinite(inverse['publishedMaxErrorXYZ']) and
        inverse['publishedMaxErrorXYZ']<=.005, 'Published examples failed')
require(math.isfinite(cvd['maxErrorXYZ']) and cvd['maxErrorXYZ']<=1e-9, 'CVD errors exceed tolerance')
for key, name, rows, count, minimum in [('domain','domain-results.json','results','checks',64),
    ('preview','preview-results.json','checks','checkCount',275),
    ('ui','ui-results.json','results','checks',107),
    ('input','input-contract-results.json','results','checks',198)]:
    result=read(name)
    validate_sources(ROOT, result.get('sources'), RUN_PATHS[key], key)
    require(isinstance(result.get(rows),list) and len(result[rows])==result[count]
            and result[count]>=minimum, name+': incomplete checks')
    require(all(isinstance(row,dict) and row.get('passed') is True for row in result[rows]), name+': failed check')
    failures='failedCount' if key=='preview' else 'failures'
    require(result.get(failures)==0, name+': failures recorded')
inputs=read('input-contract-results.json')
require(inputs.get('version')==version, 'Input-contract version is stale')
ui=read('ui-results.json')
require(len(ui['routes'])==39 and len({(r['model'],r['plane']) for r in ui['routes']})==39
        and all(row['passed'] is True for row in ui['routes']), 'Missing, duplicate or failed UI routes')
require({(r['width'],r['height']) for r in ui['dimensions']}=={(900,650),(1100,720),(1440,900)}
        and all(r['passed'] is True for r in ui['dimensions']), 'Missing or failed UI layouts')
launch=read('launch-results.json')
require(launch['schemaVersion']==2 and launch['version']==version, 'Stale launch record')
for key in ['passed','launchFromUnrelatedFolder','cwdPreserved','helpResourcesResolved','cameraMatrixAbsent','legacyConstructorDelegates']:
    require(launch[key] is True, 'Launch contract failed: '+key)
validate_sources(ROOT, launch.get('dependencies'), RUNTIME_PATHS, 'launch runtime')
validate_sources(ROOT, launch.get('sources'), RUN_PATHS['launch'], 'run_launch')
# Reject edits made during the comparison as well as stale inputs at entry.
validate_sources(ROOT, suite['sources'], SUITE_PATHS, 'run_all')
validate_sources(ROOT, suite['outputs'], RESULT_PATHS, 'run_all observations')
print('PASS: one complete MATLAB suite and numerical comparisons match current test inputs and source.')
