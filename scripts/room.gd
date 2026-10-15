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
