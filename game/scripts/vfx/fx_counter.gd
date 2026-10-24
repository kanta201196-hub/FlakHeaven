class_name FxCounter
extends RefCounted
## Estimate of GPU particles alive. The GPU does not report counts back cheaply, so each emit adds to the
## time bin where it expires and the counter subtracts bins as time passes: O(1) per emit and per query.
## Lifetimes longer than HORIZON are clamped (they then count as gone a little early; only budgets use this).

const BIN := 0.1
const BINS := 128
const HORIZON := BIN * (BINS - 1)

var _bins := PackedInt32Array()
var _total := 0
var _now_bin := 0   # absolute index of the last bin already expired


func _init() -> void:
	_bins.resize(BINS)


## Count n particles emitted at time now (s) that live for life seconds (delay included)
func add(now: float, life: float, n := 1) -> void:
	_advance(now)
	var end := int(floor((now + clampf(life, 0.0, HORIZON - BIN)) / BIN)) + 1
	_bins[end % BINS] += n
	_total += n


## Particles still alive at time now (s); time only moves forward
func alive(now: float) -> int:
	_advance(now)
	return _total


func _advance(now: float) -> void:
	var target := int(floor(now / BIN))
	if target - _now_bin >= BINS:   # long pause: everything expired
		_bins.fill(0)
		_total = 0
		_now_bin = target
		return
	while _now_bin < target:
		_now_bin += 1
		var i := _now_bin % BINS
		_total -= _bins[i]
		_bins[i] = 0
