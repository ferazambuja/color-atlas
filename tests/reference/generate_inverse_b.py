#!/usr/bin/env python3
"""Independent forward-model reference cases for the Color Atlas inverses.

Writes tests/fixtures/inverse-b.json. Every case starts from a
known XYZ, computes the forward appearance correlates with an implementation
that shares no code with the app, and asks the MATLAB probe to reconstruct XYZ
through every input branch (J/Q x C/M/s). Sources:

- CIECAM02, CAM16, Hellwig&Fairchild 2022 (CAM16 basis): colour-science 0.4.7
  (`colour.appearance`), with `discount_illuminant=True` for the forced D=1
  the app uses by default.
- Hellwig&Fairchild 2022 on the CIECAM02 basis (CAT02 + HPE): written here
  from the paper's correlate definitions, reusing only colour's CAT02/HPE
  matrices and the standard response compression.
- Published worked examples: CIE 159:2004 CIECAM02 example and the Li et al.
  2017 CAM16 example (same stimulus), entered by hand.

White points use the exact `whitepoint()` values of MATLAB R2026a (x100).
"""
import itertools
import json
import pathlib
import sys

import numpy as np

import colour
from colour.appearance import (
    VIEWING_CONDITIONS_CIECAM02, VIEWING_CONDITIONS_CAM16,
    VIEWING_CONDITIONS_HELLWIG2022,
    XYZ_to_CIECAM02, XYZ_to_CAM16, XYZ_to_Hellwig2022,
)
from colour.adaptation import CAT_CAT02
from colour.appearance.hunt import MATRIX_XYZ_TO_HPE as MATRIX_HPE
from colour.appearance.ciecam02 import (
    luminance_level_adaptation_factor, degree_of_adaptation,
    post_adaptation_non_linear_response_compression_forward,
)
from colour.appearance.hellwig2022 import eccentricity_factor as ecc_hellwig

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "tests" / "fixtures" / "inverse-b.json"

# MATLAB R2026a whitepoint() values (Y=1) scaled to 100.
WHITES = {
    "d65": [0.95047, 1.0, 1.08883],
    "d50": [0.96419865576090, 1.0, 0.82511648322104],
    "a": [1.0985, 1.0, 0.3558],
    "e": [1.0, 1.0, 1.0],
}
SURROUND = {"average": (1.0, 0.69, 1.0), "dim": (0.9, 0.59, 0.9), "dark": (0.8, 0.525, 0.8)}


def hellwig_cam02_forward(XYZ, XYZ_w, L_A, Y_b, surround, D_forced):
    """Hellwig & Fairchild 2022 correlates on the CIECAM02 (CAT02+HPE) basis.

    Equations: Hellwig & Fairchild, Color Res Appl 47(5), 2022, eqs for A, J,
    Q, M, C, s, e_t; front end as CIE 159:2004 CIECAM02.
    """
    F, c, N_c = surround
    XYZ = np.asarray(XYZ, float)
    XYZ_w = np.asarray(XYZ_w, float)
    RGB_w = CAT_CAT02 @ XYZ_w
    D = 1.0 if D_forced else float(np.clip(degree_of_adaptation(F, L_A), 0, 1))
    Y_w = XYZ_w[1]
    D_RGB = D * Y_w / RGB_w + 1 - D
    F_L = luminance_level_adaptation_factor(L_A)
    n = Y_b / Y_w
    z = 1.48 + np.sqrt(n)
    RGB_wc = D_RGB * RGB_w
    RGB_wp = MATRIX_HPE @ np.linalg.solve(CAT_CAT02, RGB_wc)
    RGB_aw = post_adaptation_non_linear_response_compression_forward(RGB_wp, F_L)
    A_w = 2 * RGB_aw[0] + RGB_aw[1] + 0.05 * RGB_aw[2] - 0.305
    RGB = CAT_CAT02 @ XYZ
    RGB_c = D_RGB * RGB
    RGB_p = MATRIX_HPE @ np.linalg.solve(CAT_CAT02, RGB_c)
    RGB_a = post_adaptation_non_linear_response_compression_forward(RGB_p, F_L)
    Ra, Ga, Ba = RGB_a
    a = Ra - 12 * Ga / 11 + Ba / 11
    b = (Ra + Ga - 2 * Ba) / 9
    h = np.degrees(np.arctan2(b, a)) % 360
    A = 2 * Ra + Ga + 0.05 * Ba - 0.305
    J = 100 * (A / A_w) ** (c * z)
    Q = (2 / c) * (J / 100) * A_w
    e_t = ecc_hellwig(h)
    M = 43 * N_c * e_t * np.hypot(a, b)
    C = 35 * M / A_w
    s = 100 * M / Q if Q > 0 else 0.0
    return dict(J=float(J), C=float(C), h=float(h), Q=float(Q), M=float(M), s=float(s))


def colour_forward(model, XYZ, XYZ_w, L_A, Y_b, cond, D_forced):
    if model == "CAM02":
        spec = XYZ_to_CIECAM02(XYZ, XYZ_w, L_A, Y_b, VIEWING_CONDITIONS_CIECAM02[cond.capitalize()],
                               discount_illuminant=D_forced)
    elif model == "CAM16":
        spec = XYZ_to_CAM16(XYZ, XYZ_w, L_A, Y_b, VIEWING_CONDITIONS_CAM16[cond.capitalize()],
                            discount_illuminant=D_forced)
    elif model == "modCAM16":
        spec = XYZ_to_Hellwig2022(XYZ, XYZ_w, L_A, Y_b, VIEWING_CONDITIONS_HELLWIG2022[cond.capitalize()],
                                  discount_illuminant=D_forced)
    else:
        raise ValueError(model)
    return {k: float(getattr(spec, k)) for k in ("J", "C", "h", "Q", "M", "s")}


def forward(model, XYZ, XYZ_w, L_A, Y_b, cond, D_forced):
    if model == "modCAM02":
        return hellwig_cam02_forward(XYZ, XYZ_w, L_A, Y_b, SURROUND[cond], D_forced)
    return colour_forward(model, XYZ, XYZ_w, L_A, Y_b, cond, D_forced)


def sample_xyz(white_key):
    """Linear-sRGB grid, converted to XYZ (Y_w=100) and Bradford-adapted to the target white."""
    levels = [0.02, 0.1, 0.3, 0.6, 1.0]
    rgb = np.array(list(itertools.product(levels, repeat=3)))
    srgb = colour.RGB_COLOURSPACES["sRGB"]
    XYZ = colour.RGB_to_XYZ(rgb, srgb, apply_cctf_decoding=False)  # D65-relative, Y in 0..1
    target = np.array(WHITES[white_key])
    XYZ = colour.adaptation.chromatic_adaptation_VonKries(XYZ, np.array(WHITES["d65"]), target, transform="Bradford")
    extra = np.array([[0.0, 0.0, 0.0], [1e-4, 1e-4, 1e-4]]) * target  # black-ish
    XYZ = np.vstack([XYZ, extra, target * 0.5, target])
    return XYZ * 100.0


CONDITIONS = [
    # (white, surround, L_A, Y_b, D_forced)
    ("d65", "average", 20, 20, True),      # app default
    ("d65", "dim", 20, 20, True),
    ("d65", "dark", 20, 20, True),
    ("d65", "average", 200, 20, True),
    ("d65", "average", 20, 50, True),
    ("d65", "average", 20, 20, False),     # computed D
    ("d50", "average", 20, 20, True),
    ("a", "average", 20, 20, True),
    ("e", "average", 20, 20, True),
    ("a", "dim", 20, 20, False),
    ("d65", "dark", 200, 50, False),
]
MODELS = ["CAM02", "modCAM02", "CAM16", "modCAM16"]


def main():
    cases = []
    cid = 0
    for (wk, cond, L_A, Y_b, Df) in CONDITIONS:
        XYZ_w = np.array(WHITES[wk]) * 100
        XYZs = sample_xyz(wk)
        for model in MODELS:
            for XYZ in XYZs:
                with np.errstate(all="ignore"):
                    spec = forward(model, XYZ, XYZ_w, L_A, Y_b, cond, Df)
                if not all(np.isfinite(list(spec.values()))):
                    continue
                cases.append(dict(id=cid, model=model, white=wk, condition=cond, La=L_A, Yb=Y_b,
                                  D=1.0 if Df else "computed", XYZ=[float(v) for v in XYZ], **spec))
                cid += 1
    published = [
        dict(id=cid, model="CAM02", white="cie159", condition="average", La=318.31, Yb=20, D="computed",
             XYZ=[19.01, 20.00, 21.78], XYZw=[95.05, 100.0, 108.88],
             J=41.73, C=0.10, h=219.0, Q=195.37, M=0.11, s=2.36,
             source="CIE 159:2004 worked example (values rounded as published)"),
        dict(id=cid + 1, model="CAM16", white="cie159", condition="average", La=318.31, Yb=20, D="computed",
             XYZ=[19.01, 20.00, 21.78], XYZw=[95.05, 100.0, 108.88],
             J=41.73, C=0.1033, h=209.5, Q=195.37, M=0.1074, s=2.3450,
             source="Li et al. 2017 CAM16 example (Color Res Appl 42(6)) as reproduced by colour-science tests"),
    ]
    payload = dict(generator="tests/reference/generate_inverse_b.py",
                   colour_science=colour.__version__, numpy=np.__version__, python=sys.version.split()[0],
                   whites=WHITES, cases=cases, published=published)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload) + "\n")
    print(f"wrote {len(cases)} grid cases + {len(published)} published cases -> {OUT}")


if __name__ == "__main__":
    main()
