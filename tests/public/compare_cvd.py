"""Compare maintained CVD output with independently constructed plane fixtures."""
from pathlib import Path
import hashlib
import json
import numpy as np
from provenance import RUN_PATHS, COMPARE_PATHS, capture_sources, validate_sources

ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def compare(root=ROOT):
    out = root/'validation/results'
    sources = capture_sources(root, COMPARE_PATHS['cvd'])
    ref = json.loads((root/'tests/fixtures/cvd.json').read_text())
    run = json.loads((out/'cvd-results.json').read_text())
    validate_sources(root, run.get('sources'), RUN_PATHS['cvd'], 'run_cvd')
    core = hashlib.sha256((root/'app/ColorAtlasScience.m').read_bytes()).hexdigest()
    require(run.get('sourceSHA256') == core, 'Core changed since MATLAB run')
    require(len(ref['cases']) == len(run['results']) == 6615, 'Incomplete CVD comparison rows')
    seen = set(); worst = 0.; groups = {}
    for expected, row in zip(ref['cases'], run['results']):
        key = expected['id']
        require(key == row['id'] and key not in seen, 'Missing, duplicate or misaligned CVD IDs')
        seen.add(key)
        actual = np.asarray(row['XYZ'], dtype=float)
        xyz = np.asarray(expected['expectedXYZ'], dtype=float)
        require(actual.shape == xyz.shape == (3,) and np.isfinite(actual).all() and np.isfinite(xyz).all(),
                f'{key}: expected finite XYZ rows')
        error = float(np.max(abs(actual-xyz)))
        require(row.get('error') == '' and error <= 1e-9, f'CVD comparison failed: {key}, error {error}')
        worst = max(worst, error)
        key = expected['mode']; groups.setdefault(key, dict(count=0, maxErrorXYZ=0.))
        groups[key]['count'] += 1
        groups[key]['maxErrorXYZ'] = max(groups[key]['maxErrorXYZ'], error)
    summary = dict(version=(root/'VERSION').read_text().strip(), matlab=run['matlab'], count=len(seen),
        toleranceXYZ=1e-9, maxErrorXYZ=worst, failed=0, failures=[], groups=groups,
        model='Brettel-style HPE/selected-white approximation; not original Stockman/E observer parity',
        referenceSHA256=hashlib.sha256((root/'tests/fixtures/cvd.json').read_bytes()).hexdigest(),
        sourceFiles={'app/ColorAtlasScience.m':core}, sources=sources)
    validate_sources(root, sources, COMPARE_PATHS['cvd'], 'CVD comparison')
    return summary


if __name__ == '__main__':
    summary = compare()
    (ROOT/'validation/results/cvd-summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k:summary[k] for k in ('count','failed','maxErrorXYZ','groups')}, indent=2))
