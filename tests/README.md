# Tests

The suite checks the color models, RGB previews and native MATLAB interface.
MATLAB computes the results; Python compares the inverse-model and vision
projection outputs with independent reference data.

## Run the suite

Tested with MATLAB R2026a Update 5 and Image Processing Toolbox on macOS.
Run from the source root, with MATLAB available as `matlab` in your shell:

```sh
matlab -batch "addpath('tests/public'); run_all"
python3 -m venv .venv-validation
.venv-validation/bin/python -m pip install -r tests/requirements.txt
.venv-validation/bin/python tests/public/compare_all.py
```

The expected values are included in `tests/fixtures/`. A normal test run reads
these files and writes its results to `validation/results/`. Both the MATLAB
run and the Python comparison must succeed. The comparison also checks UI,
launch and input-validation results, and confirms they describe the current
source files. Run results record the exact runner, helpers, fixture bytes and
VERSION before and after execution. The complete MATLAB run also records its
output files; changed tests or inputs require rerunning the affected suite.

Python is needed only for tests. The reference environment uses Python 3.12,
Colour 0.4.7 and NumPy 2.5.3; pins are in `tests/requirements.txt`.

## Coverage

| Check | Coverage and tolerance |
|---|---|
| Inverse models | 55,512 calls, four formulations and all six J/Q × C/M/s branches; absolute XYZ error <= 1e-7 at white Y=100 |
| Published examples | Twelve branches from two rounded examples; absolute XYZ error <= .005 |
| CVD geometry | 6,615 projections, both wings, neutrals, anchors, scaling and idempotence; absolute XYZ error <= 1e-9 |
| Domain and input handling | Invalid correlates, response singularities, nonfinite arithmetic, malformed types and rejected UI-state changes |
| Preview | Selected-space membership separated from sRGB encoding, gamut boundaries, backgrounds, adaptation and Q-white sampling |
| UI | All 39 model/plane routes, native callbacks, cell geometry, three window sizes and owned-window lifetime |

## Reference data

The inverse-model fixtures start with known XYZ values. The scripts in
`tests/reference/` calculate their appearance coordinates using Colour's
forward models and independently composed CAT02/HPE plus Hellwig correlates.
The app's inverse functions must then recover the original XYZ values. The
manual-D fixture tests explicit adaptation values through the same process.

The CVD reference calculation independently solves the projection planes in
the HPE cone basis. Its inputs cover both planes, spectral anchors, neutral
colors and scaling. Fixture metadata records model conditions, dependency
versions and scientific references.

To regenerate the four fixtures deliberately, run these commands in the same
pinned Python environment, then rerun both MATLAB and Python comparisons:

```sh
.venv-validation/bin/python tests/reference/generate_inverse_a.py
.venv-validation/bin/python tests/reference/generate_inverse_b.py
.venv-validation/bin/python tests/reference/generate_manual_d_reference.py
.venv-validation/bin/python tests/reference/generate_cvd_reference.py
```

Regeneration replaces the corresponding JSON files in `tests/fixtures/`.
Review changes to both the numerical cases and their metadata before using
new expected values.

The results describe numerical agreement and software behavior. Display
measurements and observer studies are separate forms of validation.
