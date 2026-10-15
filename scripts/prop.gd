class_name Prop
extends RigidBody3D
## A loose physics object (S4): a ball ("apple"), a crate, or the solo weight
## block (as heavy as a bean). A bean can pick one up with the grab button and
## carry it in front of them; heavy ones slow you down. Props roll, slide and
## ride in folded paper like anything else, count on pressure plates, and come
## back to where they started if they're lost in the void.

enum { BALL, CRATE, WEIGHT }

const LOST_Y := -25.0
const HOLD_SPEED := 9.0 ## how fast a held prop catches up with the hands, m/s
## Rolling resistance for balls (apples aren't marbles): they sit still in
## paper tilted a degree or two, but still roll down a real slope.
const ROLL_RESIST := 0.04

var kind := BALL
var size := 0.45 ## ball radius, or half the crate's edge
var holder = null ## the bean carrying it, if any
var spawn_transform := Transform3D.IDENTITY
var _respawn := false
var _wake_time := 0.0
var _nudge := Vector3.ZERO


## Sets the prop up before it enters the tree.
func setup(prop_kind: int, kg: float, color: Color, half_size := 0.45) -> void:
	kind = prop_kind
	mass = kg
	size = half_size
	continuous_cd = true
	contact_monitor = true # (for rolling resistance)
	max_contacts_reported = 4
	angular_damp = 0.4 if kind == BALL else 2.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6 if kind == BALL else 0.8
	pm.rough = kind == BALL
	physics_material_override = pm
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	if kind == BALL:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		mi.mesh = sm
		var shape := SphereShape3D.new()
		shape.radius = size
		cs.shape = shape
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size * 2.0
		mi.mesh = bm
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * size * 2.0
		cs.shape = shape
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	mi.material_override = m
	add_child(mi)
	add_child(cs)
	if kind == WEIGHT:
		var label := Label3D.new()
		label.text = "%d kg" % roundi(kg)
		label.font_size = 64
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = size + 0.35
		label.outline_size = 12
		add_child(label)


func _ready() -> void:
	add_to_group("props")
	spawn_transform = global_transform


func pick_up(by) -> void:
	holder = by
	gravity_scale = 0.0
	can_sleep = false # (a sleeping body would never follow the hands)
	sleeping = false


func drop() -> void:
	holder = null
	gravity_scale = 1.0
	# Let it fall before it may sleep again: held still in the hands, it'd
	# otherwise doze off in mid-air the moment it's let go.
	_wake_time = 1.0
	sleeping = false
	linear_velocity *= 0.2 # set down, not thrown
	angular_velocity = Vector3.ZERO


## A change in velocity: the carried paper it rests in sped up or slowed down
## (see PaperSheet._carry_riders).
func nudge(dv: Vector3) -> void:
	_nudge += dv
	sleeping = false


## Back to where it started (lost in the void, or a plate dumped it).
func respawn() -> void:
	if holder != null:
		holder.drop_prop()
	_respawn = true
	sleeping = false


func _physics_process(delta: float) -> void:
	if _wake_time > 0.0:
		_wake_time -= delta
		if _wake_time <= 0.0 and holder == null:
			can_sleep = true
	if global_position.y < LOST_Y:
		respawn()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _respawn:
		_respawn = false
		state.transform = spawn_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
	if _nudge != Vector3.ZERO:
		state.linear_velocity += _nudge
		_nudge = Vector3.ZERO
	if holder != null:
		# Follow the hands (still colliding with the world on the way).
		var to: Vector3 = holder.hold_point() - state.transform.origin
		var v := to / state.step
		if v.length() > HOLD_SPEED:
			v = v.normalized() * HOLD_SPEED
		state.linear_velocity = v
		state.angular_velocity *= 0.8
	elif kind == BALL and state.get_contact_count() > 0:
		var w := state.angular_velocity
		var slow := 2.5 * ROLL_RESIST * 9.8 / size * state.step
		state.angular_velocity = w - w.limit_length(slow)
