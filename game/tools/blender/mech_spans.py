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
    # tier 1 (PT-03, 06.11), measured on the hangar models' top view: fuselage edge |y| 0.07
    # «Оса 1»: drop tank under 0.26-0.30 (its nose shows ahead of the leading edge), wing fences at 0.29 and 0.40, tip at 0.48; the slat sits between the fences
    "fighter_t1": {"slat": [(0.32, 0.39, -0.016, -0.061)], "flap": [(0.10, 0.25, 0.117, 0.034)]},
    # «Грач 1»: straight wing 0.08-0.50, tip tanks outboard of 0.51
    "attacker_t1": {"slat": [(0.30, 0.48, 0.094, 0.102)], "flap": [(0.10, 0.30, 0.098, 0.094)]},
    # «Кит 1»: straight wing, fuselage edge 0.045, coupled-engine nacelle 0.13-0.20, tip at 0.69; mid-chord ~0.08
    "bomber_t1": {"slat": [(0.22, 0.40, 0.085, 0.09)],
                  "flap": [(0.055, 0.12, 0.08, 0.08), (0.21, 0.40, 0.082, 0.085)]},
    # tiers 4-5 (PT-02, 07.11), chord runs of the hangar models under vertical rays
    # «Оса 4»: blended body to |y| 0.10, leading edge swept back, trailing edge swept forward, tip at 0.317
    "fighter_t4": {"slat": [(0.17, 0.27, -0.125, -0.17)], "flap": [(0.11, 0.22, -0.095, -0.14)]},
    # «Оса 5»: manta wing outboard of the engine humps (|y| 0.08), tip pod at 0.36-0.42
    "fighter_t5": {"slat": [(0.22, 0.32, -0.236, -0.212)], "flap": [(0.12, 0.24, -0.21, -0.237)]},
    # «Грач 4»: intake trunks to |y| 0.16, tip tanks outboard of 0.38
    "attacker_t4": {"slat": [(0.25, 0.36, -0.08, -0.105)], "flap": [(0.18, 0.32, -0.07, -0.092)]},
    # «Грач 5»: engine pods to |y| 0.20 (their silhouette joins the trailing edge inboard of it), tip pods outboard of 0.34
    "attacker_t5": {"slat": [(0.24, 0.33, -0.122, -0.135)], "flap": [(0.21, 0.30, -0.12, -0.13)]},
    # «Кит 4»: forward-swept wing; inner nacelle under 0.13-0.18 (its exhaust behind the trailing edge), outer one
    # under 0.19-0.24 ahead of the leading edge, tip at 0.38
    "bomber_t4": {"slat": [(0.25, 0.355, 0.02, 0.09)],
                  "flap": [(0.065, 0.125, -0.05, -0.04), (0.19, 0.30, -0.013, 0.05)]},
    # «Кит 5»: blended body; the rounded stub wings between the front and rear ducted fans carry both, outboard of
    # the fan fairing (|y| 0.28) where the leading edge is straight
    "bomber_t5": {"slat": [(0.285, 0.31, 0.01, 0.005)], "flap": [(0.28, 0.31, 0.01, 0.005)]},
}
SLAT_C = 0.15     # share of the local chord
FLAP_C = 0.26
