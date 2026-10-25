class_name BuildOrder
extends RefCounted
## Order of test build numbers ("3.5-s11"): kept free of autoloads so unit tests can load it
## (UpdateCheck uses it to decide whether the site has a newer build).


## true when build `a` is later than `b`: "3.5-s12" > "3.5-s11" > "3.5-s9" (numbers compared in order)
static func newer(a: String, b: String) -> bool:
	var na := _nums(a)
	var nb := _nums(b)
	if na.is_empty() or nb.is_empty():
		return false
	for i in maxi(na.size(), nb.size()):
		var x := na[i] if i < na.size() else 0
		var y := nb[i] if i < nb.size() else 0
		if x != y:
			return x > y
	return false


static func _nums(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cur := ""
	for ch in s + ".":
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			out.append(int(cur))
			cur = ""
	return out
