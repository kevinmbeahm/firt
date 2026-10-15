class_name Player
extends CharacterBody3D
## A wobbly co-op "bean" in the spirit of Human Fall Flat: momentum-based
## movement, floppy limbs and arms that reach out to grab the paper. Physics is a
## CharacterBody3D capsule; the wobble is procedural on top of it.

const SPEED := 5.0
const GROUND_ACCEL := 20.0
const AIR_ACCEL := 7.0
const GRAVITY := 14.0
const JUMP_SPEED := 6.2
const STEP_HEIGHT := 0.55 ## walk up one paper layer without jumping
const REACH := 2.4 ## from the chest to a grabbable corner/edge
const DRAG_SPEED_MULT := 0.6
const LIFT_SPEED := 1.6 ## how fast held paper is raised/lowered (m/s)
const LIFT_RANGE := Vector2(-3.0, 3.2)
const WEIGHT := 70.0 * 9.8 ## newtons pressed into paper you stand on
const FALL_DEATH_Y := -14.0
const ARM_LEN := 0.75
const MAX_ARM_STRETCH := 2.6

var id := 1
var color := Color.WHITE
var level ## Level (untyped to avoid a circular class dependency)
var spawn := Vector3.ZERO

var grabbing := false
var hover = null ## {sheet, world, local, facet} of the reachable corner/edge, or null

var _grab_sheet: PaperSheet
var _grab_facet := 0
var _grab_local := Vector3.ZERO ## grabbed point, sheet-local
var _grab_start_player := Vector3.ZERO
var _grab_start_sheet := Vector3.ZERO
var _lift := 0.0 ## how far the hands are raised above where they grabbed
var _fold_mode := PaperModel.FOLD_NORMAL
var _choice := 0 ## which collapse option, in collapse mode
var _floor_body: Object = null ## what we're standing on, from the last frame
var _rig: Node3D
var _arms: Array = []
var _hands: Array = []
var _legs: Array = []
var _marker: MeshInstance3D
var _phase := 0.0
var _tilt := Vector2.ZERO
var _tilt_vel := Vector2.ZERO
var _yaw := 0.0


func _a(action: String) -> String:
	return "p%d_%s" % [id, action]


func _ready() -> void:
	add_to_group("players")
	floor_snap_length = STEP_HEIGHT + 0.1
	floor_max_angle = deg_to_rad(50.0)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	_build_visuals()


func _build_visuals() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var skin := _mat(color)
	var dark := _mat(color.darkened(0.35))
	var face := _mat(Color(0.12, 0.12, 0.15))

	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.38
	tm.height = 1.0
	torso.mesh = tm
	torso.material_override = skin
	torso.position.y = 1.05
	_rig.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	head.mesh = hm
	head.material_override = skin
	head.position.y = 1.72
	_rig.add_child(head)
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.05
		em.height = 0.1
		eye.mesh = em
		eye.material_override = face
		eye.position = Vector3(0.1 * sx, 1.76, -0.25)
		_rig.add_child(eye)

	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.46 * sx, 1.28, 0.0)
		var am := MeshInstance3D.new()
		var acm := CapsuleMesh.new()
		acm.radius = 0.1
		acm.height = ARM_LEN
		am.mesh = acm
		am.material_override = dark
		am.rotation_degrees.x = 90.0
		am.position.z = -ARM_LEN * 0.5
		arm.add_child(am)
		_rig.add_child(arm)
		_arms.append(arm)

		var hand := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		hand.mesh = sm
		hand.material_override = skin
		_rig.add_child(hand)
		_hands.append(hand)

		var leg := Node3D.new()
		leg.position = Vector3(0.2 * sx, 0.7, 0.0)
		var lm := MeshInstance3D.new()
		var lcm := CapsuleMesh.new()
		lcm.radius = 0.14
		lcm.height = 0.7
		lm.mesh = lcm
		lm.material_override = dark
		lm.position.y = -0.33
		leg.add_child(lm)
		_rig.add_child(leg)
		_legs.append(leg)

	# Glowing marker on the corner/edge you can grab (or are holding).
	_marker = MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.22
	mm.height = 0.44
	_marker.mesh = mm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = glow
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m


func respawn() -> void:
	if grabbing:
		_grab_sheet.cancel_fold()
		grabbing = false
	global_position = spawn
	velocity = Vector3.ZERO


# --- Physics -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var input := Input.get_vector(_a("left"), _a("right"), _a("up"), _a("down"))
	var wish: Vector3 = level.camera_basis() * Vector3(input.x, 0.0, input.y)

	# Separate control: while held, movement slides the whole sheet, jump flips
	# it over and grab turns it.
	var handling_sheet := Input.is_action_pressed(_a("sheet")) and not grabbing
	if handling_sheet:
		var s: PaperSheet = level.sheet_near(self)
		if s != null and not s.is_busy():
			s.push(wish * level.sheet_speed)
			if Input.is_action_just_pressed(_a("jump")):
				s.flip(level.camera_basis().x)
			elif Input.is_action_just_pressed(_a("grab")):
				s.turn(PI * 0.25)
		# Ride the sheet if you're on it, otherwise walk alongside as you push.
		if s == null or _floor_body == s:
			wish = Vector3.ZERO
		else:
			wish *= level.sheet_speed / SPEED

	var speed := SPEED * (DRAG_SPEED_MULT if grabbing else 1.0)
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if grabbing:
		if _fold_mode == PaperModel.FOLD_COLLAPSE:
			# Collapses lie flat, so raise/lower step through the options instead.
			if Input.is_action_just_pressed(_a("jump")):
				_choice += 1
			elif Input.is_action_just_pressed(_a("lower")):
				_choice -= 1
		else:
			# While holding paper, jump/lower raise and lower your hands instead.
			var dir := Input.get_axis(_a("lower"), _a("jump"))
			nudge_lift(dir * LIFT_SPEED * delta)

	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
		if Input.is_action_just_pressed(_a("jump")) and not grabbing and not handling_sheet:
			velocity.y = JUMP_SPEED
		else:
			_step_up(Vector3(velocity.x, 0.0, velocity.z) * delta)
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_press_on_paper()
	_update_grab(handling_sheet)

	if global_position.y < FALL_DEATH_Y:
		respawn()


func nudge_lift(amount: float) -> void:
	if grabbing:
		_lift = clampf(_lift + amount, LIFT_RANGE.x, LIFT_RANGE.y)


## Your weight pushes down on paper you stand on, so stepping out onto an
## overhang can tip a sheet over the edge.
func _press_on_paper() -> void:
	_floor_body = null
	if not is_on_floor():
		return
	var from := global_position + Vector3.UP * 0.2
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.5, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_floor_body = hit.get("collider")
	var body := _floor_body as RigidBody3D
	if body != null:
		body.sleeping = false
		body.apply_force(Vector3.DOWN * WEIGHT, hit.position - body.global_position)


## Lets the bean climb a single paper layer by walking into it.
func _step_up(motion: Vector3) -> void:
	if motion.length() < 0.001:
		return
	var t := global_transform
	if not test_move(t, motion):
		return
	var lift := Vector3.UP * STEP_HEIGHT
	if test_move(t, lift):
		return
	if test_move(t.translated(lift), motion):
		return
	global_position += lift


## Where the hands hold the grabbed point now, in world space. It follows the
## player's walking (not the sheet's own motion) and the raised/lowered hands.
func _hands_world() -> Vector3:
	var s := _grab_sheet
	var walked := global_position - _grab_start_player
	var slid := s.global_position - _grab_start_sheet
	return s.to_global(_grab_local) + Vector3(walked.x - slid.x, _lift, walked.z - slid.z)


func _update_grab(handling_sheet: bool) -> void:
	if grabbing and _grab_sheet.fold_owner != self:
		grabbing = false # the sheet dropped the fold (respawned, reset...)
	if grabbing:
		var t := _grab_sheet.to_local(_hands_world())
		if Input.is_action_pressed(_a("grab")):
			if Input.is_action_just_pressed(_a("mode")):
				_fold_mode = (_fold_mode + 1) % PaperModel.FOLD_NAMES.size()
			_grab_sheet.update_fold(_grab_facet, _grab_local, t, _fold_mode, false, _choice)
		else:
			_grab_sheet.finish_fold(_grab_facet, _grab_local, t, _fold_mode, _choice)
			grabbing = false
		return
	hover = null
	if handling_sheet:
		return
	hover = level.find_handle(global_position + Vector3.UP, REACH)
	if hover != null and Input.is_action_just_pressed(_a("grab")):
		var s: PaperSheet = hover.sheet
		if s.begin_fold(self):
			grabbing = true
			_grab_sheet = s
			_grab_facet = hover.facet
			_grab_local = hover.local
			_grab_start_player = global_position
			_grab_start_sheet = s.global_position
			_lift = 0.0
			_fold_mode = PaperModel.FOLD_NORMAL
			_choice = 0


func fold_status() -> String:
	if not grabbing:
		return ""
	var msg := "%s, hands %+.1f m" % [PaperModel.FOLD_NAMES[_fold_mode], _lift]
	if _fold_mode == PaperModel.FOLD_COLLAPSE:
		msg = PaperModel.FOLD_NAMES[_fold_mode]
		if _grab_sheet.fold_choices > 1:
			msg += ", option %d of %d (raise/lower to change)" % [_grab_sheet.fold_choice + 1, _grab_sheet.fold_choices]
	if _grab_sheet.fold_status != "":
		msg += "  (" + _grab_sheet.fold_status + ")"
	return msg


# --- Procedural animation -----------------------------------------------------

func _process(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()

	# Face where we're going, or toward what we're holding.
	var look_dir := flat
	var reach_target = null
	if grabbing:
		reach_target = _hands_world()
		look_dir = reach_target - global_position
		look_dir.y = 0.0
	elif hover != null:
		reach_target = hover.world
	if look_dir.length() > 0.15:
		_yaw = lerp_angle(_yaw, atan2(-look_dir.x, -look_dir.z), 1.0 - exp(-10.0 * delta))
	_rig.rotation.y = _yaw

	# Spring-based lean so the bean sloshes around as it speeds up and stops.
	var local_v := _rig.global_basis.inverse() * flat
	var tilt_target := Vector2(-0.045 * -local_v.z, -0.03 * local_v.x)
	_tilt_vel += ((tilt_target - _tilt) * 70.0 - _tilt_vel * 7.0) * delta
	_tilt += _tilt_vel * delta
	_rig.rotation.x = _tilt.x
	_rig.rotation.z = _tilt.y

	_phase += speed * delta * 2.4
	var swing := sin(_phase) * clampf(speed / SPEED, 0.0, 1.0)
	var airborne := not is_on_floor()
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var leg: Node3D = _legs[i]
		leg.rotation.x = (0.35 * s if airborne else 0.8 * swing * s)

		var arm: Node3D = _arms[i]
		var hand: MeshInstance3D = _hands[i]
		if reach_target != null:
			var shoulder := arm.global_position
			var tgt: Vector3 = reach_target + _rig.global_basis.x * (0.18 * (1.0 if i == 0 else -1.0)) * -1.0
			var to := tgt - shoulder
			var dist := minf(to.length(), ARM_LEN * MAX_ARM_STRETCH)
			if to.length() > 0.05:
				arm.look_at(shoulder + to, Vector3.UP)
			arm.scale = Vector3(1, 1, maxf(dist / ARM_LEN, 0.4))
		else:
			var lift := 0.0 if not airborne else 1.2
			arm.rotation = Vector3(deg_to_rad(-80.0 + lift * 60.0) + 0.7 * swing * -s, 0.0, 0.0)
			arm.scale = Vector3.ONE
		hand.global_position = arm.global_transform * Vector3(0, 0, -ARM_LEN)

	# Marker on what you can grab / are holding.
	if grabbing:
		_marker.visible = true
		_marker.scale = Vector3.ONE
		_marker.global_position = _hands_world()
	elif hover != null:
		_marker.visible = true
		var pulse := 1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.008)
		_marker.scale = Vector3.ONE * pulse
		_marker.global_position = hover.world + Vector3.UP * 0.2
	else:
		_marker.visible = false
