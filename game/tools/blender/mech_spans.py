"""Where the wing mechanisation sits on each plane; shared by wing_mech.py (battle plates) and mech_cut.py
(sections cut out of the hangar models, S11-02).
Blender axes of the hangar model: length 1, nose +X, left wing +Y, up +Z.
Each segment: (y0, y1, xm0, xm1) — span from the axis (left wing; the right one is mirrored) and the middle of the chord
at both ends, so the silhouette search finds the wing and not a nacelle or the tailplane. Taken from the top view 17.10.
fighter_2 (Meshy model, 24.10): exposed wing |y| 0.18-0.41; inboard of 0.21 the tailplane almost touches the trailing
edge under a top-down ray, so the flaps start at 0.21.
Slats — the outer 50-70 % of the panel, flaps — inner, no ailerons at the tip."""

SPANS = {
    # fighter_1 «Оса» (Sketchfab model, VIS-01, 24.10): swing wing from the glove (y 0.09) to the tip (0.225)
    "fighter_1": {"slat": [(0.14, 0.205, -0.21, -0.334)], "flap": [(0.10, 0.17, -0.153, -0.276)]},
    "fighter_2": {"slat": [(0.20, 0.37, -0.165, -0.238)], "flap": [(0.21, 0.32, -0.174, -0.218)]},
    "attacker_1": {"slat": [(0.20, 0.42, -0.12, -0.17)], "flap": [(0.12, 0.32, -0.10, -0.14)]},
    "attacker_2": {"slat": [(0.20, 0.44, -0.16, -0.20)], "flap": [(0.15, 0.33, -0.15, -0.18)]},
    # «Кит 1»: between the nacelles and outboard of the outer one
    "bomber_1": {"slat": [(0.21, 0.26, -0.03, -0.045), (0.37, 0.48, -0.11, -0.16)],
                 "flap": [(0.20, 0.27, -0.02, -0.04), (0.355, 0.41, -0.09, -0.12)]},
    "bomber_2": {"slat": [(0.20, 0.48, -0.11, -0.25)], "flap": [(0.17, 0.36, -0.10, -0.19)]},
}
SLAT_C = 0.15     # share of the local chord
FLAP_C = 0.26
