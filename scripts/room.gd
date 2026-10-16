class_name Room
extends Node3D
## One puzzle room. The Level loads rooms one at a time (only one exists at a
## time, so each room builds its world around the origin as it likes) and
## hosts everything shared: players, camera, HUD, input, undo.
##
## A room builds its terrain, sheets and goal in build(), says where players
## start, and decides when it's solved in is_complete(). Helpers below cover
## the common pieces.

var level ## Level (untyped to avoid a circular class dependency)
var title := ""
var hint := "" ## one line shown under the controls
var sheets: Array = []
var sheet: PaperSheet ## the room's main sheet (the first one added)
var props: Array = [] ## loose props (balls, crates, weight blocks)
var spawns: Array = [Vector3.ZERO, Vector3(0, 0, 3)] ## where P1 and P2 start
var cam_yaw := -PI * 0.5 ## starting camera direction
var checkpoints: Array = [] ## {pos, radius, spawns}: reaching one moves both players' respawn points

var goal_pos := Vector3.ZERO
var goal_radius := 3.0
var goal_min_y := -INF
var _flag: MeshInstance3D
var _complete := false


## Builds the room. Override.
func build() -> void:
	pass


## Whether the room is solved. Default: every player stands in the goal zone.
func is_complete(players: Array) -> bool:
	if _flag == null:
		return false
	for p in players:
		var d := Vector2(p.global_position.x - goal_pos.x, p.global_position.z - goal_pos.z).length()
		if d > goal_radius or p.global_position.y < goal_min_y:
			return false
	return true


## Called by the level every frame with the current completion state.
func update_room(_delta: float, complete: bool) -> void:
	if complete != _complete and _flag != null:
		(_flag.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1, 0.5) if complete else Color(1, 0.85, 0.2)
	_complete = complete


# --- Building helpers --------------------------------------------------------

## A sheet of paper lying flat at `pos`, turned `yaw` about the vertical.
## `creases` are printed crease lines, each {a: Vector2, b: Vector2, mv: +1
## valley / -1 mountain}, in the sheet's paper coordinates (centred, metres).
func add_sheet(size: Vector2, pos: Vector3, yaw: float = 0.0, creases: Array = []) -> PaperSheet:
	var s := PaperSheet.new()
	s.setup(size, creases)
	s.position = pos
	s.rotation.y = yaw # before entering the tree, so it's part of the spawn transform
	add_child(s)
	sheets.append(s)
	if sheet == null:
		sheet = s
	if level != null:
		level.register_sheet(s)
	return s


func add_block(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


## The goal: a flag at `pos`; players count as there within `radius` of it
## (horizontally) and no lower than `min_y`.
func add_goal(pos: Vector3, radius: float = 3.0, min_y: float = -INF) -> void:
	goal_pos = pos
	goal_radius = radius
	goal_min_y = min_y
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 3.0
	pole.mesh = cm
	pole.material_override = mat(Color(0.9, 0.9, 0.9))
	pole.position = pos + Vector3(0, 1.5, 0)
	add_child(pole)
	_flag = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.4, 0.8, 0.05)
	_flag.mesh = fm
	_flag.material_override = mat(Color(1, 0.85, 0.2))
	_flag.position = pos + Vector3(0.7, 2.5, 0)
	add_child(_flag)


## A loose prop at `pos` (see Prop for the kinds).
func add_prop(kind: int, pos: Vector3, kg: float, color: Color, half_size := 0.45) -> Prop:
	var p := Prop.new()
	p.setup(kind, kg, color, half_size)
	p.position = pos
	add_child(p)
	props.append(p)
	return p


## The solo stand-in: a block as heavy as a bean.
func add_weight_block(pos: Vector3) -> Prop:
	return add_prop(Prop.WEIGHT, pos, 70.0, Color(0.32, 0.33, 0.38), 0.45)


## A pressure plate centred at `pos` (top of the floor there) that weighs this
## room's props.
func add_plate(pos: Vector3, plate_size: Vector2, kg: float) -> PressurePlate:
	var plate := PressurePlate.new()
	plate.position = pos
	add_child(plate)
	plate.setup(plate_size, kg, props, level.players if level != null else [])
	return plate


## A seesaw plank (S8): `length` m long along X, pivoting about the Z axis at
## `pivot`, tipping up to `max_angle` either way (stopped by blocks under its
## ends). It starts with its -X end down, and `lean` (newton-metres) keeps it
## leaning that way when nothing else is on it, as if weighted under that end.
## Returns the plank body.
func add_seesaw(pivot: Vector3, length: float, width: float, max_angle: float, kg: float, color: Color, lean := 0.0) -> RigidBody3D:
	var plank := RigidBody3D.new()
	plank.mass = kg
	plank.axis_lock_linear_x = true
	plank.axis_lock_linear_y = true
	plank.axis_lock_linear_z = true
	plank.axis_lock_angular_x = true
	plank.axis_lock_angular_y = true
	plank.angular_damp = 1.5
	plank.can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	plank.physics_material_override = pm
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.3, width)
	mi.mesh = bm
	mi.material_override = mat(color)
	plank.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 0.3, width)
	cs.shape = shape
	plank.add_child(cs)
	plank.position = pivot
	plank.rotation.z = max_angle # -X end down
	plank.constant_torque = Vector3(0, 0, lean)
	add_child(plank)
	# The post it pivots on (just clear of the plank), and the stops under its ends.
	add_block(Vector3(pivot.x, (pivot.y - 0.25) * 0.5 - 4.0, pivot.z), Vector3(0.6, pivot.y - 0.25 + 8.0, 0.6), color.darkened(0.4))
	var half := length * 0.5 - 0.4
	for sgn in [-1.0, 1.0]:
		var end := pivot + Vector3(half * cos(max_angle) * sgn, -half * sin(max_angle) - 0.15 / cos(max_angle), 0)
		add_block(Vector3(end.x, end.y - 4.0, end.z), Vector3(0.6, 8.0, width * 0.6), color.darkened(0.4))
	return plank


## A straight sloping walkway `width` m wide from `from` to `to` (its top
## surface's centre line).
func add_ramp(from: Vector3, to: Vector3, width: float, color: Color) -> StaticBody3D:
	var run := to - from
	var body := StaticBody3D.new()
	var along := run.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along)
	body.transform = Transform3D(Basis(along, up, side), (from + to) * 0.5 - up * 0.25)
	var size := Vector3(run.length(), 0.5, width)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


## A door panel that slides down into the floor when open_door() is called.
func add_door(center: Vector3, size: Vector3, color: Color) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.position = center
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func open_door(door: AnimatableBody3D) -> void:
	var tw := create_tween()
	tw.tween_property(door, "position:y", door.position.y - (door.get_child(1).shape as BoxShape3D).size.y - 0.05, 1.2)


## A cable from `from` to `to` (S7), with a post holding up each end.
func add_cable(from: Vector3, to: Vector3, post_bottoms := Vector2(-6.0, -6.0)) -> Cable:
	var c := Cable.new()
	c.setup(from, to)
	add_child(c)
	var post := Color(0.45, 0.35, 0.25)
	var out := (to - from)
	out.y = 0.0
	out = out.normalized() * 0.35
	for end in [[from - out, post_bottoms.x], [to + out, post_bottoms.y]]:
		var top: Vector3 = end[0]
		var h: float = top.y + 0.2 - end[1]
		add_block(Vector3(top.x, end[1] + h * 0.5, top.z), Vector3(0.35, h, 0.35), post)
	return c


## Water (S5) over a rectangle: `center` is the middle of its surface.
func add_water(center: Vector3, extent: Vector2, depth: float, current := Vector3.ZERO, falls := false) -> Water:
	var w := Water.new()
	w.setup(center, extent, depth, current, falls)
	add_child(w)
	return w


## Extra line for the HUD (e.g. how well a shape gate is filled).
func status() -> String:
	return ""


## A checkpoint: once any player comes within `radius` of `pos`, both players
## respawn at `respawn` (P2 a little to the side) from then on.
func add_checkpoint(pos: Vector3, radius: float, respawn: Vector3, side := Vector3(0, 0, 2.5)) -> void:
	checkpoints.append({"pos": pos, "radius": radius, "spawns": [respawn, respawn + side]})


func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m
