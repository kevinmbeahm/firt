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
const VALLEY_COLOR := Color(0.2, 0.32, 0.75) ## printed crease to fold toward you
const MOUNTAIN_COLOR := Color(0.78, 0.25, 0.2) ## printed crease to fold away
const PRINT_WIDTH := 0.1
const TWEEN_TIME := 0.4
const AREAL_DENSITY := 0.6 ## kg per square metre of paper (it's giant paper)
const SLIDE_ACCEL := 12.0
const LOST_Y := -25.0 ## below this the sheet is lost in the void and respawns
const CARRY_MAX_SPEED := 4.0 ## m/s: how fast a carried sheet follows the hands
const CARRY_MAX_RISE := 1.0 ## m/s: ...rises or drops
const CARRY_MAX_TURN := 1.2 ## rad/s: ...and turns
const CARRY_STRETCH := 1.5 ## carriers' hands this much further apart (or closer) than their grips and it slips
const HOOK_TOL := 0.35 ## a crease this close to a cable along HOOK_MIN of its length hooks onto it
const HOOK_MIN := 1.0
const HOOK_ANGLE := deg_to_rad(15.0) ## ...and running this close to parallel with it
const HOOK_KG_PER_M := 50.0 ## what each metre of crease on the cable holds
const RIDER_KG := 70.0
const HOOK_DRAG := 0.08 ## rope friction and air: slows a sliding sheet (v squared)
const HOOK_SWING_DAMP := 1.5
const PAPER_FLOAT := 3.0 ## kg per square metre a sheet lying in water holds up on its own (a raft)
const WATER_GRIP := 1.0 ## per second: how quickly a floating sheet takes up the current's speed
const WATER_HEAVE_DAMP := 30.0 ## ...up and down
const WATER_SPIN_DAMP := 20.0
const PADDLE_SPEED := 0.5 ## share of the slide speed you paddle a floating sheet at
const PADDLE_ACCEL := 2.0
const CONTACT_SLOP := 0.02 ## overlaps shallower than this (a loaded sheet settling) don't block folds

var paper_size := Vector2(18, 12)
var printed_creases: Array = [] ## {a, b, mv} lines printed on the paper (see setup)
var facets: Array = [] ## Array[PaperModel.Facet]
var fold_owner = null ## the player currently dragging a fold, if any
var fold_status := "" ## why the current drag can't fold, for the HUD

var _history: Array = []
var _offsets: Array = []
var _preview: Dictionary = {}
var _held_still := false ## frozen for the duration of a fold drag or a carry
var carriers: Array = [] ## the two beans carrying it, if it's being carried
var _rider_vel := {} ## (carrying) prop -> the paper's velocity under it last frame
var _carry_local: Array = [] ## where each carrier holds it (sheet-local)
var _carry_basis := Basis.IDENTITY ## its orientation when they picked it up
var hook_cable: Cable = null ## the cable it hangs on, if any
var hook_len := 0.0 ## metres of crease on the cable
var hook_speed := 0.0 ## sliding along the cable, m/s (+ toward its end)
var hook_note := "" ## why it last came off a cable, for the HUD
var riders: Array = [] ## beans hanging on to it
var _hook_s := 0.0 ## where its crease's middle is along the cable, metres
var _hook_mid := Vector3.ZERO ## the hooked crease's middle, sheet-local
var _hook_ends: Array = [] ## ...and its two ends: the handles you hang on by
var _hook_half := 0.0 ## half the hooked crease's length
var _hook_basis := Basis.IDENTITY ## its orientation with the crease along the cable, before swinging
var _swing := 0.0 ## how far it has swung about the cable from there, radians
var _swing_v := 0.0
var _swing_hang := 0.0 ## the swing at which its centre of mass is right below the cable
var _swing_r := 1.0 ## how far its centre of mass is from the cable
var water: Water = null ## the water it's floating in, if any
var swamped := false ## water got in over the rim (or through a gap): its hull holds nothing up
var dry_volume := 0.0 ## the dry space its hull keeps under the waterline, m^3
var _hull: Hull = null
var _dry_center := Vector3.ZERO ## (sheet-local)
var _dry_frame := 0
var _out_of_water := 0.0
var _sunk := 0.0
var _wet := 0.0
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


## `printed` crease lines, each {a: Vector2, b: Vector2, mv: +1 valley / -1
## mountain} in paper coordinates (centred, metres, paper y = sheet -Z), are
## drawn on the paper and remembered as creases, so folds snap to them and
## collapses prefer folding them the printed way.
func setup(size: Vector2, printed: Array = []) -> void:
	paper_size = size
	printed_creases = printed
	reset_paper()


func reset_paper() -> void:
	if hook_cable != null:
		unhook()
	if not carriers.is_empty():
		end_carry()
	facets = PaperModel.make_sheet(paper_size, printed_creases)
	_history.clear()
	fold_owner = null
	_let_go()
	_preview = {}
	_refresh()


func is_busy() -> bool:
	return fold_owner != null or not carriers.is_empty() or hook_cable != null or _tween_t < 1.0


# --- Carrying ------------------------------------------------------------------
# Two beans holding one sheet carry it between them (kinematically, for now):
# it keeps its shape and hangs between their hands, turning to follow them and
# tilting when one holds their end higher than the other.

## Whether bean `p` can take hold of this sheet as the second carrier (someone
## else is already holding it mid-fold).
func can_join_carry(p) -> bool:
	return fold_owner != null and fold_owner != p and carriers.is_empty() and fold_owner.grabbing


## The bean folding the sheet and bean `b` (grabbing sheet-local point
## `b_local`) now carry it together; the fold in progress is dropped.
func start_carry(b, b_local: Vector3) -> void:
	var a = fold_owner
	var a_local: Vector3 = a._grab_local
	fold_owner = null
	_preview = {}
	_plan_key = []
	fold_status = ""
	_build_mesh(facets)
	_crease.visible = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_held_still = true # let go of on end_carry
	carriers = [a, b]
	_rider_vel = {}
	_carry_local = [a_local, b_local]
	_carry_basis = global_basis
	a.begin_carry(self, to_global(a_local))
	b.begin_carry(self, to_global(b_local))


## Both carriers let go; the sheet (and whatever's in it) drops from where it is.
func end_carry() -> void:
	var was: Array = carriers
	carriers = []
	_carry_local = []
	for p in was:
		p.end_carry()
	_let_go()


## Where the sheet hangs between the carriers' hands `h1`, `h2` (world): the
## grabbed points go to the middle of the hands, turned to face along them
## and tilted by the difference in their height.
func _carry_pose(h1: Vector3, h2: Vector3) -> Transform3D:
	var l1: Vector3 = _carry_local[0]
	var l2: Vector3 = _carry_local[1]
	var d0: Vector3 = _carry_basis * (l2 - l1)
	var d := h2 - h1
	var flat0 := Vector3(d0.x, 0.0, d0.z)
	var flat := Vector3(d.x, 0.0, d.z)
	var basis := _carry_basis
	if flat0.length() > 0.01 and flat.length() > 0.01:
		var yaw := flat0.signed_angle_to(flat, Vector3.UP)
		basis = Basis(Vector3.UP, yaw) * basis
		var tilt := atan2(d.y, flat.length()) - atan2(d0.y, flat0.length())
		var side := Vector3.UP.cross(flat).normalized()
		basis = Basis(side, -tilt) * basis
	var mid_hands := (h1 + h2) * 0.5
	return Transform3D(basis, mid_hands - basis * ((l1 + l2) * 0.5))


func _update_carry() -> void:
	var h1: Vector3 = carriers[0].carry_hands()
	var h2: Vector3 = carriers[1].carry_hands()
	var span: float = (_carry_local[1] - _carry_local[0]).length()
	if absf(h1.distance_to(h2) - span) > CARRY_STRETCH:
		end_carry() # pulled apart (or pushed together) too far: it slips out of their hands
		return
	var pose := _ease_toward(global_transform, _carry_pose(h1, h2))
	# Solid things stop it (it can't be lowered into the ground or swung
	# through a wall); the carriers' hands go on and it slips if they pull too far.
	if not _hits_world({"moved": facets, "swept": false}, 1.0, pose):
		_carry_riders(global_transform, pose)
		global_transform = pose


## The carried sheet follows the hands smoothly: arms are soft, so a carrier
## stepping up a ledge doesn't jerk it (and fling out what's in it).
func _ease_toward(from: Transform3D, to: Transform3D) -> Transform3D:
	var dt := get_physics_process_delta_time()
	var flat_from := Vector3(from.origin.x, 0.0, from.origin.z)
	var origin := flat_from.move_toward(Vector3(to.origin.x, 0.0, to.origin.z), CARRY_MAX_SPEED * dt)
	origin.y = move_toward(from.origin.y, to.origin.y, CARRY_MAX_RISE * dt)
	var q0 := from.basis.get_rotation_quaternion()
	var q1 := to.basis.get_rotation_quaternion()
	var angle := q0.angle_to(q1)
	var t := 1.0 if angle < 0.0001 else minf(1.0, CARRY_MAX_TURN * dt / angle)
	return Transform3D(Basis(q0.slerp(q1, t)), origin)


## Props resting in the carried paper speed up and slow down with it, as if
## friction held them: kinematic paper otherwise slides out from under a ball,
## which rolls out the back the moment the carriers set off. Tilt it and they
## still roll.
func _carry_riders(from: Transform3D, to: Transform3D) -> void:
	var box := AABB()
	var first := true
	for q in _all_points():
		if first:
			box = AABB(q, Vector3.ZERO)
			first = false
		else:
			box = box.expand(q)
	box = box.grow(0.1)
	box.position.y -= 0.5 # (the props sit on top of the paper)
	box.size.y += 1.0
	var inv := from.affine_inverse()
	var dt := get_physics_process_delta_time()
	var seen := {}
	for p in get_tree().get_nodes_in_group("props"):
		var prop: Prop = p
		if prop.holder != null:
			continue
		var local := inv * prop.global_position
		if not box.has_point(local):
			continue
		var v := (to * local - from * local) / dt
		v.y = 0.0
		var dv: Vector3 = v - _rider_vel.get(prop, Vector3.ZERO)
		prop.nudge(dv.limit_length(1.0))
		seen[prop] = v
	_rider_vel = seen


# --- Hanging on a cable (S7) -------------------------------------------------
# Carry a sheet up to a cable with a crease lying along it and it hooks on: it
# swings to hang below the cable and the carriers find themselves hanging on to
# it. Once someone hangs on it slides downhill; on its own, friction holds it.
# Each metre of crease on the cable holds HOOK_KG_PER_M: overload a short hook
# and it slips off.

func is_hooked() -> bool:
	return hook_cable != null


## The creases (edges where two facets meet at an angle), sheet-local:
## [[a, b], ...].
func crease_segments() -> Array:
	var out := []
	for i in facets.size():
		var fi: PaperModel.Facet = facets[i]
		for j in range(i + 1, facets.size()):
			var fj: PaperModel.Facet = facets[j]
			if fi.normal().dot(fj.normal()) > 0.999:
				continue
			var e := PaperModel.shared_edge(fi.pts, fj.pts)
			if e.size() < 2 or e[0].distance_to(e[1]) < 0.01:
				continue
			var off: Vector3 = (_offsets[i] + _offsets[j]) * 0.5
			out.append([fi.at(e[0]) + off, fi.at(e[1]) + off])
	return out


## A crease lying along a cable now: {cable, a, b, len}, or {}.
func _find_hook() -> Dictionary:
	var cables := get_tree().get_nodes_in_group("cables")
	if cables.is_empty():
		return {}
	for seg in crease_segments():
		var p0 := to_global(seg[0])
		var p1 := to_global(seg[1])
		var d := p1 - p0
		var n := int(ceil(d.length() / 0.1))
		if d.length() < HOOK_MIN:
			continue
		for c in cables:
			var cable: Cable = c
			if absf(d.normalized().dot(cable.dir())) < cos(HOOK_ANGLE):
				continue
			var run := 0.0
			var best := 0.0
			for k in n + 1:
				if cable.distance_to(p0 + d * (float(k) / n)) < HOOK_TOL:
					run += d.length() / n
					best = maxf(best, run)
				else:
					run = 0.0
			# It hooks once it lies along as much of the cable as it can (the
			# whole crease, or the whole of a short bar), give or take a bit.
			var full := minf(d.length(), cable.length())
			var overlap := absf(cable.along(p1) - cable.along(p0))
			if best >= HOOK_MIN and overlap >= full - 0.5:
				return {"cable": cable, "a": seg[0], "b": seg[1], "len": full}
	return {}


func _hook(h: Dictionary) -> void:
	var c: Cable = h.cable
	var a: Vector3 = h.a
	var b: Vector3 = h.b
	if (global_basis * (b - a)).dot(c.dir()) < 0.0:
		var t := a
		a = b
		b = t
	var held: Array = []
	for i in carriers.size():
		held.append([carriers[i], _carry_local[i]])
	carriers = []
	_carry_local = []
	for pair in held:
		pair[0].end_carry()
	hook_cable = c
	hook_len = h.len
	hook_speed = 0.0
	hook_note = ""
	_hook_mid = (a + b) * 0.5
	_hook_ends = [a, b]
	_hook_half = minf((b - a).length(), c.length()) * 0.5
	var along := (global_basis * (b - a)).normalized()
	_hook_basis = Basis(Quaternion(along, c.dir())) * global_basis
	_hook_s = _clamp_on_cable(c.along(to_global(_hook_mid)))
	_swing = 0.0
	_swing_v = 0.0
	# Where it comes to rest: its centre of mass right below the cable.
	var cd := c.dir()
	var arm := _hook_basis * (center_of_mass - _hook_mid)
	arm -= cd * arm.dot(cd)
	var down := Vector3.DOWN - cd * Vector3.DOWN.dot(cd)
	_swing_r = maxf(arm.length(), 0.3)
	_swing_hang = 0.0 if arm.length() < 0.05 else arm.signed_angle_to(down, cd)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_held_still = true # let go of on unhook
	for pair in held:
		add_rider(pair[0], pair[1])


## Slips off the cable (overloaded, or the room restarts): riders let go and it
## falls.
func unhook(note := "") -> void:
	hook_note = note
	var was := riders.duplicate()
	riders.clear()
	hook_cable = null
	for p in was:
		p.end_ride()
	_let_go()


## Bean `p` grabs the hooked sheet at sheet-local `local` and hangs on.
func add_rider(p, local: Vector3) -> bool:
	if hook_cable == null or riders.has(p):
		return false
	riders.append(p)
	p.begin_ride(self, local)
	return true


func remove_rider(p) -> void:
	riders.erase(p)


## The load it's carrying and what its hook holds, kg.
func hook_load() -> float:
	return mass + riders.size() * RIDER_KG


func hook_capacity() -> float:
	return hook_len * HOOK_KG_PER_M


## Keeps the whole hooked crease on the cable.
func _clamp_on_cable(s: float) -> float:
	var lo := _hook_half + 0.3
	var hi := hook_cable.length() - _hook_half - 0.3
	if lo > hi:
		return hook_cable.length() * 0.5
	return clampf(s, lo, hi)


func _hook_pose(s: float, swing: float) -> Transform3D:
	var basis := Basis(hook_cable.dir(), swing) * _hook_basis
	var on := hook_cable.point(s) + Vector3.UP * (Cable.RADIUS + PaperModel.THICKNESS)
	return Transform3D(basis, on - basis * _hook_mid)


func _update_hook(delta: float) -> void:
	if not is_instance_valid(hook_cable):
		unhook()
		return
	if hook_load() > hook_capacity():
		unhook("it slipped off the cable: %.1f m of crease holds %d kg, not %d" % [hook_len, roundi(hook_capacity()), roundi(hook_load())])
		return
	var cd := hook_cable.dir()
	if riders.is_empty():
		hook_speed = move_toward(hook_speed, 0.0, 3.0 * delta) # friction holds the paper alone
	else:
		hook_speed += (-cd.y * 9.8 - HOOK_DRAG * hook_speed * absf(hook_speed)) * delta
	var want := _hook_s + hook_speed * delta
	var s := _clamp_on_cable(want)
	if absf(s - want) > 1e-5:
		hook_speed = 0.0 # at the end of the cable
	_swing_v += (-9.8 / _swing_r * sin(_swing - _swing_hang) - HOOK_SWING_DAMP * _swing_v) * delta
	var swing := _swing + _swing_v * delta
	var plan := {"moved": facets, "swept": false}
	var pose := _hook_pose(s, swing)
	if not _hits_world(plan, 1.0, pose):
		_move_hooked(pose, s, swing)
		return
	# Something's in the way of the swing (the ground under a low cable): it
	# drags, swinging back up as far as it has to.
	_swing_v = 0.0
	var back := _swing
	for i in 12:
		pose = _hook_pose(s, back)
		if not _hits_world(plan, 1.0, pose):
			_move_hooked(pose, s, back)
			return
		back = move_toward(back, 0.0, 0.08)
	hook_speed = 0.0 # stuck


func _move_hooked(pose: Transform3D, s: float, swing: float) -> void:
	_hook_s = s
	_swing = swing
	global_transform = pose


## For the HUD.
func hook_status() -> String:
	if hook_cable != null:
		return "On the cable: %.1f m of crease holds %d kg (%d kg on it)" % [hook_len, roundi(hook_capacity()), roundi(hook_load())]
	return hook_note


## Back to where it started, with its folds (lost in the void, over a waterfall).
func respawn() -> void:
	if hook_cable != null:
		unhook()
	if not carriers.is_empty():
		end_carry()
	if fold_owner != null:
		cancel_fold()
	swamped = false
	_respawn = true
	sleeping = false


# --- Water (S5) ----------------------------------------------------------------
# Paper floats two ways: on the dry space a folded hull keeps under the
# waterline (Hull: water pours in over a rim or through a gap, and then it's
# swamped until it's out of the water again), and as a thin raft (a little lift
# per square metre of paper lying in the water). The water drags it along with
# its current and damps its bobbing. Sheet handling paddles it.

func _update_water(delta: float) -> void:
	if freeze:
		water = null
		return
	var box := world_box()
	var w := Water.find(get_tree(), global_position + box.get_center())
	if w == null or global_position.y + box.position.y > w.surface() + 0.05:
		water = null
		dry_volume = 0.0
		_out_of_water += delta
		if _out_of_water > 1.0:
			swamped = false
		return
	water = w
	_out_of_water = 0.0
	sleeping = false # (the water never stops pushing)
	var surf := w.surface()
	# Sunk without a trace: back to where it started.
	if global_position.y + box.end.y < surf - 0.3:
		_sunk += delta
		if _sunk > 2.0:
			_sunk = 0.0
			respawn()
			return
	else:
		_sunk = 0.0
	var g := Water.GRAVITY
	# A raft: each facet holds up a little where it lies in the water.
	var wet_area := 0.0
	for i in facets.size():
		var f: PaperModel.Facet = facets[i]
		var off: Vector3 = _offsets[i] if i < _offsets.size() else Vector3.ZERO
		var area := absf(PaperGeometry.signed_area(f.pts))
		var pts := Array(f.pts)
		pts.append(PaperGeometry.centroid(f.pts))
		var part := 0.0
		var at := Vector3.ZERO
		for q in pts:
			var p := to_global(f.at(q) + off)
			var k := clampf((surf - p.y) / 0.1 + 0.5, 0.0, 1.0)
			part += k
			at += p * k
		if part <= 0.0:
			continue
		at /= part
		part /= pts.size()
		wet_area += area * part
		apply_force(Vector3.UP * PAPER_FLOAT * area * part * g, at - global_position)
	# A hull: the dry space it keeps out.
	if _hull == null:
		_hull = Hull.build(facets, _offsets)
		_dry_frame = 0
	if _dry_frame % 3 == 0:
		var d := _hull.dry(global_transform, surf)
		if dry_volume > 0.5 and d.volume < dry_volume * 0.3:
			swamped = true # the water poured in
		dry_volume = d.volume
		_dry_center = to_local(d.center)
	_dry_frame += 1
	if not swamped and dry_volume > 0.0:
		apply_force(Vector3.UP * Water.DENSITY * dry_volume * g, to_global(_dry_center) - global_position)
	_wet = minf(wet_area / 4.0, 1.0) # (how firmly the water has hold of it, 0..1)
	apply_central_force(-Vector3.UP * linear_velocity.y * WATER_HEAVE_DAMP * wet_area)
	apply_torque(-angular_velocity * WATER_SPIN_DAMP * wet_area)


## For the HUD.
func water_status() -> String:
	if water == null:
		return ""
	if swamped:
		return "swamped: the water got in"
	if dry_volume > 0.05:
		return "afloat on %.1f m3 of dry hull" % dry_volume
	return "afloat as a raft"


func _ready() -> void:
	add_to_group("sheets")
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
	# Hold the sheet still while it's being folded (it can't be slid then
	# either): the preview stays put and walking onto it doesn't shove it.
	_held_still = not freeze
	if _held_still:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
	return true


## Lets the sheet move again after a fold drag ends.
func _let_go() -> void:
	if _held_still:
		_held_still = false
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


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
	_let_go()
	_preview = {}
	_plan_key = []
	fold_status = ""
	_refresh()
	if ok:
		folded.emit()
	return ok


func cancel_fold() -> void:
	fold_owner = null
	_let_go()
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
	for p in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("props"):
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
	_update_water(delta)
	if hook_cable != null:
		_update_hook(delta)
	elif carriers.size() == 2:
		_update_carry()
		if carriers.size() == 2:
			var h := _find_hook()
			if not h.is_empty():
				_hook(h)
	elif _tween_t < 1.0:
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
	if _push_velocity != null and water != null:
		# Afloat: paddle it, relative to the current.
		var want: Vector3 = water.current + _push_velocity * PADDLE_SPEED
		var h := Vector3(v.x, 0.0, v.z).move_toward(Vector3(want.x, 0.0, want.z), PADDLE_ACCEL * state.step)
		state.linear_velocity = Vector3(h.x, v.y, h.z)
		var w0 := state.angular_velocity
		state.angular_velocity = w0 - Vector3.UP * w0.dot(Vector3.UP)
		_push_velocity = null
		return
	if water != null and _wet > 0.0:
		# The current carries it. (Set directly, like paddling: beans standing
		# in it would otherwise hold it still by the friction under their feet.)
		var h := Vector3(v.x, 0.0, v.z)
		h += (Vector3(water.current.x, 0.0, water.current.z) - h) * minf(WATER_GRIP * _wet * state.step, 1.0)
		state.linear_velocity = Vector3(h.x, v.y, h.z)
		return
	if _push_velocity != null and state.get_contact_count() == 0:
		_push_velocity = null # can't steer a sheet that's in free fall
	if _push_velocity != null:
		# Drive the slide directly (it overrides friction, riders and all) while
		# gravity keeps acting on y, so a sheet pushed off an edge still falls.
		_slide = _slide.move_toward(_push_velocity, SLIDE_ACCEL * state.step)
		state.linear_velocity = Vector3(_slide.x, v.y, _slide.z)
		# Sliding doesn't spin it (turning is its own control), though it can
		# still tip over an edge.
		var w := state.angular_velocity
		state.angular_velocity = w - Vector3.UP * w.dot(Vector3.UP)
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
	if hook_cable != null:
		# Hanging on a cable, it's held by the ends of the hooked crease.
		for end in _hook_ends:
			var w := to_global(end)
			var d := w.distance_to(from_world)
			if d < best_d:
				best_d = d
				best = {"world": w, "local": end, "facet": 0, "dist": d}
		return best
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
	_hull = null


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
		for c in printed_creases:
			_add_printed_line(st, list[i], offsets[i], c)
	_mesh_instance.mesh = st.commit()


## A printed crease line where it crosses facet `f`, drawn on both faces just
## above the paper: blue for valley folds, red for mountain folds (as seen from
## the cream front; the back shows the opposite colour, as real paper would).
func _add_printed_line(st: SurfaceTool, f: PaperModel.Facet, offset: Vector3, c: Dictionary) -> void:
	var seg := PaperGeometry.clip_segment(c.a, c.b, f.pts)
	if seg.is_empty():
		return
	var n := f.normal()
	var along: Vector2 = (seg[1] - seg[0]).normalized()
	var side := f.xf.basis * Vector3(-along.y, along.x, 0.0).normalized() * (PRINT_WIDTH * 0.5)
	var valley: bool = int(c.get("mv", 1)) > 0
	for face in [1.0, -1.0]:
		var lift: Vector3 = n * face * (PaperModel.THICKNESS * 0.5 + 0.004)
		var p0: Vector3 = f.at(seg[0]) + offset + lift
		var p1: Vector3 = f.at(seg[1]) + offset + lift
		var col := VALLEY_COLOR if valley == (face > 0.0) else MOUNTAIN_COLOR
		_tri(st, p0 - side, p0 + side, p1 + side, n * face, col)
		_tri(st, p0 - side, p1 + side, p1 - side, n * face, col)


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
