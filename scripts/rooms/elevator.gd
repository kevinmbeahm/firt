extends Room
## P13 "Paper Elevator": a hook bar hangs in a shaft below a high ledge, on a
## lift that rises while someone (or something heavy) stands on a plate: the
## one in the alcove at the bottom, or the one up on the ledge. Fold the sheet
## in half, carry it up to the bar together until the crease hooks on, and
## hang on while your partner stands on the plate. At the top, push toward the
## ledge as you let go to hop off. Then step on the top plate to bring the lift
## back up with your partner hanging on.

const BAR_Y := 2.9 ## the hook bar's height at the bottom
const TOP_Y := 11.5 ## ...and at the top
const LIFT_SPEED := 1.8
const LEDGE_Y := 9.0
const LEDGE_X := 4.0 ## the ledge's face

var lift: Cable
var low_plate: PressurePlate
var high_plate: PressurePlate


func build() -> void:
	title = "Paper Elevator"
	hint = "Fold the sheet in half, carry it up to the hook bar together until the crease hooks on, and hang on while your partner stands on the plate. Push toward the ledge as you let go at the top. Then the top plate brings the lift back up."
	spawns = [Vector3(-12, 0.1, 3), Vector3(-12, 0.1, 6)]
	cam_yaw = -PI * 0.5
	add_block(Vector3(-6, -2, 0), Vector3(20, 4, 18), Color(0.55, 0.58, 0.62)) # floor, x -16..4
	add_block(Vector3(10, LEDGE_Y * 0.5 - 2, 0), Vector3(12, LEDGE_Y + 4, 18), Color(0.62, 0.5, 0.72)) # ledge, x 4..16
	# The shaft's frame: two posts and a beam over the top.
	var frame := Color(0.4, 0.33, 0.28)
	for z in [-3.2, 3.2]:
		add_block(Vector3(0, (TOP_Y + 1.5) * 0.5, z), Vector3(0.4, TOP_Y + 1.5, 0.4), frame)
	add_block(Vector3(0, TOP_Y + 1.5, 0), Vector3(0.6, 0.4, 6.8), frame)
	# The hook bar, on two ropes up to the beam.
	lift = Cable.new()
	lift.setup(Vector3(-2, BAR_Y, 0), Vector3(2, BAR_Y, 0), Color(0.75, 0.6, 0.3))
	add_child(lift)
	for x in [0.0, 4.0]:
		var rope := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.03
		cm.height = 20.0
		rope.mesh = cm
		rope.material_override = mat(Color(0.85, 0.8, 0.65))
		rope.position = Vector3(x, 10.0, 0)
		lift.add_child(rope)
	add_sheet(Vector2(6, 5), Vector3(-8, 0, 0), 0.0, [
		{"a": Vector2(-3, 0), "b": Vector2(3, 0), "mv": 1},
	])
	low_plate = add_plate(Vector3(-11, 0, -6), Vector2(2.5, 2.5), 60.0)
	high_plate = add_plate(Vector3(8, LEDGE_Y, 4), Vector2(2.5, 2.5), 60.0)
	for p in [low_plate, high_plate]:
		p.counts_players = true
		p.latch = false
	add_weight_block(Vector3(-14, 0.5, -6))
	add_goal(Vector3(12, LEDGE_Y, -4), 3.0, LEDGE_Y - 0.4)


func lift_up() -> bool:
	return low_plate.is_pressed or high_plate.is_pressed


func _physics_process(delta: float) -> void:
	var y := lift.position.y
	lift.position.y = move_toward(y, TOP_Y if lift_up() else BAR_Y, LIFT_SPEED * delta)


func status() -> String:
	var where := "at the top" if lift.position.y > TOP_Y - 0.05 else ("at the bottom" if lift.position.y < BAR_Y + 0.05 else ("going up" if lift_up() else "going down"))
	var s := "Lift %s." % where
	if sheet.hook_status() != "":
		s += "  " + sheet.hook_status()
	return s
