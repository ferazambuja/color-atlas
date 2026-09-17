"""Pinned Colour forward cases for independent testing of the app inverses."""
from pathlib import Path
import hashlib
import itertools
import json
import warnings

warnings.filterwarnings("ignore", message='.*related API features are not available.*')
import colour
import numpy as np
from modified_cam02_reference import XYZ_to_modified_CAM02

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tests/fixtures'
OUT.mkdir(parents=True, exist_ok=True)
assert colour.__version__ == '0.4.7'
models = {
    'inverse_CAM02': colour.XYZ_to_CIECAM02,
    'inverse_CAM16': colour.XYZ_to_CAM16,
    'inverse_modCAM16': colour.XYZ_to_Hellwig2022,
    'inverse_modCAM02': XYZ_to_modified_CAM02,
}
whites = {'D65': [95.047, 100, 108.883], 'D50': [96.422, 100, 82.521],
          'A': [109.85, 100, 35.585]}
cases = []
for model, forward in models.items():
    for white_name, surround_name, la, yb, forced in itertools.product(
            whites, ['Average', 'Dim', 'Dark'], [0.1, 20, 318.31], [5, 20], [False, True]):
        white = np.array(whites[white_name])
        samples = [[19.01, 20, 21.78], 0.001*white, .2*white, .9*white,
                   [41.24, 21.26, 1.93], [35.76, 71.52, 11.92],
                   [18.05, 7.22, 95.05], [10, 15, 35]]
        for sample_i, xyz in enumerate(samples):
            spec = forward(xyz, white, la, yb,
                surround=colour.VIEWING_CONDITIONS_CIECAM02[surround_name],
                discount_illuminant=forced)
            correlates = {k: float(getattr(spec, k)) for k in ['J','Q','C','M','s','h']}
            assert all(np.isfinite(list(correlates.values())))
            for tone, chroma in itertools.product(['J','Q'], ['C','M','s']):
                cases.append(dict(id=len(cases)+1, model=model,
                    branch=tone+chroma+'h', whiteName=white_name,
                    white=white.tolist(), La=la, Yb=yb, Yw=100,
                    surround=surround_name.lower(), forcedD=forced,
                    sample=sample_i, appearance={k:correlates[k] for k in [tone,chroma,'h']},
                    expectedXYZ=np.asarray(xyz).tolist()))
metadata = dict(colour=colour.__version__, numpy=np.__version__,
    method='Colour forward correlates -> exact app inverse -> original XYZ',
    modifiedCAM02Reference='Composed Colour CAT02/HPE front end plus Hellwig2022 correlates; not a stock named Colour model',
    caseCount=len(cases), toleranceXYZ=1e-7,
    source='https://github.com/colour-science/colour/tree/v0.4.7/colour/appearance')
(OUT/'inverse-a.json').write_text(json.dumps(dict(metadata=metadata,cases=cases),separators=(',',':'))+'\n')
print(json.dumps(metadata,indent=2))
