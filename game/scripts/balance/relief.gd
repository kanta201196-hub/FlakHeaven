class_name ReliefBalance
extends RefCounted
## Numbers of the Нагорье landform regions (RV-01, Kanta 2026-10-24). Used by `ReliefProvinces`.
## Distances are world px (as `Terrain3D`), heights are shares of the relief ceiling
## (470 px under the combat plane), so mountains never reach the planes.

## Size of a region: elevation class and mesa noise wavelengths, px. 9000 px gives regions
## of about 5–10 km, a few per screen-minute of flight.
const ELEV_WAVE := 9000.0
const MESA_WAVE := 7000.0
## Elevation class noise → 0 (hills) … 1 (high range): smoothstep edges.
const ELEV_EDGE := 0.38
## Mesa noise threshold (smoothstep from, to) and the elevation it needs (no mesas in hills).
const MESA_FROM := 0.0
const MESA_TO := 0.3
const MESA_ELEV_FROM := 0.2
const MESA_ELEV_TO := 0.45
## Hill share falls from 1 to 0 while the elevation class goes HILLS_FROM → HILLS_TO.
const HILLS_FROM := 0.12
const HILLS_TO := 0.42
## Bank asymmetry: the slope run of each bank is multiplied by ASYM_MIN … ASYM_MAX.
const ASYM_WAVE := 3800.0
const ASYM_MIN := 0.55
const ASYM_MAX := 1.7

## Valley floor up to D_FLOOR + 40 stays as it was: floor bumps (0.0075) plus the first
## metres of the fan never rise above this share there.
const FLOOR_MAX := 0.012
## Where the floor ends and the fan reaches its foot (Terrain3D.D_FLOOR, D_FAN).
const D_FLOOR := 260.0
const D_FAN := 480.0
## Slope run from the foot to the crest, px: long and gentle in hills, short in high ranges.
const RUN_HILLS := 2600.0
const RUN_HIGH := 800.0
## Hills start further from the river: wide valleys with fields where hills meet the river.
const HILLS_FOOT := 250.0
## Crest height share: lowest hills … highest range (the old relief: 0.3 … 1.0 everywhere).
const TOP_LOW := 0.38
const TOP_HIGH := 1.0
## Main crests and spurs of high ranges (ridged noise wavelength and strength).
const SPINE_WAVE := 3400.0
const SPINE_K := 0.4
## Rounded knolls of hill regions and lone peaks rising from them.
const ROLL_WAVE := 1300.0
const ROLL_K := 0.55
const CONE_WAVE := 2100.0
const CONE_K := 0.7
## Mesa: cliff run above the floor, px; plateau top share (low … high elevation); levels.
const MESA_CLIFF := 260.0
const MESA_TOP_LOW := 0.35
const MESA_TOP_HIGH := 0.62
const MESA_LEVELS := 4.0
## Kanta 24.10 («резкие перепады и идеально ровное место, так не бывает»): a ledge keeps this share
## of the ground's own rise and roll (no dead-flat tables), the lower MESA_TALUS share of each step
## is a concave scree apron under the wall instead of a sheer drop; MESA_HUMMOCK — low mounds on the
## ledges (share of the ceiling, ±), MESA_KNOB — small ~180 px mounds on top of them.
const MESA_TREAD := 0.3
const MESA_TALUS := 0.4
const MESA_HUMMOCK := 0.05
const MESA_KNOB := 0.022
## Side canyons in mesa regions: noise wavelength and half-width (in noise units).
const CANYON_WAVE := 2600.0
const CANYON_W := 0.05
## RV-02 gullies (own "erosion filter", Kanta 2026-10-24): stripes running down the slope in
## cells of GULLY_CELL px, GULLY_OCTAVES finer layers that follow the slope plus the coarser
## gullies (so they branch). GULLY_AMP — depth of the coarsest layer in shares of the ceiling,
## each finer layer GULLY_GAIN of the previous; GULLY_BIAS — how much deeper than high (0…1). GULLY_SLOPE_* — base slope (share per px) where
## gullies start and reach full depth: none on flat ground. ERO_KEEP — share of the old uniform
## "wrinkle" noise swing kept on slopes once gullies are on (its mean stays, so peaks keep their height).
const GULLY_CELL := 420.0
const GULLY_OCTAVES := 3
const GULLY_AMP := 0.17
const GULLY_GAIN := 0.5
const GULLY_BIAS := 0.15
const GULLY_SLOPE_FROM := 0.00005
const GULLY_SLOPE_TO := 0.0003
const ERO_KEEP := 0.35
