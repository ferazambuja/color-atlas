"""Fail-closed comparison of maintained inverse output with independent fixtures."""
from pathlib import Path
from collections import defaultdict
import hashlib
import json
import numpy as np
from provenance import RUN_PATHS, COMPARE_PATHS, capture_sources, validate_sources

ROOT = Path(__file__).resolve().parents[2]
BRANCHES = ('JC', 'JM', 'Js', 'QC', 'QM', 'Qs')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def xyz_array(value, label):
    actual = np.asarray(value, dtype=float)
    require(actual.shape == (3,) and np.all(np.isfinite(actual)), f'{label}: expected finite XYZ row')
    return actual


def compare(root=ROOT):
    out = root / 'validation/results'
    sources = capture_sources(root, COMPARE_PATHS['inverse'])
    run = json.loads((out / 'inverse-results.json').read_text())
    validate_sources(root, run.get('sources'), RUN_PATHS['inverse'], 'run_inverse')
    core = hashlib.sha256((root / 'app/ColorAtlasScience.m').read_bytes()).hexdigest()
    require(run.get('sourceSHA256') == core, 'Core changed since MATLAB run')
    refs = json.loads((root/'tests/fixtures/inverse-a.json').read_text())
    other = json.loads((root/'tests/fixtures/inverse-b.json').read_text())
    manual = json.loads((root/'tests/fixtures/manual-d.json').read_text())
    expected = {}

    def expect(key, model, branch, xyz):
        require(key not in expected, f'Duplicate reference ID: {key}')
        expected[key] = (model, branch, xyz_array(xyz, key))

    for c in refs['cases']:
        expect(f"referenceA:{c['id']}", c['model'].replace('inverse_', ''), c['branch'], c['expectedXYZ'])
    for c in other['cases']:
        for branch in BRANCHES:
            expect(f"referenceB:{c['id']}:{branch}", c['model'], branch+'h', c['XYZ'])
    for c in manual['cases']:
        expect(f"manual:{c['id']}", c['model'], ''.join(c['appearance']), c['expectedXYZ'])
    require(len(expected) == 55512 and len(run['results']) == len(expected), 'Incomplete inverse comparison rows')
    seen = set(); groups = defaultdict(list)
    for row in run['results']:
        key = row['id']
        require(key in expected and key not in seen, f'Missing, duplicate or unexpected inverse ID: {key}')
        seen.add(key)
        model, branch, xyz = expected[key]
        actual = xyz_array(row['XYZ'], key)
        error = float(np.max(abs(actual-xyz)))
        require(row.get('error') == '' and error <= 1e-7, f'Inverse comparison failed: {key}, error {error}')
        groups[model].append(error)
    require(seen == set(expected), 'Missing inverse IDs')

    # Recompute the published-example errors from XYZ and the independent fixture.
    # Check both the computed error and the reported error field.
    published_expected = {f"published:{c['id']}:{branch}": xyz_array(c['XYZ'], 'published reference')
                          for c in other['published'] for branch in BRANCHES}
    published = run['published']
    require(len(published_expected) == len(published) == 12, 'Incomplete published examples')
    published_seen = set(); published_errors = []
    for row in published:
        key = row['id']
        require(key in published_expected and key not in published_seen, f'Unexpected published ID: {key}')
        published_seen.add(key)
        error = float(np.max(abs(xyz_array(row['XYZ'], key)-published_expected[key])))
        require(row.get('error') == '' and error <= .005, f'Published example failed: {key}')
        require(np.array_equal(xyz_array(row['expectedXYZ'], key), published_expected[key]), f'Published expectation changed: {key}')
        require(isinstance(row.get('maxError'), (int, float)) and np.isfinite(row['maxError']) and
                abs(row['maxError']-error) <= 1e-12, f'Inconsistent published error: {key}')
        published_errors.append(error)
    require(published_seen == set(published_expected), 'Missing published IDs')
    summary = dict(publishedExampleCount=12, publishedToleranceXYZ=.005,
        publishedMaxErrorXYZ=max(published_errors), version=(root/'VERSION').read_text().strip(), matlab=run['matlab'],
        toleranceXYZ=1e-7, total=len(seen), failed=0, failures=[],
        modelResults={m:dict(count=len(v), maxErrorXYZ=max(v), failed=0) for m,v in groups.items()},
        referenceFiles={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in
          [root/'tests/fixtures/inverse-a.json',root/'tests/fixtures/inverse-b.json',root/'tests/fixtures/manual-d.json']},
        sourceFiles={'app/ColorAtlasScience.m':core}, sources=sources,
        note='Sampled numerical branch comparisons; modified CAM02 uses composed forward references, not a stock standardized model.')
    validate_sources(root, sources, COMPARE_PATHS['inverse'], 'inverse comparison')
    return summary


if __name__ == '__main__':
    summary = compare()
    (ROOT/'validation/results/inverse-summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False)+'\n')
    print(json.dumps({k:summary[k] for k in ('version','total','failed','modelResults')}, indent=2))
