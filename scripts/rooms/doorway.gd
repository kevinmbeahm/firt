extends Room
## P3 "Shape of the Doorway": a wall with a glowing outline painted on it at
## floor level and a locked door beside it. Stand paper up against the wall so
## it fills the outline (a ShapeGate: at least 90% covered, at most 10%
## spilling outside) and the door slides open; the flag is behind it.
## Subclasses set the outline, the sheet and its printed creases.
##
## Layout: floor top at y=0; the wall's face is at z=WALL_Z, facing +Z (the
## camera starts looking at it); the outline is centred at x=OUTLINE_X; the
## door is a 3 m gap at x=DOOR_X; the flag stands behind the wall.

const WALL_Z := -4.0
const OUTLINE_X := -3.0
const DOOR_X := 4.0
const DOOR_W := 3.0
const DOOR_H := 3.5
const WALL_H := 6.0
const FLOOR_COLOR := Color(0.55, 0.66, 0.5)
const WALL_COLOR := Color(0.78, 0.74, 0.66)
const DOOR_COLOR := Color(0.55, 0.42, 0.32)

var gate: ShapeGate
var door: AnimatableBody3D


## Override: {outline: PackedVector2Array (wall-local x,y), size: Vector2,
## pos: Vector3, creases: Array}.
func layout() -> Dictionary:
	return {}


func build() -> void:
	var l := layout()
	spawns = [Vector3(6, 0.1, 4), Vector3(8.5, 0.1, 4)]
	cam_yaw = 0.0 # looking at the wall (toward -Z)
	add_block(Vector3(0, -2, -2), Vector3(24, 4, 24), FLOOR_COLOR)
	# The wall, with a door-sized gap.
	var left_end := DOOR_X - DOOR_W * 0.5
	var right_start := DOOR_X + DOOR_W * 0.5
	add_block(Vector3((-12 + left_end) * 0.5, WALL_H * 0.5, WALL_Z - 0.5), Vector3(left_end + 12, WALL_H, 1), WALL_COLOR)
	add_block(Vector3((right_start + 12) * 0.5, WALL_H * 0.5, WALL_Z - 0.5), Vector3(12 - right_start, WALL_H, 1), WALL_COLOR)
	add_block(Vector3(DOOR_X, (DOOR_H + WALL_H) * 0.5, WALL_Z - 0.5), Vector3(DOOR_W, WALL_H - DOOR_H, 1), WALL_COLOR)
	door = add_door(Vector3(DOOR_X, DOOR_H * 0.5, WALL_Z - 0.5), Vector3(DOOR_W - 0.05, DOOR_H, 0.8), DOOR_COLOR)
	add_goal(Vector3(DOOR_X, 0, WALL_Z - 5.0), 3.0)
	add_sheet(l.size, l.pos, 0.0, l.creases)
	gate = ShapeGate.new()
	gate.position = Vector3(OUTLINE_X, 0.0, WALL_Z)
	add_child(gate)
	gate.setup(l.outline, sheets)
	gate.opened.connect(func() -> void: open_door(door))


func is_complete(players: Array) -> bool:
	return gate.is_open and super.is_complete(players)


func status() -> String:
	return gate.status()
