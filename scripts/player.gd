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
const PROP_LIFT := Vector2(-1.0, 1.6) ## how far a carried prop can be lowered/raised
const HANG := 2.1 ## hanging on, your hands are this far above your feet
const HOP_SPEED := 4.0 ## letting go of a ride while pushing the stick hops you off that way

var id := 1
var color := Color.WHITE
var level ## Level (untyped to avoid a circular class dependency)
var spawn := Vector3.ZERO

var grabbing := false ## holding a sheet: folding it, or carrying it with the other bean
var carrying := false ## ...carrying it (see PaperSheet.start_carry)
var riding := false ## ...hanging on to it while it hangs on a cable (see PaperSheet.add_rider)
var held_prop: Prop = null ## a prop carried in front of you
var controlled_by := 1 ## which player's controls drive this character: 1, 2, or 0 = idle (solo play)
var _latched := false ## holding on for a player who just took over, until they press grab
var hover = null ## {sheet, world, local, facet} of the reachable corner/edge, or null

var _grab_sheet: PaperSheet
var _grab_facet := 0
var _grab_local := Vector3.ZERO ## grabbed point, sheet-local
var _grab_start_player := Vector3.ZERO
var _grab_start_sheet := Vector3.ZERO
var _carry_anchor := Vector3.ZERO ## (carrying) where your hands were when the carry started, world
var _carry_from := Vector3.ZERO ## ...and where you stood
var _carry_lift := 0.0 ## ...and how high your hands were
var _lift := 0.0 ## how far the hands are raised above where they grabbed
var _fold_mode := PaperModel.FOLD_NORMAL
var _choice := 0 ## which collapse option, in collapse mode
var _floor_body: Object = null ## what we're standing on, from the last frame
var _rig: Node3D
var _arms: Array = []
var _hands: Array = []
var _legs: Array = []
var _marker: MeshInstance3D
var _pointer: MeshInstance3D
var _body_shape: CollisionShape3D
var _ghost_frames := 0 ## collision stays off this many more physics frames after a teleport
var _phase := 0.0
var _tilt := Vector2.ZERO
var _tilt_vel := Vector2.ZERO
var _yaw := 0.0


func _a(action: String) -> String:
	return "p%d_%s" % [controlled_by, action]


## Input, from whoever controls this character right now. An idle character
## (controlled_by 0, in solo play) presses nothing but keeps holding what it
## holds.
func _pressed(action: String) -> bool:
	if action == "grab" and grabbing and (controlled_by == 0 or _latched):
		return true
	return controlled_by != 0 and Input.is_action_pressed(_a(action))


func _just(action: String) -> bool:
	return controlled_by != 0 and Input.is_action_just_pressed(_a(action))


func _stick() -> Vector2:
	if controlled_by == 0:
		var partner = _carry_partner()
		return partner._stick() if partner != null and partner.controlled_by != 0 else Vector2.ZERO
	return Input.get_vector(_a("left"), _a("right"), _a("up"), _a("down"))


func _axis(negative: String, positive: String) -> float:
	if controlled_by == 0:
		var partner = _carry_partner()
		return partner._axis(negative, positive) if partner != null and partner.controlled_by != 0 else 0.0
	return Input.get_axis(_a(negative), _a(positive))


## The other bean carrying the same sheet. An idle bean (solo play) carrying a
## sheet with the bean you control walks and lifts in step with it, so one
## player can carry a sheet with both beans.
func _carry_partner():
	if not carrying or not is_instance_valid(_grab_sheet):
		return null
	for p in _grab_sheet.carriers:
		if p != self:
			return p
	return null


## Hands control of this character to input set `who` (1 or 2), or 0 to leave
## it idle. A character taken over while holding paper keeps holding it until
## its new player presses grab (and lets go when they release it).
func set_controller(who: int) -> void:
	if who != 0 and who != controlled_by and grabbing:
		_latched = not Input.is_action_pressed("p%d_grab" % who)
	controlled_by = who


func _ready() -> void:
	controlled_by = id
	add_to_group("players")
	floor_snap_length = STEP_HEIGHT + 0.1
	floor_max_angle = deg_to_rad(50.0)

	_body_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_body_shape.shape = cap
	_body_shape.position.y = 0.9
	add_child(_body_shape)

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

	# In solo play, an arrow over the bean you're controlling.
	_pointer = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.4
	_pointer.mesh = cone
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.emission_enabled = true
	white.emission = Color(1, 1, 1)
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pointer.material_override = white
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pointer.position.y = 2.45
	_pointer.visible = false
	add_child(_pointer)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m


func respawn() -> void:
	release()
	_teleport(spawn)


## Lets go of anything held (the fold in progress is dropped).
func release() -> void:
	_latched = false
	drop_prop()
	if riding:
		end_ride()
	if carrying and is_instance_valid(_grab_sheet):
		_grab_sheet.end_carry()
	if grabbing:
		if is_instance_valid(_grab_sheet):
			_grab_sheet.cancel_fold()
		grabbing = false
	hover = null


## Puts the player at `pos` (and makes it their respawn point), e.g. at the
## start of a room.
func place(pos: Vector3) -> void:
	release()
	spawn = pos
	_teleport(pos)


## Moves the bean without it counting as a very fast movement (which would
## fling any paper it was standing on): its collision is off for a moment.
func _teleport(pos: Vector3) -> void:
	_body_shape.disabled = true
	_ghost_frames = 2
	global_position = pos
	velocity = Vector3.ZERO
	_floor_body = null


# --- Physics -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _ghost_frames > 0:
		_ghost_frames -= 1
		if _ghost_frames == 0:
			_body_shape.disabled = false
	var input := _stick()
	var wish: Vector3 = level.camera_basis() * Vector3(input.x, 0.0, input.y)
	if riding:
		_ride(delta, wish)
		return

	# Separate control: while held, movement slides the whole sheet, jump flips
	# it over and grab turns it.
	var handling_sheet := _pressed("sheet") and not grabbing
	if handling_sheet:
		var s: PaperSheet = level.sheet_near(self)
		if s != null and not s.is_busy():
			s.push(wish * level.sheet_speed)
			if _just("jump"):
				s.flip(level.camera_basis().x)
			elif _just("grab"):
				s.turn(PI * 0.25)
		# Ride the sheet if you're on it, otherwise walk alongside as you push.
		if s == null or _floor_body == s:
			wish = Vector3.ZERO
		else:
			wish *= level.sheet_speed / SPEED

	var speed := SPEED * (DRAG_SPEED_MULT if grabbing else 1.0)
	if held_prop != null:
		speed *= clampf(1.0 - held_prop.mass / 200.0, 0.5, 1.0) # heavy things slow you down
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if held_prop != null:
		_lift = clampf(_lift + _axis("lower", "jump") * LIFT_SPEED * delta, PROP_LIFT.x, PROP_LIFT.y)
	elif grabbing:
		if _fold_mode == PaperModel.FOLD_COLLAPSE and not carrying:
			# Collapses lie flat, so raise/lower step through the options instead.
			if _just("jump"):
				_choice += 1
			elif _just("lower"):
				_choice -= 1
		else:
			# While holding paper, jump/lower raise and lower your hands instead.
			var dir := _axis("lower", "jump")
			nudge_lift(dir * LIFT_SPEED * delta)

	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
		if _just("jump") and not grabbing and held_prop == null and not handling_sheet:
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
	if body != null and not body.freeze: # (a frozen body would bank the force and release it all at once)
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
	if riding:
		return _grab_sheet.to_global(_grab_local)
	if carrying:
		return carry_hands()
	var s := _grab_sheet
	var walked := global_position - _grab_start_player
	var slid := s.global_position - _grab_start_sheet
	return s.to_global(_grab_local) + Vector3(walked.x - slid.x, _lift, walked.z - slid.z)


func _update_grab(handling_sheet: bool) -> void:
	if held_prop != null:
		if not is_instance_valid(held_prop) or held_prop.holder != self:
			held_prop = null
		elif not _pressed("grab"):
			drop_prop()
		return
	if carrying:
		if not is_instance_valid(_grab_sheet) or not _grab_sheet.carriers.has(self):
			end_carry()
		elif not _pressed("grab"):
			_grab_sheet.end_carry() # either carrier letting go drops it
		return
	if grabbing and (not is_instance_valid(_grab_sheet) or _grab_sheet.fold_owner != self):
		grabbing = false # the sheet dropped the fold (respawned, reset...)
	if grabbing:
		var t := _grab_sheet.to_local(_hands_world())
		if _latched and Input.is_action_pressed(_a("grab")):
			_latched = false # the new player has taken hold of it
		if _pressed("grab"):
			if _just("mode"):
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
	if hover != null and _just("grab"):
		if hover.has("prop"):
			held_prop = hover.prop
			held_prop.pick_up(self)
			_lift = 0.0
			return
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
		elif s.is_hooked():
			s.add_rider(self, hover.local) # hang on
		elif s.can_join_carry(self):
			# Someone's already holding it: pick it up together.
			_grab_sheet = s
			_grab_local = hover.local
			s.start_carry(self, hover.local)


## Called by the sheet when you take hold of it hanging on a cable (or were
## carrying it when it hooked on): you hang from where you hold it.
func begin_ride(s: PaperSheet, local: Vector3) -> void:
	carrying = false
	grabbing = true
	riding = true
	_grab_sheet = s
	_grab_local = local
	_lift = 0.0
	add_collision_exception_with(s)


## Lets go of a ride (or the sheet slipped off its cable).
func end_ride() -> void:
	if not riding:
		return
	riding = false
	grabbing = false
	_latched = false
	if is_instance_valid(_grab_sheet):
		_grab_sheet.remove_rider(self)
		remove_collision_exception_with(_grab_sheet)


## Hanging on: your hands go where the paper takes them and you dangle below
## (or drag along the ground). Let go to drop; push the stick as you let go
## to hop off that way.
func _ride(delta: float, wish: Vector3) -> void:
	if not is_instance_valid(_grab_sheet) or not _grab_sheet.riders.has(self):
		end_ride()
		return
	if _latched and Input.is_action_pressed(_a("grab")):
		_latched = false
	if not _pressed("grab"):
		end_ride()
		if wish.length() > 0.1:
			velocity += wish.normalized() * HOP_SPEED + Vector3.UP * HOP_SPEED * 0.6
		return
	var target := _hands_world() - Vector3.UP * HANG
	var to := target - global_position
	var held_back := to
	held_back.y = maxf(held_back.y, 0.0) # (standing under it, your feet are on the ground)
	if held_back.length() > 1.6:
		end_ride() # something held you back: your grip slips
		return
	velocity = (to / delta).limit_length(14.0)
	move_and_slide()
	velocity = velocity.limit_length(8.0) # (what you keep when you let go)
	_floor_body = null
	hover = null


## Called by the sheet when a carry starts: hold it where it is now.
func begin_carry(s: PaperSheet, hands_at: Vector3) -> void:
	grabbing = true
	carrying = true
	_grab_sheet = s
	_carry_anchor = hands_at
	_carry_from = global_position
	_carry_lift = _lift


## Called by the sheet when the carry ends.
func end_carry() -> void:
	carrying = false
	grabbing = false


## (Carrying) where your hands are now, world: they move as you walk (up and
## down slopes too) and as you raise or lower them.
func carry_hands() -> Vector3:
	var walked := global_position - _carry_from
	return _carry_anchor + walked + Vector3.UP * (_lift - _carry_lift)


## (Holding a prop) where it's held: in front of you at chest height, raised
## or lowered with your hands.
func hold_point() -> Vector3:
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	return global_position + fwd * (0.75 + held_prop.size) + Vector3.UP * (1.1 + _lift)


func drop_prop() -> void:
	if held_prop != null and is_instance_valid(held_prop):
		held_prop.drop()
	held_prop = null
	_lift = 0.0


func fold_status() -> String:
	if held_prop != null:
		return "carrying a %d kg %s" % [roundi(held_prop.mass), ["ball", "crate", "weight block"][held_prop.kind]]
	if riding:
		return "hanging on (let go to drop; push the stick as you let go to hop off)"
	if carrying:
		return "carrying the sheet together (raise/lower your end with jump/lower; keep it level)"
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
	elif held_prop != null:
		reach_target = held_prop.global_position
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

	_pointer.visible = level.solo and controlled_by == 1
	_pointer.position.y = 2.45 + 0.08 * sin(Time.get_ticks_msec() * 0.006)

	# Marker on what you can grab / are holding.
	if grabbing:
		_marker.visible = true
		_marker.scale = Vector3.ONE
		_marker.global_position = _hands_world()
	elif held_prop != null:
		_marker.visible = false
	elif hover != null:
		_marker.visible = true
		var pulse := 1.0 + 0.2 * sin(Time.get_ticks_msec() * 0.008)
		_marker.scale = Vector3.ONE * pulse
		_marker.global_position = hover.world + Vector3.UP * 0.2
	else:
		_marker.visible = false
