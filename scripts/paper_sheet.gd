class_name PaperSheet
extends AnimatableBody3D
## A giant sheet of paper lying in the world that can be folded.
##
## The sheet is stored as flat convex "facets" (polygons in sheet-local XZ
## space, units are metres). Each facet has a stacking `layer`, a `flipped`
## flag (showing the back of the paper) and an `elev` (how many slabs it sits
## on). Folding along a line splits every facet by that line and mirrors the
## grabbed side over it, onto the top of the stack. The result is just a new
## facet list, so folds persist until undone. Each facet becomes a thick slab
## with its own collision, and the whole sheet is an AnimatableBody3D so it can
## be slid around carrying anyone standing on it.

signal folded ## a fold was committed (or undone) and the collision changed

const THICKNESS := 0.5
const MIN_FOLD_LENGTH := 1.5
const HANDLE_MERGE_DIST := 0.6
const SWING_SPEED := 2.4 ## fold progress per second
const OVERLAP_EPS := 0.05

const FRONT_COLOR := Color(0.97, 0.95, 0.86)
const BACK_COLOR := Color(0.45, 0.65, 0.95)


class Facet:
	var pts: PackedVector2Array
	var layer: int
	var flipped: bool
	var elev: int

	func _init(p: PackedVector2Array, l: int, f: bool, e: int = 0) -> void:
		pts = p
		layer = l
		flipped = f
		elev = e

	func clone() -> Facet:
		return Facet.new(pts.duplicate(), layer, flipped, elev)


var paper_size := Vector2(18, 12)
var facets: Array = [] ## Array[Facet]
var fold_owner = null ## the player currently dragging a fold, if any

var _history: Array = []
var _mesh_instance: MeshInstance3D
var _crease: MeshInstance3D
var _material: StandardMaterial3D
var _shapes: Array = []

# Fold animation: the flap swings over the crease. `_anim_t` runs 0..1.
var _anim_active := false
var _anim_committed := false
var _anim_t := 0.0
var _anim_target := 0.0
var _anim_src: Array = []
var _anim_g := Vector2.ZERO
var _anim_c := Vector2.ZERO
var _model: Dictionary = {}


func _init() -> void:
	sync_to_physics = true
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.9
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	_crease = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.06, 40.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.45, 0.15)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = glow
	_crease.mesh = box
	_crease.visible = false
	_crease.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crease)


func setup(size: Vector2) -> void:
	paper_size = size
	reset_paper()


func reset_paper() -> void:
	var h := paper_size * 0.5
	var rect := PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)
	])
	facets = [Facet.new(rect, 0, false, 0)]
	_history.clear()
	_end_anim()
	fold_owner = null
	_rebuild_collision()
	_build_static()


# --- Fold model --------------------------------------------------------------

## Returns {facets, kept, moved}: a new facet list where everything on g's side
## of the fold line has been mirrored over it so g lands on c. `moved` lists the
## flap pieces with their pre-fold shape (for animating the swing). `src` is
## left untouched.
static func fold_facets(src: Array, g: Vector2, c: Vector2) -> Dictionary:
	var d := c - g
	if d.length() < 0.001:
		var same := clone_facets(src)
		return {"facets": same, "kept": same, "moved": []}
	var n := d.normalized()
	var mid := (g + c) * 0.5
	var top := 0
	for item in src:
		top = maxi(top, (item as Facet).layer)

	var kept: Array = []
	var flaps: Array = []
	var moved: Array = []
	for item in src:
		var f: Facet = item
		var keep := PaperGeometry.clip_half_plane(f.pts, mid, n, true)
		if keep.size() >= 3:
			kept.append(Facet.new(keep, f.layer, f.flipped))
		var moving := PaperGeometry.clip_half_plane(f.pts, mid, n, false)
		if moving.size() >= 3:
			var mirrored := PackedVector2Array()
			for p in moving:
				var s := (p - mid).dot(n)
				mirrored.append(p - 2.0 * s * n)
			mirrored.reverse()
			# Flipping a stack reverses its order and lays it above everything.
			var to := Facet.new(mirrored, top + 1 + (top - f.layer), not f.flipped)
			flaps.append(to)
			moved.append({"from_pts": moving, "from_elev": f.elev, "flipped": f.flipped, "to": to})

	var out: Array = kept.duplicate()
	out.append_array(flaps)
	out.sort_custom(func(a: Facet, b: Facet) -> bool: return a.layer < b.layer)
	for i in out.size():
		(out[i] as Facet).layer = i
	compute_elevations(out)
	return {"facets": out, "kept": kept, "moved": moved}


## `list` must be sorted by layer. A facet rests on the highest slab it overlaps.
static func compute_elevations(list: Array) -> void:
	for i in list.size():
		var f: Facet = list[i]
		f.elev = 0
		for j in i:
			var below: Facet = list[j]
			if PaperGeometry.overlap_area(f.pts, below.pts) > OVERLAP_EPS:
				f.elev = maxi(f.elev, below.elev + 1)


static func clone_facets(src: Array) -> Array:
	var out: Array = []
	for item in src:
		out.append((item as Facet).clone())
	return out


# --- Fold interaction ---------------------------------------------------------

func is_animating() -> bool:
	return _anim_active


## 0..1 progress of the flap swing, for hand animation.
func fold_progress() -> float:
	return smoothstep(0.0, 1.0, _anim_t) if _anim_active else 0.0


func begin_fold(owner) -> bool:
	if fold_owner != null or _anim_active:
		return false
	fold_owner = owner
	return true


func update_fold(g: Vector2, c: Vector2) -> void:
	if (c - g).length() >= MIN_FOLD_LENGTH:
		if not _anim_active:
			_anim_active = true
			_anim_committed = false
			_anim_t = 0.0
			_anim_src = clone_facets(facets)
		_anim_g = g
		_anim_c = c
		_model = fold_facets(_anim_src, g, c)
		_anim_target = 1.0
	elif _anim_active:
		_anim_target = 0.0


func finish_fold(g: Vector2, c: Vector2) -> bool:
	update_fold(g, c)
	fold_owner = null
	if (c - g).length() >= MIN_FOLD_LENGTH and _anim_active:
		_history.append(clone_facets(facets))
		facets = _model.facets
		_anim_committed = true
		_anim_target = 1.0
		_rebuild_collision()
		folded.emit()
		return true
	_anim_target = 0.0
	return false


func cancel_fold() -> void:
	fold_owner = null
	if _anim_active and not _anim_committed:
		_anim_target = 0.0


func undo() -> void:
	if fold_owner != null or _anim_active or _history.is_empty():
		return
	facets = _history.pop_back()
	_rebuild_collision()
	_build_static()
	folded.emit()


func _end_anim() -> void:
	_anim_active = false
	_anim_committed = false
	_anim_t = 0.0
	_anim_target = 0.0
	_model = {}
	_crease.visible = false


# --- Queries ---------------------------------------------------------------

func local_bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for item in facets:
		for p in (item as Facet).pts:
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2(lo, hi - lo)


## Height of the top paper surface above the sheet origin at a world point, or
## -1 when there is no paper there.
func top_at(world: Vector3) -> float:
	var l := Vector2(world.x - global_position.x, world.z - global_position.z)
	var best := -1.0
	for item in facets:
		var f: Facet = item
		if Geometry2D.is_point_in_polygon(l, f.pts):
			best = maxf(best, (f.elev + 1) * THICKNESS)
	return best


## Grabbable points: every facet corner and edge midpoint that is not buried
## under a higher layer. Returns Array of {pos: Vector2, layer: int, y: float}.
func get_handles() -> Array:
	var handles: Array = []
	for item in facets:
		var f: Facet = item
		var n := f.pts.size()
		for i in n:
			var a := f.pts[i]
			var b := f.pts[(i + 1) % n]
			_add_handle(handles, a, f)
			_add_handle(handles, (a + b) * 0.5, f)
	return handles


func _add_handle(handles: Array, p: Vector2, f: Facet) -> void:
	for item in facets:
		var other: Facet = item
		if other.layer > f.layer and Geometry2D.is_point_in_polygon(p, other.pts):
			return
	var y := (f.elev + 1) * THICKNESS
	for h in handles:
		if (h.pos as Vector2).distance_to(p) < HANDLE_MERGE_DIST:
			if f.layer > h.layer:
				h.pos = p
				h.layer = f.layer
				h.y = y
			return
	handles.append({"pos": p, "layer": f.layer, "y": y})


## Closest grabbable point to a sheet-local position, or null. `ref_y` is the
## player's feet height relative to the sheet.
func nearest_handle(local: Vector2, ref_y: float, radius: float):
	var best = null
	var best_d := radius
	for h in get_handles():
		if absf(h.y - ref_y) > 2.4:
			continue
		var d := (h.pos as Vector2).distance_to(local)
		if d < best_d:
			best = h
			best_d = d
	return best


# --- Collision ---------------------------------------------------------------

func _rebuild_collision() -> void:
	for s in _shapes:
		remove_child(s)
		s.queue_free()
	_shapes.clear()
	for item in facets:
		var f: Facet = item
		var pts := PackedVector3Array()
		var y0 := f.elev * THICKNESS
		for p in f.pts:
			pts.append(Vector3(p.x, y0, p.y))
			pts.append(Vector3(p.x, y0 + THICKNESS, p.y))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var node := CollisionShape3D.new()
		node.shape = shape
		add_child(node)
		_shapes.append(node)


# --- Rendering ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not _anim_active:
		return
	_anim_t = move_toward(_anim_t, _anim_target, SWING_SPEED * delta)
	if _anim_committed and _anim_t >= 1.0:
		_end_anim()
		_build_static()
		return
	if not _anim_committed and _anim_target == 0.0 and _anim_t <= 0.0:
		_end_anim()
		_build_static()
		return
	_build_anim()


func _build_static() -> void:
	var st := _begin_mesh()
	for item in facets:
		var f: Facet = item
		_add_slab(st, f.pts, f.elev * THICKNESS, f.flipped, Transform3D.IDENTITY)
	_mesh_instance.mesh = st.commit()


func _build_anim() -> void:
	var eased := smoothstep(0.0, 1.0, _anim_t)
	var n2 := (_anim_c - _anim_g).normalized()
	var mid := (_anim_g + _anim_c) * 0.5
	var n3 := Vector3(n2.x, 0.0, n2.y)
	var axis := Vector3.UP.cross(n3)
	var pivot_y := 0.0
	for item in _anim_src:
		pivot_y = maxf(pivot_y, ((item as Facet).elev + 1) * THICKNESS)
	var p3 := Vector3(mid.x, pivot_y, mid.y)
	var rot := Basis(axis, PI * eased)

	var st := _begin_mesh()
	for item in _model.kept:
		var f: Facet = item
		_add_slab(st, f.pts, f.elev * THICKNESS, f.flipped, Transform3D.IDENTITY)
	for mv in _model.moved:
		var to: Facet = mv.to
		var y0: float = mv.from_elev * THICKNESS
		# Rotating by pi flips y about the pivot; dy lands the flap on its final slab.
		var dy := ((to.elev + 1) * THICKNESS - (2.0 * pivot_y - y0)) * eased
		var xf := Transform3D(rot, p3 + Vector3(0, dy, 0) - rot * p3)
		_add_slab(st, mv.from_pts, y0, mv.flipped, xf)
	_mesh_instance.mesh = st.commit()

	# Crease marker while a fold is being dragged.
	var showing := fold_owner != null and _anim_target == 1.0
	_crease.visible = showing
	if showing:
		var perp := Vector3(-n2.y, 0.0, n2.x)
		_crease.transform = Transform3D(
			Basis(Vector3.UP, atan2(perp.x, perp.z)),
			Vector3(mid.x, pivot_y + 0.12, mid.y))


func _begin_mesh() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material)
	return st


## Adds an extruded convex polygon. The top face shows the front (or back, when
## flipped) of the paper and the underside shows the opposite side, so a flap
## swung over reveals the right colour.
func _add_slab(st: SurfaceTool, pts: PackedVector2Array, y0: float, flipped: bool, xf: Transform3D) -> void:
	var count := pts.size()
	if count < 3:
		return
	var top_color := BACK_COLOR if flipped else FRONT_COLOR
	var bottom_color := FRONT_COLOR if flipped else BACK_COLOR
	var side_color := top_color.darkened(0.3)
	var y1 := y0 + THICKNESS

	var tops: Array = []
	var bottoms: Array = []
	var cen := Vector2.ZERO
	for p in pts:
		tops.append(xf * Vector3(p.x, y1, p.y))
		bottoms.append(xf * Vector3(p.x, y0, p.y))
		cen += p
	cen /= count

	for i in range(1, count - 1):
		_tri(st, tops[0], tops[i], tops[i + 1], xf.basis * Vector3.UP, top_color)
		_tri(st, bottoms[0], bottoms[i], bottoms[i + 1], xf.basis * Vector3.DOWN, bottom_color)
	for i in count:
		var j := (i + 1) % count
		var m := (pts[i] + pts[j]) * 0.5 - cen
		var out := xf.basis * Vector3(m.x, 0.0, m.y).normalized()
		_tri(st, tops[i], tops[j], bottoms[j], out, side_color)
		_tri(st, tops[i], bottoms[j], bottoms[i], out, side_color)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	st.set_color(color)
	st.set_normal(outward)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(outward)
	st.add_vertex(b)
	st.set_color(color)
	st.set_normal(outward)
	st.add_vertex(c)
