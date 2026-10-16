class_name Hull
extends RefCounted
## The water a folded sheet keeps out (S5, design doc 4.1), on a voxel grid in
## the sheet's own frame. Paper marks cells solid. For a pose and a waterline,
## water fills every open cell below the waterline it can reach from outside
## the grid; the open cells below the waterline it can't reach are dry: air
## the paper holds under the waterline, which is what floats a boat. A leak
## (a gap in the walls, or a rim dipping under) lets the water in.

const CELL := 0.25

var origin := Vector3.ZERO ## the grid's lowest corner, sheet-local
var dims := Vector3i.ZERO
var solid := PackedByteArray()


## Builds the grid for `facets` (with stacking `offsets`), sheet-local.
static func build(facets: Array, offsets: Array) -> Hull:
	var h := Hull.new()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		var off: Vector3 = offsets[i] if i < offsets.size() else Vector3.ZERO
		for q in f.pts:
			var p := f.at(q) + off
			lo = lo.min(p)
			hi = hi.max(p)
	h.origin = lo - Vector3.ONE * CELL * 1.5
	var size := hi - lo + Vector3.ONE * CELL * 3.0
	h.dims = Vector3i(ceili(size.x / CELL), ceili(size.y / CELL), ceili(size.z / CELL))
	h.solid.resize(h.dims.x * h.dims.y * h.dims.z)
	h.solid.fill(0)
	var step := CELL * 0.4
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		var off: Vector3 = offsets[i] if i < offsets.size() else Vector3.ZERO
		var box := Rect2(f.pts[0], Vector2.ZERO)
		for q in f.pts:
			box = box.expand(q)
		var nx := maxi(ceili(box.size.x / step), 1)
		var ny := maxi(ceili(box.size.y / step), 1)
		for ix in nx + 1:
			for iy in ny + 1:
				var q := box.position + Vector2(box.size.x * ix / nx, box.size.y * iy / ny)
				if Geometry2D.is_point_in_polygon(q, f.pts) or _near_edge(q, f.pts, step):
					h._mark(f.at(q) + off)
	return h


static func _near_edge(q: Vector2, pts: PackedVector2Array, d: float) -> bool:
	for i in pts.size():
		var c := Geometry2D.get_closest_point_to_segment(q, pts[i], pts[(i + 1) % pts.size()])
		if c.distance_to(q) < d:
			return true
	return false


func _mark(p: Vector3) -> void:
	var c := ((p - origin) / CELL).floor()
	var i := Vector3i(c)
	if i.x >= 0 and i.y >= 0 and i.z >= 0 and i.x < dims.x and i.y < dims.y and i.z < dims.z:
		solid[_index(i.x, i.y, i.z)] = 1


func _index(x: int, y: int, z: int) -> int:
	return (z * dims.y + y) * dims.x + x


## Dry space held under the waterline `water_y` (world) with the sheet at
## `pose`: {volume (m^3), center (world), below (open cells under the
## waterline)}.
func dry(pose: Transform3D, water_y: float) -> Dictionary:
	var n := dims.x * dims.y * dims.z
	var under := PackedByteArray()
	under.resize(n)
	var ys := PackedFloat32Array()
	ys.resize(n)
	var o := pose * (origin + Vector3.ONE * CELL * 0.5)
	var bx := pose.basis.x * CELL
	var by := pose.basis.y * CELL
	var bz := pose.basis.z * CELL
	var below := 0
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var i := _index(x, y, z)
				var wy: float = o.y + bx.y * x + by.y * y + bz.y * z
				ys[i] = wy
				if wy - CELL * 0.5 < water_y and solid[i] == 0: # (any of it under)
					under[i] = 1
					below += 1
	# Water comes in from outside the grid: flood from its faces.
	var wet := PackedByteArray()
	wet.resize(n)
	var stack := PackedInt32Array()
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				if x == 0 or y == 0 or z == 0 or x == dims.x - 1 or y == dims.y - 1 or z == dims.z - 1:
					var i := _index(x, y, z)
					if under[i] == 1:
						wet[i] = 1
						stack.append(i)
	var sx := 1
	var sy := dims.x
	var sz := dims.x * dims.y
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := i % dims.x
		var y := (i / dims.x) % dims.y
		var z := i / sz
		for k in 6:
			var j := -1
			match k:
				0: j = i - sx if x > 0 else -1
				1: j = i + sx if x < dims.x - 1 else -1
				2: j = i - sy if y > 0 else -1
				3: j = i + sy if y < dims.y - 1 else -1
				4: j = i - sz if z > 0 else -1
				5: j = i + sz if z < dims.z - 1 else -1
			if j >= 0 and under[j] == 1 and wet[j] == 0:
				wet[j] = 1
				stack.append(j)
	var count := 0.0
	var sum := Vector3.ZERO
	for z in dims.z:
		for y in dims.y:
			for x in dims.x:
				var i := _index(x, y, z)
				if under[i] == 1 and wet[i] == 0:
					var part := clampf((water_y - ys[i]) / CELL + 0.5, 0.0, 1.0) # how much of the cell is under
					count += part
					sum += Vector3(x, y, z) * part
	var center := Vector3.ZERO
	if count > 0.0:
		center = o + pose.basis * ((sum / count) * CELL)
	return {"volume": count * CELL * CELL * CELL, "center": center, "below": below}
