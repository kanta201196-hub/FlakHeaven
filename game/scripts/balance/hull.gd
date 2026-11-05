class_name HullBalance
extends RefCounted
## Player hull rules in the campaign («Битва асов» has its own in `AcesBalance`).

## Invulnerability after a hit, s. GD-14 (s15 item 21, Kanta 05.11): 0.7 → 0.55. In s15 the hull stayed at
## 80–100 % for 15 minutes and the plane was invulnerable 26 % of the sortie: in a dense fight the window after
## each hit swallowed almost every other bullet.
const HIT_INVULN := 0.55
