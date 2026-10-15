extends Room
## P11 "Counterweight Lift": a long seesaw plank is the only way up to the high
## ledge. It rests with its near end on the ground, a ramp up to the ledge,
## but it tips the moment you walk past the pivot unless there's enough weight
## on the near end. One bean can hold it down for the other (or the solo
## weight block can), but the last one up needs a counterweight of apples, and
## loose apples roll off the slope: carry them in a folded trough.

const PIVOT := Vector3(0, 2.5, 0)
const PLANK := 16.0
const TILT := 0.2985 # rad (17.1 deg): the near end just touches the ground
const LEDGE_Y := 5.0
## The plank leans back onto its near end as if 120 kg sat 1 m from the pivot,
## so it always settles back where you can get on it. A bean near the far end
## outweighs that about four times over.
const LEAN := 120.0 * 9.8

var plank: RigidBody3D


func build() -> void:
	title = "Counterweight Lift"
	hint = "The plank is a ramp to the high ledge, but it tips once you're past the middle. Weigh its near end down: a bean, the weight block, or a trough full of apples (they roll off on their own)."
	spawns = [Vector3(-18, 0.1, -2), Vector3(-18, 0.1, 2)]
	cam_yaw = -PI * 0.5
	var ground := Color(0.55, 0.62, 0.5)
	add_block(Vector3(-15.8, -2, 0), Vector3(16.4, 4, 22), ground) # start, x -24..-7.6, z -11..11
	add_block(Vector3(16.05, LEDGE_Y - 5.0, 0), Vector3(15.9, 10, 16), Color(0.62, 0.5, 0.72)) # ledge, x 8.1..24
	plank = add_seesaw(PIVOT, PLANK, 8.0, TILT, 120.0, Color(0.6, 0.45, 0.3), LEAN)
	# Printed so the trough's walls run across the plank (they stop apples
	# rolling down it) and its open ends face the plank's sides.
	add_sheet(Vector2(6, 5), Vector3(-14, 0, 4.5), 0.0, [
		{"a": Vector2(-1.5, -2.5), "b": Vector2(-1.5, 2.5), "mv": 1},
		{"a": Vector2(1.5, -2.5), "b": Vector2(1.5, 2.5), "mv": 1},
	])
	var red := Color(0.85, 0.15, 0.12)
	for i in 8:
		add_prop(Prop.BALL, Vector3(-21.5 + (i % 4) * 1.2, 0.5, -5.5 + (i / 4) * 1.2), 15.0, red)
	add_weight_block(Vector3(-20, 0.5, 6))
	add_goal(Vector3(15, LEDGE_Y, 0), 3.5, LEDGE_Y - 0.4)
