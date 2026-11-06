class_name FlightBalance
extends RefCounted
## Look of the player's bank in a turn (Kanta 2026-11-06: «из крена слишком быстро выходим, надо чуть замедлить
## наклон и стабилизацию после него»). Only the picture: the flight bank (`Player.bank`) that drives speed bleed
## and skills keeps its rate; the model follows a separate visible bank that rolls in a little slower and levels
## out clearly slower. Behind the F1 toggle `bank_soft` until Kanta's «ок» (R-22); the multipliers are the
## defaults of the F1 sliders `bank_soft_in` / `bank_soft_out`.

## Roll-in rate × this: a little slower (fighter 11 → 8.3 /s, ≈ 0.12 s time constant instead of 0.09 s).
const SOFT_IN_K := 0.75
## Level-out rate × this: fighter back to 10 % in ≈ 0.4 s instead of 0.2 s, bomber ≈ 1.2 s instead of 0.6 s.
const SOFT_OUT_K := 0.5
## Floor of either multiplier, so a slider at 0 never freezes the model on its side.
const MIN_K := 0.1


## Rate (1/s) at which the visible bank `bank` moves toward `want`: `rate_in` × `k_in` when it rolls deeper
## into the same turn, `rate_out` × `k_out` when it levels out or reverses. Multipliers are clamped to
## [MIN_K, 1], so the soft bank is never faster than the flight bank.
static func vis_bank_rate(bank: float, want: float, rate_in: float, rate_out: float, k_in: float, k_out: float) -> float:
	var deeper := absf(want) > absf(bank) and (signf(want) == signf(bank) or bank == 0.0)
	return rate_in * clampf(k_in, MIN_K, 1.0) if deeper else rate_out * clampf(k_out, MIN_K, 1.0)
