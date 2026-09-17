"""Composed forward oracle for the app's Hellwig-modified CAM02 variant.

Colour 0.4.7 exposes the standard CIECAM02 and Hellwig2022 (CAM16-based)
models, but not a top-level Hellwig-modified CAM02 model. This module composes
Colour's public CAT02 adaptation/Hunt-Pointer-Estevez stages with its public
Hellwig2022 appearance-correlate functions. It never reads or calls the app's
inverse implementation. It is an independent numerical composition, not a
separately published reference implementation or evidence of perceptual
validity. No Helmholtz-Kohlrausch extension is included.

The optional 0.1 offsets in Colour's response compression are retained;
Colour's opponent and achromatic functions account for their cancellation.
The return object uses CAM_Specification_CIECAM02 only as a common container
for J, C, h, s, Q, M, and H; it does not label this variant as standard CAM02.
The signature and domain/range-scale convention match colour.XYZ_to_CAM16.

Source functions, pinned to Colour 0.4.7:
https://github.com/colour-science/colour/blob/v0.4.7/colour/appearance/ciecam02.py
https://github.com/colour-science/colour/blob/v0.4.7/colour/appearance/hellwig2022.py
"""

import numpy as np
import colour
from colour.algebra import vecmul
from colour.appearance import ciecam02, hellwig2022
from colour.utilities import (
    as_float,
    as_float_array,
    from_range_100,
    from_range_degrees,
    to_domain_100,
    tsplit,
)


def XYZ_to_modified_CAM02(
    XYZ,
    XYZ_w,
    L_A,
    Y_b,
    surround=colour.VIEWING_CONDITIONS_CAM16["Average"],
    discount_illuminant=False,
    compute_H=True,
):
    """Return CAT02/HPE responses expressed through Hellwig2022 correlates.

    XYZ and XYZ_w use the 0-100 reference scale. L_A is adapting-field
    luminance in cd/m2; Y_b shares the reference-white luminance scale.
    ``discount_illuminant=True`` forces D=1. Otherwise D follows Colour's
    surround/adapting-luminance equation, clipped to its physical [0,1] range.
    Array inputs follow Colour's broadcasting and domain/range conventions.
    """
    if colour.__version__ != "0.4.7":
        raise RuntimeError("This composed reference requires Colour 0.4.7")

    XYZ = to_domain_100(XYZ)
    XYZ_w = to_domain_100(XYZ_w)
    _, Y_w, _ = tsplit(XYZ_w)
    L_A = as_float_array(L_A)
    Y_b = as_float_array(Y_b)

    F_L, z = hellwig2022.viewing_conditions_dependent_parameters(Y_b, Y_w, L_A)
    RGB = vecmul(ciecam02.CAT_CAT02, XYZ)
    RGB_w = vecmul(ciecam02.CAT_CAT02, XYZ_w)
    D = (
        np.ones_like(L_A)
        if discount_illuminant
        else np.clip(ciecam02.degree_of_adaptation(surround.F, L_A), 0, 1)
    )

    RGB_c = ciecam02.full_chromatic_adaptation_forward(RGB, RGB_w, Y_w, D)
    RGB_wc = ciecam02.full_chromatic_adaptation_forward(RGB_w, RGB_w, Y_w, D)
    RGB_p = ciecam02.RGB_to_rgb(RGB_c)
    RGB_pw = ciecam02.RGB_to_rgb(RGB_wc)
    RGB_a = ciecam02.post_adaptation_non_linear_response_compression_forward(
        RGB_p, F_L
    )
    RGB_aw = ciecam02.post_adaptation_non_linear_response_compression_forward(
        RGB_pw, F_L
    )

    a, b = tsplit(hellwig2022.opponent_colour_dimensions_forward(RGB_a))
    h = hellwig2022.hue_angle(a, b)
    H = hellwig2022.hue_quadrature(h) if compute_H else np.full(h.shape, np.nan)
    e_t = hellwig2022.eccentricity_factor(h)
    A = hellwig2022.achromatic_response_forward(RGB_a)
    A_w = hellwig2022.achromatic_response_forward(RGB_aw)
    J = hellwig2022.lightness_correlate(A, A_w, surround.c, z)
    Q = hellwig2022.brightness_correlate(surround.c, J, A_w)
    M = hellwig2022.colourfulness_correlate(surround.N_c, e_t, a, b)
    C = hellwig2022.chroma_correlate(M, A_w)
    s = hellwig2022.saturation_correlate(M, Q)

    return ciecam02.CAM_Specification_CIECAM02(
        J=as_float(from_range_100(J)),
        C=as_float(from_range_100(C)),
        h=as_float(from_range_degrees(h)),
        s=as_float(from_range_100(s)),
        Q=as_float(from_range_100(Q)),
        M=as_float(from_range_100(M)),
        H=as_float(from_range_degrees(H, 400)),
        HC=None,
    )
