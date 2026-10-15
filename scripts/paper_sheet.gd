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
const CONTACT_SLOP := 0.02 ## overlaps shallower than this (a loaded sheet settling) don't block folds

var paper_size := Vector2(18, 12)
var facets: Array = [] ## Array[PaperModel.Facet]
var fold_owner = null ## the player currently dragging a fold, if any
var fold_status := "" ## why the current drag can't fold, for the HUD

var _history: Array = []
var _offsets: Array = []
var _preview: Dictionary = {}
var _drag_side := 0 ## which side of its paper the flap being folded is on (+1 above, -1 below, 0 not far over yet)
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
var _plan_key := [] ## inputs of the current preview, to skip re-planning when idle
var _collapse_cache := {} ## collapse search for the current grab (it's costly)
var fold_choice := 0 ## which of several equally good collapses is shown
var fold_choices := 0 ## how many there are (for the HUD)
var _plan_msec := 0 ## when the preview was last planned (live previews run at ~30 Hz)
var _handles: Array = [] ## cached grab points (rebuilt when the paper or its "up" changes)
var _handles_up := Vector3.ZERO


func _init() -> void:
	continuous_cd = true
	contact_monitor = true # lets the slide control tell a resting sheet from a falling one
	max_contacts_reported = 4
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
	_drag_side = 0
	return true


## g and t are sheet-local: the grabbed point and where the hands hold it now.
## `mode` is one of PaperModel's FOLD_* kinds.
func update_fold(facet: int, g: Vector3, t: Vector3, mode: int = PaperModel.FOLD_NORMAL, force := false, choice := 0) -> void:
	if mode != PaperModel.FOLD_NORMAL:
		var n: Vector3 = facets[facet].normal()
		t -= n * n.dot(t - g) # reverse folds are flat
	# Planning is costly; only redo it when the hands actually moved, and at
	# most ~30 times a second for the live preview.
	if not force:
		if _plan_key.size() == 5 and _plan_key[0] == facet and _plan_key[2] == mode and _plan_key[4] == choice \
				and (_plan_key[1] as Vector3).distance_to(t) < 0.01 and _same_pose(_plan_key[3]):
			return
		if _plan_key.size() == 5 and _plan_key[4] == choice and Time.get_ticks_msec() - _plan_msec < 33:
			return
	_plan_key = [facet, t, mode, global_transform, choice]
	_plan_msec = Time.get_ticks_msec()
	var snapped := t
	if mode == PaperModel.FOLD_COLLAPSE:
		# Which creases can collapse together only depends on the grab, so the
		# search runs once per grab; dragging just picks among its results.
		if _collapse_cache.get("facet", -1) != facet:
			_collapse_cache = PaperModel.collapse_states(facets, facet, g)
			_collapse_cache.facet = facet
		_preview = PaperModel.plan_collapse(facets, facet, g, t, up_local(), _collapse_cache, choice)
		fold_choice = _preview.choice
		fold_choices = _preview.choices
	else:
		snapped = PaperModel.snap_target(facets, facet, g, t)
		_preview = PaperModel.plan_fold(facets, facet, g, snapped, up_local(), mode)
		fold_choices = 0
		# The flap moves continuously with the hands: once it's over on one side
		# of the paper, hands pushed on through the paper's plane just press it
		# flat there rather than flipping it through the paper to the other side.
		if _preview.ok and _preview.swept and _drag_side != 0 and absf(_preview.theta) > PI * 0.5 \
				and (1 if _preview.above else -1) != _drag_side:
			_preview = PaperModel.plan_fold(facets, facet, g, snapped, up_local(), mode, -PI * signf(_preview.theta))
	var note := ""
	if _preview.ok and _blocked_by_world(_preview):
		var plan := _preview
		_preview = _unblocked(facet, g, snapped, mode, plan)
		note = "" if not _preview.ok else _preview.get("note", "")
	fold_status = _preview.reason if not _preview.ok else note
	if _preview.ok and _preview.get("swept", false):
		_drag_side = 0 if absf(_preview.theta) < PI * 0.5 else (1 if _preview.above else -1)
	_build_mesh(_preview.facets if _preview.ok else facets)
	_show_crease(_preview)


func finish_fold(facet: int, g: Vector3, t: Vector3, mode: int = PaperModel.FOLD_NORMAL, choice := 0) -> bool:
	update_fold(facet, g, t, mode, true, choice) # always plan exactly what was released
	var ok: bool = _preview.ok
	if ok:
		_history.append(PaperModel.clone_all(facets))
		facets = _preview.facets
		PaperModel.remember_creases(facets)
	fold_owner = null
	_preview = {}
	_plan_key = []
	fold_status = ""
	_refresh()
	if ok:
		folded.emit()
	return ok


func cancel_fold() -> void:
	fold_owner = null
	_preview = {}
	_plan_key = []
	fold_status = ""
	_refresh()


func can_undo() -> bool:
	return not _history.is_empty()


## Unfolds the last fold, unless the paper has no room to swing back out
## (e.g. the sheet now rests where the old flap would go).
func undo() -> bool:
	if is_busy() or _history.is_empty():
		return false
	var restored: Array = _history.back()
	if _blocked_by_world({"moved": restored, "swept": false}):
		return false
	facets = _history.pop_back()
	_refresh()
	return true


## A fold whose flap would run into something: like real paper, swing it the
## other way if it was nearly flat anyway (e.g. hands a touch below the paper on
## the floor), otherwise let it come to rest against whatever is in the way.
func _unblocked(facet: int, g: Vector3, t: Vector3, mode: int, plan: Dictionary) -> Dictionary:
	var blocked := plan.duplicate()
	blocked.ok = false
	blocked.reason = "blocked by the ground or something solid"
	if not plan.swept:
		return blocked
	var theta: float = plan.theta
	var clear := _clear_fraction(plan)
	if clear < 0.02 and absf(theta) > deg_to_rad(150.0):
		var over := PaperModel.plan_fold(facets, facet, g, t, up_local(), mode, -PI * signf(theta))
		if over.ok and not _blocked_by_world(over):
			return over
	if absf(theta * clear) >= PaperModel.MIN_ANGLE:
		var rest := PaperModel.plan_fold(facets, facet, g, t, up_local(), mode, theta * clear)
		if rest.ok and not _blocked_by_world(rest):
			rest.note = "resting against something solid"
			return rest
	return blocked


## How far along its swing (0..1) a fold's flap gets before touching anything.
func _clear_fraction(plan: Dictionary) -> float:
	const STEPS := 8
	var lo := 0.0
	var hi := -1.0
	for k in range(1, STEPS + 1):
		var s := float(k) / STEPS
		if _hits_world(plan, s, global_transform):
			hi = s
			break
		lo = s
	if hi < 0.0:
		return 1.0
	for i in 6: # narrow down the contact angle
		var mid := (lo + hi) * 0.5
		if _hits_world(plan, mid, global_transform):
			hi = mid
		else:
			lo = mid
	return maxf(lo - deg_to_rad(1.0) / maxf(absf(plan.theta), 0.01), 0.0)


## True if the sheet has barely moved since `xf` (a resting body jitters a little).
func _same_pose(xf: Transform3D) -> bool:
	var now := global_transform
	return now.origin.distance_to(xf.origin) < 0.005 and now.basis.x.dot(xf.basis.x) > 0.99999 \
		and now.basis.z.dot(xf.basis.z) > 0.99999


## Would the paper that moves in `plan` hit anything solid (the ground, the
## ledge, another sheet)? Normal folds are checked along their swing, so you
## can't fold a flap down through the floor; players don't block folds.
func _blocked_by_world(plan: Dictionary, pose: Transform3D = global_transform) -> bool:
	if not is_inside_tree():
		return false
	for s in ([0.25, 0.5, 0.75, 1.0] if plan.swept else [1.0]):
		if _hits_world(plan, s, pose):
			return true
	return false


## Does the moving paper of `plan`, `s` of the way through its swing, overlap
## anything solid by more than CONTACT_SLOP? (Players don't count, and a sheet
## pressed a few millimetres into the ground under someone's weight is fine.)
func _hits_world(plan: Dictionary, s: float, pose: Transform3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var exclude: Array[RID] = [get_rid()]
	for p in get_tree().get_nodes_in_group("players"):
		exclude.append((p as CollisionObject3D).get_rid())
	query.exclude = exclude
	query.collision_mask = collision_mask
	query.transform = pose
	var back := Transform3D.IDENTITY
	if plan.swept and s < 1.0:
		var rot := Basis(plan.axis_d, plan.theta * (s - 1.0))
		back = Transform3D(rot, plan.axis_a - rot * plan.axis_a)
	for item in plan.moved:
		query.shape = _probe(item, back)
		var contacts := space.collide_shape(query, 16)
		for i in range(0, contacts.size() - 1, 2):
			if (contacts[i] as Vector3).distance_to(contacts[i + 1]) > CONTACT_SLOP:
				return true
	return false


## A thin, slightly shrunk copy of a facet's mid-surface for overlap tests, so
## paper resting on the ground or touching at its hinge doesn't count as a hit.
func _probe(f: PaperModel.Facet, back: Transform3D) -> ConvexPolygonShape3D:
	var n := back.basis * f.normal() * 0.005
	var pts := PackedVector3Array()
	for p in PaperGeometry.inset(f.pts, 0.05):
		var q := back * f.at(p)
		pts.append(q + n)
		pts.append(q - n)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


# --- Whole-sheet moves -------------------------------------------------------

## Flips the sheet over about a horizontal world axis, keeping it resting at
## the same height.
## Both are refused if the paper would end up inside something solid.
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
	if _blocked_by_world({"moved": facets, "swept": false}, target):
		return # no room to turn/flip here
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
		if fold_owner != null:
			cancel_fold()
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
	if _push_velocity != null and state.get_contact_count() == 0:
		_push_velocity = null # can't steer a sheet that's in free fall
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
	var up := up_local()
	if _handles_up.dot(up) < 0.999:
		_handles = PaperModel.handles(facets, _offsets, up)
		_handles_up = up
	for h in _handles:
		var w := to_global(h.shown)
		var d := w.distance_to(from_world)
		if d < best_d:
			best_d = d
			best = {"world": w, "local": h.local, "facet": h.facet, "dist": d}
	return best


# --- Building ----------------------------------------------------------------

func _refresh() -> void:
	_collapse_cache = {}
	fold_choices = 0
	_offsets = PaperModel.stack_offsets(facets)
	_handles_up = Vector3.ZERO # grab points need rebuilding
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
	var moved: Array = _preview.get("moved", []) if not _preview.is_empty() else []
	var offsets := _offsets if list == facets else PaperModel.stack_offsets(list, moved)
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
