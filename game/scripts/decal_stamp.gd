class_name DecalStamp
extends RefCounted
## One rectangle of atlas art pressed onto the skin: a picture, one digit of a number or one tally mark.
## `DecalLoadout.stamps` expands a record into stamps; `DecalMesh.Builder.project` cuts the skin under each one.

var center := Vector3.ZERO   ## on the skin, model axes
var normal := Vector3(0.0, 0.0, -1.0)
var right := Vector3(1.0, 0.0, 0.0)
var up := Vector3.UP
var half_w := 0.02
var half_h := 0.02
var uv := Rect2()            ## atlas rect of the art
var mirror := false
var c1 := 0                  ## paint indices (DecalCatalog.paint_index)
var c2 := 0
