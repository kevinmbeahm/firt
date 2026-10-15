extends Room
## P1 "The Ramp": a start island, a 7 m bottomless gap, and a ledge 2.2 m high
## that you can't jump onto. The paper has real weight: slide a flat sheet too
## far over the edge and it tips into the void. Fold part of the big sheet up
## into a ramp, slide it out until the ramp's tip reaches over the ledge (so
## it's held up at both ends) and walk up. A second, smaller sheet on the
## island is a sandbox for free folding (paper planes, reverse folds...). Both
## players must reach the flag.

const PUZZLE_SIZE := Vector2(18, 12)
const PUZZLE_START := Vector3(-12, 0, 0)
const SANDBOX_SIZE := Vector2(6, 8.5)
const SANDBOX_START := Vector3(-26, 0, 9.5)
const GOAL_POS := Vector3(13, 2.2, 0)


func build() -> void:
	title = "The Ramp"
	hint = "Fold the far strip of the big sheet up into a ramp, ride the sheet out over the gap, and walk up to the flag."
	spawns = [Vector3(-25, 0.1, -2.0), Vector3(-25, 0.1, 2.0)]
	cam_yaw = -PI * 0.5 # looking toward +X (the ledge)
	# Start island (top at y=0, edge at x=-1) and the high ledge (x from 6, top at y=2.2).
	add_block(Vector3(-16, -2, 0), Vector3(30, 4, 26), Color(0.45, 0.62, 0.45))
	add_block(Vector3(13, -1.9, 0), Vector3(14, 8.2, 16), Color(0.62, 0.5, 0.72))
	add_goal(GOAL_POS, 3.5, 1.9)
	add_sheet(PUZZLE_SIZE, PUZZLE_START)
	add_sheet(SANDBOX_SIZE, SANDBOX_START, PI * 0.5)
