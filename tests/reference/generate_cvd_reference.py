#!/usr/bin/env python3
"""Independent, deterministic CVD geometry fixture; no app imports or reads.

Run from the repository root:
    .venv-validation/bin/python tests/reference/generate_cvd_reference.py

This is an explicitly specified two-wing HPE/selected-white approximation,
not an implementation of Brettel's original Stockman/equal-energy observer.
The geometry and wing rules are from Brettel, Vienot & Mollon (1997),
equations 6-11 and the rules below them, DOI: 10.1364/JOSAA.14.002647.
The independent oracle solves three linear constraints: retain two cone
coordinates and lie in the chosen white/anchor plane. No MATLAB method,
new or old, is imported, extracted, or called to create these expectations.
"""

from __future__ import annotations

import hashlib
import itertools
import json
from pathlib import Path
import warnings

warnings.filterwarnings("ignore", message='.*related API features are not available.*')

import colour
import numpy as np


EXPECTED_VERSIONS = {"colour-science": "0.4.7", "numpy": "2.5.3"}
HPE = np.array(
    [[0.4002, 0.7075, -0.0807], [-0.2280, 1.1500, 0.0612], [0.0, 0.0, 0.9184]]
)
WHITES = {
    "D65": np.array([95.047, 100.0, 108.883]),
    "D50": np.array([96.422, 100.0, 82.521]),
    "A": np.array([109.85, 100.0, 35.585]),
}
# missing coordinate, ratio numerator, ratio denominator, lower/upper wings
MODES = {
    "protanopia": (0, 2, 1, 575, 475),
    "deuteranopia": (1, 2, 0, 575, 475),
    "tritanopia": (2, 1, 0, 660, 485),
}
# Exact values from CIE 1931 2 degree CMFs at the four anchor wavelengths.
# They are directions, expressed here at the fixture's nominal Y=100 scale;
# there is no claim that these spectral anchors fit inside an RGB gamut.
CIE_ANCHORS = {
    475: np.array([14.21, 11.26, 104.19]),
    575: np.array([84.25, 91.54, 0.18]),
    485: np.array([5.795001, 16.93, 61.62]),
    660: np.array([16.49, 6.10, 0.0]),
}
ABS_TOLERANCE = 1e-9


def reference_projection(xyz, white, mode):
    """Project onto a specified half-plane using independent constraints."""
    xyz, white = np.asarray(xyz, dtype=float), np.asarray(white, dtype=float)
    missing, numerator, denominator, lower, upper = MODES[mode]
    q, neutral = HPE @ xyz, HPE @ white
    assert np.all(np.isfinite(q)) and np.all(np.isfinite(neutral))
    assert neutral[denominator] > 0.0 and q[denominator] >= 0.0
    # The denominator is positive in this fixture's physical stimulus domain.
    # A determinant avoids division by a stimulus component at black.
    side = q[numerator] * neutral[denominator] - q[denominator] * neutral[numerator]
    anchor_nm = lower if side < 0.0 else upper
    normal = np.cross(neutral, HPE @ CIE_ANCHORS[anchor_nm])
    normal /= np.linalg.norm(normal)
    retained = [index for index in range(3) if index != missing]
    constraints = np.vstack((np.eye(3)[retained], normal))
    rhs = np.array([q[retained[0]], q[retained[1]], 0.0])
    projected_lms = np.linalg.solve(constraints, rhs)
    projected_xyz = np.linalg.solve(HPE, projected_lms)
    # An algebraically different line/plane-intersection construction guards
    # against accidentally solving the constraints along the wrong direction.
    intersection = q.copy()
    intersection[missing] -= np.dot(normal, q) / normal[missing]
    np.testing.assert_allclose(projected_lms, intersection, atol=1e-10, rtol=1e-12)
    return projected_xyz, anchor_nm, retained, normal


def base_stimuli(white, mode):
    """In-gamut RGB inputs, neutrals, all anchors, and signed wing probes."""
    # Use the white returned by the same pinned sRGB transform, avoiding a
    # white mismatch from its rounded RGB matrix. Only grid XYZ is adapted;
    # the spectral anchor definitions and projection are not adapted.
    rgb_white_xyz = colour.sRGB_to_XYZ(np.ones(3))
    for index, rgb in enumerate(itertools.product([0.0, 0.1, 0.25, 0.5, 1.0], repeat=3)):
        xyz_d65 = colour.sRGB_to_XYZ(np.array(rgb))
        xyz = 100.0 * colour.adaptation.chromatic_adaptation_VonKries(
            xyz_d65, rgb_white_xyz, white / 100.0, transform="Bradford"
        )
        yield f"srgb-{index:03d}", "srgb-grid", xyz
    for index, luminance in enumerate([0.0, 1e-6, 1e-4, 0.001, 0.01, 0.1, 0.2, 0.5, 1.0]):
        yield f"neutral-{index:02d}", "neutral", luminance * white
    for nm, xyz in sorted(CIE_ANCHORS.items()):
        yield f"spectral-{nm}", "spectral-anchor", xyz
    _, numerator, _, _, _ = MODES[mode]
    neutral_lms = HPE @ (0.2 * white)
    for amount in [1e-8, 1e-5, 1e-2, 1.0]:
        for sign, name in [(-1, "negative"), (1, "positive")]:
            probe = neutral_lms.copy()
            probe[numerator] += sign * amount
            yield f"separator-{name}-{amount:g}", "separator", np.linalg.solve(HPE, probe)
    yield "warm-interior", "interior", np.array([40.0, 30.0, 20.0])


def main():
    versions = {"colour-science": colour.__version__, "numpy": np.__version__}
    if versions != EXPECTED_VERSIONS:
        raise RuntimeError(f"Use tests/requirements.txt: expected {EXPECTED_VERSIONS}, got {versions}")
    cmfs = colour.MSDS_CMFS["CIE 1931 2 Degree Standard Observer"]
    for nm, anchor in CIE_ANCHORS.items():
        np.testing.assert_allclose(100.0 * cmfs[nm], anchor, atol=2e-12, rtol=0.0)

    cases = []
    maxima = {name: 0.0 for name in [
        "neutralXYZ", "invariantAnchorXYZ", "retainedLMS", "planeResidualLMS",
        "idempotenceXYZ", "positiveScaleXYZ", "whiteScaleXYZ",
    ]}
    branch_counts = {white: {mode: {} for mode in MODES} for white in WHITES}

    def record(case_id, family, variant, mode, white, xyz, expected, anchor, base_id):
        cases.append({
            "id": case_id,
            "family": family,
            "variant": variant,
            "baseId": base_id,
            "mode": mode,
            "white": np.asarray(white).tolist(),
            "XYZ": np.asarray(xyz).tolist(),
            "expectedXYZ": np.asarray(expected).tolist(),
            "selectedAnchorNm": int(anchor),
        })

    for white_name, white in WHITES.items():
        for mode, (missing, _, _, lower, upper) in MODES.items():
            for label, family, xyz in base_stimuli(white, mode):
                base_id = f"{white_name}-{mode}-{label}"
                expected, anchor, retained, normal = reference_projection(xyz, white, mode)
                counts = branch_counts[white_name][mode]
                counts[str(anchor)] = counts.get(str(anchor), 0) + 1
                assert np.all(np.isfinite(expected))
                q, projected = HPE @ xyz, HPE @ expected
                maxima["retainedLMS"] = max(maxima["retainedLMS"], float(np.max(np.abs(projected[retained] - q[retained]))))
                maxima["planeResidualLMS"] = max(maxima["planeResidualLMS"], abs(float(np.dot(normal, projected))))
                if family == "neutral":
                    maxima["neutralXYZ"] = max(maxima["neutralXYZ"], float(np.max(np.abs(expected - xyz))))
                if label in [f"spectral-{lower}", f"spectral-{upper}"]:
                    assert anchor == int(label.removeprefix("spectral-"))
                    maxima["invariantAnchorXYZ"] = max(maxima["invariantAnchorXYZ"], float(np.max(np.abs(expected - xyz))))
                if family == "separator":
                    wanted = lower if "negative" in label else upper
                    assert anchor == wanted, (base_id, anchor, wanted)
                record(base_id, family, "base", mode, white, xyz, expected, anchor, base_id)

                for scale in [0.01, 3.0]:
                    actual_scaled, scaled_anchor, _, _ = reference_projection(xyz * scale, white, mode)
                    maxima["positiveScaleXYZ"] = max(maxima["positiveScaleXYZ"], float(np.max(np.abs(actual_scaled - expected * scale))))
                    record(f"{base_id}-input-scale-{scale:g}", family, "input-scale", mode,
                           white, xyz * scale, expected * scale, scaled_anchor, base_id)

                reapplied, next_anchor, _, _ = reference_projection(expected, white, mode)
                maxima["idempotenceXYZ"] = max(maxima["idempotenceXYZ"], float(np.max(np.abs(reapplied - expected))))
                record(f"{base_id}-reproject", family, "idempotence", mode, white,
                       expected, expected, next_anchor, base_id)

                # The selected neutral supplies a direction, so its positive
                # scale must not alter a projection at fixed input scale.
                rescaled_white, white_anchor, _, _ = reference_projection(xyz, white * 0.01, mode)
                maxima["whiteScaleXYZ"] = max(maxima["whiteScaleXYZ"], float(np.max(np.abs(rescaled_white - expected))))
                record(f"{base_id}-white-scale-0.01", family, "white-scale", mode,
                       white * 0.01, xyz, expected, white_anchor, base_id)

    assert all(value < ABS_TOLERANCE for value in maxima.values()), maxima
    assert len(cases) == len({case["id"] for case in cases})
    for white_modes in branch_counts.values():
        for mode, counts in white_modes.items():
            assert set(counts) == {str(nm) for nm in MODES[mode][-2:]}
    fixture = {
        "schemaVersion": 1,
        "description": "Independent two-wing HPE/selected-white-neutral dichromat geometry reference",
        "modelBoundary": "Brettel-style approximation; not original Stockman/equal-energy observer parity or perceptual validation",
        "XYZScale": "Nominal white Y=100; explicit input-scale and white-scale cases also test scale independence",
        "displayPolicy": "Raw XYZ expectations only; no clipping, gamut rejection, RGB encoding or monitor assumptions",
        "HPE_XYZ_to_LMS": HPE.tolist(),
        "anchorsXYZ": {str(nm): xyz.tolist() for nm, xyz in sorted(CIE_ANCHORS.items())},
        "grid": "5x5x5 encoded sRGB, converted by Colour 0.4.7 then Bradford-adapted from its numerical RGB white to each selected reference white",
        "wingRules": {
            "protanopia": "S*Mw-M*Sw < 0: 575 nm; otherwise 475 nm; replace L",
            "deuteranopia": "S*Lw-L*Sw < 0: 575 nm; otherwise 475 nm; replace M",
            "tritanopia": "M*Lw-L*Mw < 0: 660 nm; otherwise 485 nm; replace S",
        },
        "separatorPolicy": "Division-free determinant; exact zero selects the otherwise wing; neutral outputs coincide on both planes",
        "sources": [
            "https://doi.org/10.1364/JOSAA.14.002647",
            "https://vision.psychol.cam.ac.uk/jdmollon/papers/Dichromatsimulation.pdf",
            "https://doi.org/10.25039/CIE.DS.xvudnb9b",
            "https://github.com/colour-science/colour/tree/v0.4.7",
        ],
        "versions": versions,
        "generatorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "absoluteXYZTolerance": ABS_TOLERANCE,
        "baseCasesPerWhiteAndMode": 147,
        "caseCount": len(cases),
        "selfChecks": {"passed": True, "maximumAbsoluteErrors": maxima, "baseWingCounts": branch_counts},
        "cases": cases,
    }
    assert len(cases) == 147 * 3 * 3 * 5
    output = Path(__file__).resolve().parents[2] / "tests/fixtures/cvd.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(fixture, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"output": str(output), "caseCount": len(cases), "selfChecks": fixture["selfChecks"]}, indent=2))


if __name__ == "__main__":
    main()
