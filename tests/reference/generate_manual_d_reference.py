"""Additional independent Colour forward cases for explicit adaptation overrides.

Only Colour's degree-of-adaptation function is patched to a chosen scalar D;
none of its colour equations or any app implementation is copied/changed.
"""
from pathlib import Path
import json
import sys
import warnings
from unittest.mock import patch
warnings.filterwarnings('ignore',message='.*related API features are not available.*')
import colour
import numpy as np
from colour.appearance import ciecam02,cam16,hellwig2022
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/reference'))
from modified_cam02_reference import XYZ_to_modified_CAM02
models={'CAM02':(colour.XYZ_to_CIECAM02,ciecam02),
        'CAM16':(colour.XYZ_to_CAM16,cam16),
        'modCAM16':(colour.XYZ_to_Hellwig2022,hellwig2022),
        'modCAM02':(XYZ_to_modified_CAM02,ciecam02)}
assert colour.__version__=='0.4.7'
cases=[]
for model,(forward,module) in models.items():
 for w in [np.array([95.047,100.,108.883]),np.array([109.85,100.,35.58])]:
  for d in [0.,.25,.5,.75,1.]:
   for xyz in [w*.2,np.array([19.01,20.,21.78]),np.array([40.,30.,20.])]:
    with patch.object(module,'degree_of_adaptation',lambda *args,value=d: value):
     spec=forward(xyz,w,20.,20.,colour.VIEWING_CONDITIONS_CAM16['Average'],False)
    for tone in ['J','Q']:
     for chroma in ['C','M','s']:
      appearance={k:float(getattr(spec,k)) for k in [tone,chroma,'h']}
      assert all(np.isfinite(list(appearance.values())))
      cases.append(dict(id=len(cases),model=model,white=w.tolist(),La=20.,Yb=20.,D=d,
        surround='average',appearance=appearance,expectedXYZ=xyz.tolist()))
metadata=dict(colour=colour.__version__,count=len(cases),toleranceXYZ=1e-7,
  method='Independent Colour forward with scalar D override via patching degree_of_adaptation only')
p=ROOT/'tests/fixtures/manual-d.json';p.parent.mkdir(exist_ok=True,parents=True)
p.write_text(json.dumps(dict(metadata=metadata,cases=cases),separators=(',',':'))+'\n')
print(json.dumps(metadata))
