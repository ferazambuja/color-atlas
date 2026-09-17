"""Exact dependency records for the supplied standalone tests."""
from pathlib import Path
import hashlib

RUNTIME_PATHS = frozenset(['VERSION', 'app/ColorAtlas.m', 'app/ColorAtlasHelp.html', 'app/ColorAtlasScience.m', 'app/ColorAtlas_v1_2.m', 'launch_color_atlas.m'])
RUN_PATHS = {'inverse': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/fixtures/inverse-a.json', 'tests/fixtures/inverse-b.json', 'tests/fixtures/manual-d.json', 'tests/public/hash_file.m', 'tests/public/inverse_adapter.m', 'tests/public/run_inverse.m', 'tests/public/source_record.m']), 'cvd': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/fixtures/cvd.json', 'tests/public/cvd_adapter.m', 'tests/public/hash_file.m', 'tests/public/run_cvd.m', 'tests/public/source_record.m']), 'domain': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/public/hash_file.m', 'tests/public/run_domains.m', 'tests/public/source_record.m']), 'preview': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/public/hash_file.m', 'tests/public/run_preview.m', 'tests/public/source_record.m']), 'ui': frozenset(['VERSION', 'app/ColorAtlas.m', 'app/ColorAtlasHelp.html', 'app/ColorAtlasScience.m', 'tests/public/hash_file.m', 'tests/public/run_ui.m', 'tests/public/source_record.m']), 'input': frozenset(['VERSION', 'app/ColorAtlas.m', 'app/ColorAtlasScience.m', 'tests/public/hash_file.m', 'tests/public/run_input_contract.m', 'tests/public/source_record.m']), 'launch': frozenset(['VERSION', 'app/ColorAtlas.m', 'app/ColorAtlasHelp.html', 'app/ColorAtlasScience.m', 'app/ColorAtlas_v1_2.m', 'launch_color_atlas.m', 'tests/public/hash_file.m', 'tests/public/run_launch.m', 'tests/public/source_record.m'])}
COMPARE_PATHS = {'inverse': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/fixtures/inverse-a.json', 'tests/fixtures/inverse-b.json', 'tests/fixtures/manual-d.json', 'tests/public/compare_inverse.py', 'tests/public/hash_file.m', 'tests/public/inverse_adapter.m', 'tests/public/provenance.py', 'tests/public/run_inverse.m', 'tests/public/source_record.m', 'tests/requirements.txt', 'validation/results/inverse-results.json']), 'cvd': frozenset(['VERSION', 'app/ColorAtlasScience.m', 'tests/fixtures/cvd.json', 'tests/public/compare_cvd.py', 'tests/public/cvd_adapter.m', 'tests/public/hash_file.m', 'tests/public/provenance.py', 'tests/public/run_cvd.m', 'tests/public/source_record.m', 'tests/requirements.txt', 'validation/results/cvd-results.json'])}
SUITE_PATHS = frozenset(['VERSION', 'app/ColorAtlas.m', 'app/ColorAtlasHelp.html', 'app/ColorAtlasScience.m', 'app/ColorAtlas_v1_2.m', 'launch_color_atlas.m', 'tests/fixtures/cvd.json', 'tests/fixtures/inverse-a.json', 'tests/fixtures/inverse-b.json', 'tests/fixtures/manual-d.json', 'tests/public/cvd_adapter.m', 'tests/public/hash_file.m', 'tests/public/inverse_adapter.m', 'tests/public/run_all.m', 'tests/public/run_cvd.m', 'tests/public/run_domains.m', 'tests/public/run_input_contract.m', 'tests/public/run_inverse.m', 'tests/public/run_launch.m', 'tests/public/run_preview.m', 'tests/public/run_ui.m', 'tests/public/source_record.m'])
RESULT_PATHS = frozenset(['validation/results/cvd-results.json', 'validation/results/domain-results.json', 'validation/results/input-contract-results.json', 'validation/results/inverse-results.json', 'validation/results/launch-results.json', 'validation/results/preview-results.json', 'validation/results/ui-results.json'])

def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture_sources(root, paths):
    root = Path(root)
    names = list(paths)
    require(len(names) == len(set(names)), 'Duplicate dependency paths')
    require(all(isinstance(p, str) and p and not Path(p).is_absolute() and '..' not in Path(p).parts
                for p in names), 'Dependencies must be relative paths within the source root')
    return [dict(path=p, sha256=sha(root/p)) for p in sorted(names)]


def validate_sources(root, rows, expected, label='result'):
    expected = frozenset(expected)
    require(isinstance(rows, list) and len(rows) == len(expected), f'Incomplete {label} dependency set')
    require(all(isinstance(row, dict) for row in rows), f'Malformed {label} dependencies')
    names = [row.get('path') for row in rows]
    require(all(isinstance(name, str) for name in names) and len(set(names)) == len(names)
            and set(names) == expected, f'{label} dependencies must name each expected file exactly once')
    for row in rows:
        require(row.get('sha256') == sha(Path(root)/row['path']),
                f"Rerun {label}: stale dependency {row['path']}")
