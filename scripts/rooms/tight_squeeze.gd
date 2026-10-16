extends Room
## P4 "Tight Squeeze": a big 12 x 12 m sheet, and a wall with a low tunnel
## (1.2 m high, 3.4 m wide) behind a door. A glowing sizer box in front of the
## tunnel opens the door once the paper fits inside it: fold the sheet down
## small (in half three times makes a 3 x 6 m strip), slide it into the box,
## then push it through the tunnel. The beans go round by the narrow passage
## (too tall for the tunnel, too narrow for the paper) and pull it out on the
## far side. There, unfold it again (undo, which needs room to swing the paper
## back out) and lay it flat over the glowing square on the floor.

const WALL_X := -4.0 ## the wall's near face (it's 6 m thick)
const WALL_T := 6.0
const TUNNEL_H := 1.2
const TUNNEL_W := 3.4
const PASSAGE_Z := Vector2(6.0, 7.2) ## the beans' way round, z from..to
const PASSAGE_H := 3.0
const WALL_H := 6.0
const PAD := Vector3(14, 0, 0) ## the square to cover, on the far side
const PAD_SIZE := 6.2

var sizer: ShapeGate
var pad: ShapeGate
var door: AnimatableBody3D


func build() -> void:
	title = "Tight Squeeze"
	hint = "Fold the sheet down small enough to fit the glowing box (in half, three times), slide it in and the tunnel opens. Push it through, go round by the passage, pull it out, unfold it (Z) and lay it flat over the square."
	spawns = [Vector3(-26, 0.1, 8), Vector3(-26, 0.1, 10)]
	cam_yaw = -PI * 0.5
	add_block(Vector3(-1, -2, 0), Vector3(54, 4, 24), Color(0.55, 0.62, 0.5)) # floor, x -28..26
	var wall := Color(0.75, 0.7, 0.62)
	var cx := WALL_X + WALL_T * 0.5
	var t := TUNNEL_W * 0.5
	for zr in [Vector2(-12, -t), Vector2(t, PASSAGE_Z.x), Vector2(PASSAGE_Z.y, 12)]:
		add_block(Vector3(cx, WALL_H * 0.5, (zr.x + zr.y) * 0.5), Vector3(WALL_T, WALL_H, zr.y - zr.x), wall)
	add_block(Vector3(cx, (TUNNEL_H + WALL_H) * 0.5, 0), Vector3(WALL_T, WALL_H - TUNNEL_H, TUNNEL_W), wall)
	add_block(Vector3(cx, (PASSAGE_H + WALL_H) * 0.5, (PASSAGE_Z.x + PASSAGE_Z.y) * 0.5),
		Vector3(WALL_T, WALL_H - PASSAGE_H, PASSAGE_Z.y - PASSAGE_Z.x), wall)
	door = add_door(Vector3(WALL_X - 0.25, TUNNEL_H * 0.5, 0), Vector3(0.5, TUNNEL_H, TUNNEL_W), Color(0.55, 0.42, 0.32))
	add_sheet(Vector2(12, 12), Vector3(-18, 0, 0))
	sizer = ShapeGate.new()
	sizer.position = Vector3(-8, 0, 0)
	add_child(sizer)
	sizer.setup_box(Vector3(6.6, 1.0, 3.3), sheets)
	sizer.opened.connect(func() -> void: open_door(door))
	# The square on the far side: a profile gate lying on the floor, looking down.
	pad = ShapeGate.new()
	pad.position = PAD
	pad.rotation.x = -PI * 0.5
	add_child(pad)
	var h := PAD_SIZE * 0.5
	pad.setup(PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]), sheets)
	add_goal(Vector3(22, 0, 8), 3.0)


func is_complete(players: Array) -> bool:
	return pad.is_open and super.is_complete(players)


func status() -> String:
	if not sizer.is_open:
		return sizer.status()
	if pad.is_open:
		return "The square is covered."
	return "Square %d%% covered (need %d%%), %d%% of the paper outside it (max %d%%)" % [
		roundi(pad.coverage * 100.0), roundi(ShapeGate.MIN_COVER * 100.0), roundi(pad.spill * 100.0), roundi(ShapeGate.MAX_SPILL * 100.0)]
