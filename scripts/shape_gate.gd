class_name ShapeGate
extends Node3D
## A shape the folded paper must match (S2). Two modes:
##
## Fit box (setup_box): a glowing wire box, like a luggage sizer. It opens once
## every corner of some sheet is inside it.
##
## Profile (setup): a glowing outline painted on a wall. Paper standing just
## in front of the wall counts as filling the outline where, seen straight on,
## it covers it. The gate opens once the paper covers at least MIN_COVER of the
## shape with no more than MAX_SPILL (of the shape's area) poking out around
## it, and then stays open.
##
## The outline lies in this node's local XY plane (x right, y up, metres);
## local +Z points out of the wall toward the players.

signal opened

enum { PROFILE, FIT_BOX }

const MIN_COVER := 0.9
const MAX_SPILL := 0.1
const CELL := 0.1 ## raster resolution, metres
const MARGIN := 1.0 ## how far around the outline spill is looked for
const CHECK_EVERY := 6 ## physics frames between checks

var outline := PackedVector2Array() ## the shape, counter-clockwise, local XY
var depth := 1.2 ## paper further than this in front of the wall doesn't count
var sheets: Array = [] ## the sheets that can fill it
var coverage := 0.0 ## share of the outline covered, 0..1
var spill := 0.0 ## paper outside the outline, as a share of the outline's area
var is_open := false
var mode := PROFILE
var box_size := Vector3.ZERO ## (fit box) x, height, z; the box stands on this node's origin
var stick_out := 0.0 ## (fit box) how far the best-fitting sheet pokes out of it, metres
const FIT_SLACK := 0.05

var _cells_in: Array = [] ## Vector2 centres of raster cells inside the outline
var _cells_out: Array = [] ## ...and of cells in the margin around it
var _line_mat: StandardMaterial3D
var _frame := 0


## `shape` is the outline in local XY; `targets` the sheets that count.
func setup(shape: PackedVector2Array, targets: Array, max_depth := 1.2) -> void:
	outline = shape
	sheets = targets
	depth = max_depth
	var box := Rect2(shape[0], Vector2.ZERO)
	for p in shape:
		box = box.expand(p)
	box = box.grow(MARGIN)
	var nx := ceili(box.size.x / CELL)
	var ny := ceili(box.size.y / CELL)
	for ix in nx:
		for iy in ny:
			var c := box.position + Vector2((ix + 0.5) * CELL, (iy + 0.5) * CELL)
			if Geometry2D.is_point_in_polygon(c, shape):
				_cells_in.append(c)
			else:
				_cells_out.append(c)
	_build_outline()


## Fit-box mode: the box is `size` (x, height, z), standing on this node's
## origin, and a sheet fits when every corner of its paper is inside it.
func setup_box(size: Vector3, targets: Array) -> void:
	mode = FIT_BOX
	box_size = size
	sheets = targets
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(1.0, 0.85, 0.3)
	var h := size * 0.5
	for axis in 3:
		for u in [-1.0, 1.0]:
			for v in [-1.0, 1.0]:
				var c := Vector3.ZERO
				var dims := Vector3.ONE * 0.07
				dims[axis] = size[axis] + 0.07
				c[(axis + 1) % 3] = u * h[(axis + 1) % 3]
				c[(axis + 2) % 3] = v * h[(axis + 2) % 3]
				c.y += h.y
				var bar := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = dims
				bar.mesh = bm
				bar.material_override = _line_mat
				bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bar.position = c
				add_child(bar)


func _build_outline() -> void:
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(1.0, 0.85, 0.3)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(a.distance_to(b) + 0.12, 0.12, 0.04)
		seg.mesh = bm
		seg.material_override = _line_mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0.03)
		seg.rotation.z = (b - a).angle()
		add_child(seg)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if is_open or _frame % CHECK_EVERY != 0:
		return
	measure()
	if mode == FIT_BOX:
		_line_mat.albedo_color = Color(1.0, 0.85, 0.3).lerp(Color(0.35, 1.0, 0.45), clampf(coverage, 0.0, 1.0))
		if coverage >= 1.0:
			is_open = true
			_line_mat.albedo_color = Color(0.35, 1.0, 0.45)
			opened.emit()
		return
	var c := Color(1.0, 0.85, 0.3).lerp(Color(0.35, 1.0, 0.45), clampf(coverage, 0.0, 1.0))
	if spill > MAX_SPILL:
		c = c.lerp(Color(1.0, 0.25, 0.2), 0.6)
	_line_mat.albedo_color = c
	if coverage >= MIN_COVER and spill <= MAX_SPILL:
		is_open = true
		_line_mat.albedo_color = Color(0.35, 1.0, 0.45)
		opened.emit()


## Recomputes coverage and spill (or, for a fit box, the share of the paper's
## corners inside it and how far it sticks out) from where the paper is now.
func measure() -> void:
	if mode == FIT_BOX:
		_measure_box()
		return
	var polys: Array = []
	var to_local := global_transform.affine_inverse()
	for s in sheets:
		var sh: PaperSheet = s
		if not is_instance_valid(sh):
			continue
		for i in sh.facets.size():
			var f: PaperModel.Facet = sh.facets[i]
			var off: Vector3 = sh._offsets[i] if i < sh._offsets.size() else Vector3.ZERO
			var poly := PackedVector2Array()
			var nearest := INF
			for q in f.pts:
				var w: Vector3 = to_local * (sh.global_transform * (f.at(q) + off))
				nearest = minf(nearest, w.z)
				poly.append(Vector2(w.x, w.y))
			if nearest > depth or nearest < -0.5 or absf(PaperGeometry.signed_area(poly)) < 1e-4:
				continue # too far from the wall, behind it, or edge-on
			polys.append(poly)
	var hit_in := 0
	for c in _cells_in:
		if _covered(c, polys):
			hit_in += 1
	var hit_out := 0
	for c in _cells_out:
		if _covered(c, polys):
			hit_out += 1
	var n := maxf(_cells_in.size(), 1.0)
	coverage = hit_in / n
	spill = hit_out / n


func _measure_box() -> void:
	var to_local := global_transform.affine_inverse()
	var h := box_size * 0.5
	coverage = 0.0
	stick_out = INF
	for s in sheets:
		var sh: PaperSheet = s
		if not is_instance_valid(sh):
			continue
		var inside := 0
		var total := 0
		var worst := 0.0
		for i in sh.facets.size():
			var f: PaperModel.Facet = sh.facets[i]
			var off: Vector3 = sh._offsets[i] if i < sh._offsets.size() else Vector3.ZERO
			for q in f.pts:
				var w: Vector3 = to_local * (sh.global_transform * (f.at(q) + off))
				var out := maxf(maxf(absf(w.x) - h.x, absf(w.z) - h.z), maxf(-w.y, w.y - box_size.y))
				total += 1
				if out <= FIT_SLACK:
					inside += 1
				worst = maxf(worst, out)
		if total > 0 and float(inside) / total >= coverage:
			coverage = float(inside) / total
			stick_out = minf(stick_out, maxf(worst, 0.0))


static func _covered(c: Vector2, polys: Array) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(c, poly):
			return true
	return false


## For the HUD.
func status() -> String:
	if mode == FIT_BOX:
		if is_open:
			return "It fits the sizer: the tunnel is open."
		return "Sizer: the paper must fit inside the glowing box (%d%% of its corners are in%s)" % [
			roundi(coverage * 100.0), "" if stick_out == INF or stick_out <= 0.0 else ", it sticks out by %.1f m" % stick_out]
	if is_open:
		return "Outline filled: the door is open."
	return "Outline %d%% filled (need %d%%), %d%% spilling outside (max %d%%)" % [
		roundi(coverage * 100.0), roundi(MIN_COVER * 100.0), roundi(spill * 100.0), roundi(MAX_SPILL * 100.0)]
