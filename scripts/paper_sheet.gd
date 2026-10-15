class_name PaperSheet
extends RigidBody3D
## A giant sheet of thin paper in the world. Wraps a PaperModel facet list with
## rendering, collision and the interactive fold / flip / turn / slide controls.
## It is a real rigid body: it has weight, rests on whatever holds it up, tips
## and falls when it hangs too far over an edge, and carries anyone standing on
## it. Its mass and centre of mass are recomputed from the paper after every fold.

signal folded ## a fold was committed or undone

const FRONT_COLOR := Color(0.86, 0.83, 0.74)
const BACK_COLOR := Color(0.45, 0.65, 0.95)
const EDGE_COLOR := Color(0.4, 0.37, 0.33)
const TWEEN_TIME := 0.4
const AREAL_DENSITY := 0.6 ## kg per square metre of paper (it's giant paper)
const SLIDE_ACCEL := 12.0
const LOST_Y := -25.0 ## below this the sheet is lost in the void and respawns

var paper_size := Vector2(18, 12)
var facets: Array = [] ## Array[PaperModel.Facet]
var fold_owner = null ## the player currently dragging a fold, if any
var fold_status := "" ## why the current drag can't fold, for the HUD

var _history: Array = []
var _offsets: Array = []
var _preview: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _crease: MeshInstance3D
var _crease_ok_mat: StandardMaterial3D
var _crease_bad_mat: StandardMaterial3D
var _material: StandardMaterial3D
var _shapes: Array = []
var _tween_from := Transform3D.IDENTITY
var _tween_to := Transform3D.IDENTITY
var _tween_t := 1.0
var _push_velocity = null ## horizontal velocity requested by a player this frame
var _slide := Vector3.ZERO ## commanded slide velocity, ramps toward the request
var spawn_transform := Transform3D.IDENTITY
var _respawn := false


func _init() -> void:
	continuous_cd = true
	linear_damp = 0.2
	angular_damp = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.0
	physics_material_override = pm
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	_crease_ok_mat = _glow(Color(1.0, 0.45, 0.15))
	_crease_bad_mat = _glow(Color(0.95, 0.1, 0.1))
	_crease = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 40.0)
	_crease.mesh = box
	_crease.visible = false
	_crease.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crease)


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func setup(size: Vector2) -> void:
	paper_size = size
	reset_paper()


func reset_paper() -> void:
	facets = PaperModel.make_sheet(paper_size)
	_history.clear()
	fold_owner = null
	_preview = {}
	_refresh()


func is_busy() -> bool:
	return fold_owner != null or _tween_t < 1.0


func _ready() -> void:
	spawn_transform = global_transform


## Slide the sheet: called every physics frame a player holds the sheet control.
func push(velocity_xz: Vector3) -> void:
	_push_velocity = velocity_xz
	sleeping = false


## World "up" expressed in sheet-local space (the sheet may be flipped/turned).
func up_local() -> Vector3:
	return (global_basis.inverse() * Vector3.UP).normalized()


# --- Folding -----------------------------------------------------------------

func begin_fold(owner) -> bool:
	if is_busy():
		return false
	fold_owner = owner
	return true


## g and t are sheet-local: the grabbed point and where the hands hold it now.
## `mode` is one of PaperModel's FOLD_* kinds.
func update_fold(facet: int, g: Vector3, t: Vector3, mode: int = PaperModel.FOLD_NORMAL) -> void:
	if mode != PaperModel.FOLD_NORMAL:
		var n: Vector3 = facets[facet].normal()
		t -= n * n.dot(t - g) # reverse folds are flat
	var snapped := PaperModel.snap_target(facets, facet, g, t)
	_preview = PaperModel.plan_fold(facets, facet, g, snapped, up_local(), mode)
	fold_status = "" if _preview.ok else _preview.reason
	_build_mesh(_preview.facets if _preview.ok else facets)
	_show_crease(_preview)


func finish_fold(facet: int, g: Vector3, t: Vector3, mode: int = PaperModel.FOLD_NORMAL) -> bool:
	update_fold(facet, g, t, mode)
	var ok: bool = _preview.ok
	if ok:
		_history.append(PaperModel.clone_all(facets))
		facets = _preview.facets
	fold_owner = null
	_preview = {}
	fold_status = ""
	_refresh()
	if ok:
		folded.emit()
	return ok


func cancel_fold() -> void:
	fold_owner = null
	_preview = {}
	fold_status = ""
	_refresh()


func undo() -> bool:
	if is_busy() or _history.is_empty():
		return false
	facets = _history.pop_back()
	_refresh()
	folded.emit()
	return true


# --- Whole-sheet moves -------------------------------------------------------

## Flips the sheet over about a horizontal world axis, keeping it resting at
## the same height.
func flip(axis_world: Vector3) -> void:
	_rotate_about_center(Basis(axis_world.normalized(), PI))


func turn(angle: float) -> void:
	_rotate_about_center(Basis(Vector3.UP, angle))


func _rotate_about_center(rot: Basis) -> void:
	if is_busy():
		return
	var box := world_box()
	var center := global_position + box.get_center()
	var target := Transform3D(rot, center - rot * center) * global_transform
	# Keep the lowest point of the paper where it was (so it stays on the floor).
	var low_before := global_position.y + box.position.y
	var low_after := INF
	for p in _all_points():
		low_after = minf(low_after, (target * p).y)
	target.origin.y += low_before - low_after
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_tween_from = global_transform
	_tween_to = target
	_tween_t = 0.0


func _physics_process(delta: float) -> void:
	if _tween_t < 1.0:
		_tween_t = minf(_tween_t + delta / TWEEN_TIME, 1.0)
		var s := smoothstep(0.0, 1.0, _tween_t)
		global_transform = _tween_from.interpolate_with(_tween_to, s)
		if _tween_t >= 1.0:
			freeze = false
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	elif global_position.y < LOST_Y:
		_respawn = true
		sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _respawn:
		_respawn = false
		state.transform = spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
	var v := state.linear_velocity
	if _push_velocity != null:
		# Drive the slide directly (it overrides friction, riders and all) while
		# gravity keeps acting on y, so a sheet pushed off an edge still falls.
		_slide = _slide.move_toward(_push_velocity, SLIDE_ACCEL * state.step)
		state.linear_velocity = Vector3(_slide.x, v.y, _slide.z)
		_push_velocity = null
	else:
		_slide = Vector3(v.x, 0.0, v.z)


## Axis-aligned box of the paper relative to the sheet's position, in world axes.
func world_box() -> AABB:
	var b := global_basis
	var box := AABB()
	var first := true
	for p in _all_points():
		var q: Vector3 = b * p
		if first:
			box = AABB(q, Vector3.ZERO)
			first = false
		else:
			box = box.expand(q)
	return box


func _all_points() -> Array:
	var out: Array = []
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		for p in f.pts:
			out.append(f.at(p) + _offsets[i])
	return out


# --- Queries -----------------------------------------------------------------

## Closest grabbable corner/edge within `radius` of a world point, or null.
## Returns {world: Vector3, local: Vector3, facet: int, dist: float}.
func nearest_handle(from_world: Vector3, radius: float):
	var best = null
	var best_d := radius
	for h in PaperModel.handles(facets, _offsets, up_local()):
		var w := to_global(h.shown)
		var d := w.distance_to(from_world)
		if d < best_d:
			best_d = d
			best = {"world": w, "local": h.local, "facet": h.facet, "dist": d}
	return best


# --- Building ----------------------------------------------------------------

func _refresh() -> void:
	_offsets = PaperModel.stack_offsets(facets)
	_build_mesh(facets)
	_rebuild_collision()
	_update_mass()
	_crease.visible = false
	sleeping = false


## Mass from paper area; centre of mass from where the paper actually is now,
## so a fold that moves paper past an edge can tip the sheet over.
func _update_mass() -> void:
	var total := 0.0
	var com := Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		var area := absf(PaperGeometry.signed_area(f.pts))
		total += area
		com += (f.at(PaperGeometry.centroid(f.pts)) + _offsets[i]) * area
		for p in f.pts:
			var q: Vector3 = f.at(p) + _offsets[i]
			lo = lo.min(q)
			hi = hi.max(q)
	mass = maxf(total * AREAL_DENSITY, 1.0)
	center_of_mass = com / maxf(total, 0.001)
	var e := (hi - lo).max(Vector3(0.1, 0.1, 0.1))
	inertia = mass / 12.0 * Vector3(e.y * e.y + e.z * e.z, e.x * e.x + e.z * e.z, e.x * e.x + e.y * e.y)


func _rebuild_collision() -> void:
	for s in _shapes:
		remove_child(s)
		s.queue_free()
	_shapes.clear()
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		var n := f.normal() * (PaperModel.THICKNESS * 0.5)
		var pts := PackedVector3Array()
		for p in f.pts:
			var mid: Vector3 = f.at(p) + _offsets[i]
			pts.append(mid + n)
			pts.append(mid - n)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var node := CollisionShape3D.new()
		node.shape = shape
		add_child(node)
		_shapes.append(node)


func _build_mesh(list: Array) -> void:
	var offsets := _offsets if list == facets else PaperModel.stack_offsets(list)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material)
	for i in list.size():
		_add_slab(st, list[i], offsets[i])
	_mesh_instance.mesh = st.commit()


## A thin slab: cream on the paper's front, blue on its back.
func _add_slab(st: SurfaceTool, f: PaperModel.Facet, offset: Vector3) -> void:
	var count := f.pts.size()
	if count < 3:
		return
	var n := f.normal()
	var half := n * (PaperModel.THICKNESS * 0.5)
	var fronts: Array = []
	var backs: Array = []
	var cen := PaperGeometry.centroid(f.pts)
	for p in f.pts:
		var mid: Vector3 = f.at(p) + offset
		fronts.append(mid + half)
		backs.append(mid - half)
	for i in range(1, count - 1):
		_tri(st, fronts[0], fronts[i], fronts[i + 1], n, FRONT_COLOR)
		_tri(st, backs[0], backs[i], backs[i + 1], -n, BACK_COLOR)
	for i in count:
		var j := (i + 1) % count
		var m := (f.pts[i] + f.pts[j]) * 0.5 - cen
		var out := (f.xf.basis * Vector3(m.x, m.y, 0.0)).normalized()
		_tri(st, fronts[i], fronts[j], backs[j], out, EDGE_COLOR)
		_tri(st, fronts[i], backs[j], backs[i], out, EDGE_COLOR)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front faces; wind them to match the
	# normal so lighting isn't flipped on the visible side.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)


func _show_crease(plan: Dictionary) -> void:
	var d: Vector3 = plan.axis_d
	if d == Vector3.ZERO:
		_crease.visible = false
		return
	_crease.visible = true
	_crease.material_override = _crease_ok_mat if plan.ok else _crease_bad_mat
	var n: Vector3 = plan.plane_n
	_crease.transform = Transform3D(Basis.looking_at(d, n), plan.axis_a + PaperModel.canonical(n) * 0.06)
