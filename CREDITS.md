# Contributors and references

Color Atlas began as a 2024 CLRS-820 Modeling Visual Perception team project by
**Fernando Voltolini de Azambuja, Nima Rabbanifar and Soroush Shahbaznejad**.

For version 2, I fixed a few issues and made improvements to the app.

## Implementation sources

Color Atlas uses numerical implementations adapted from **MCSL-Tools**,
developed at the Munsell Color Science Laboratory. Its contributors include
Luke Hellwig, Tucker Downs, Minyao Li, Michael Murdoch and Yongmin Park.
The full upstream notice is in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The tests use the [Colour](https://www.colour-science.org/) project's forward
models as independent numerical references for the app's inverse calculations.

## Scientific references

- CIE 159:2004, *A Colour Appearance Model for Colour Management Systems: CIECAM02*.
- Li et al. (2017), [Comprehensive color solutions: CAM16, CAT16, and CAM16-UCS](https://doi.org/10.1002/col.22131).
- Hellwig and Fairchild (2022), [Brightness, lightness, colorfulness, and chroma in CIECAM02 and CAM16](https://doi.org/10.1002/col.22792).
- Brettel, Viénot and Mollon (1997), [Computerized simulation of color appearance for dichromats](https://vision.psychol.cam.ac.uk/jdmollon/papers/Dichromatsimulation.pdf).

See [README.md](README.md) for the implemented models and their conventions.
