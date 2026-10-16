extends Room
## P2 "Zipline Delivery": a cable runs down from the cliff to an island 16 m
## across the void. Fold the sheet in half along its printed line, then carry
## it up to the cable together, each holding one end of the crease, until the
## crease lies along the cable: it hooks on, and you're both hanging from it.
## Ride it down and let go over the island. Each metre of crease on the cable
## holds 50 kg: a little corner folded over it won't take two beans.

const CABLE_FROM := Vector3(-22, 3.4, 0)
const CABLE_TO := Vector3(26, -2.6, 0)
const ISLAND_Y := -6.0


func build() -> void:
	title = "Zipline Delivery"
	hint = "Fold the sheet in half on its line, carry it up to the cable together (one of you at each end of the crease) until the crease lies along the cable, then hang on and ride it down. Let go over the island."
	spawns = [Vector3(-20, 0.1, 6), Vector3(-20, 0.1, 9)]
	cam_yaw = -PI * 0.5 # looking toward +X, down the cable
	add_block(Vector3(-15, -2, 1), Vector3(22, 4, 22), Color(0.55, 0.6, 0.5)) # cliff, x -26..-4
	add_block(Vector3(23, ISLAND_Y - 2, 0), Vector3(22, 4, 16), Color(0.5, 0.66, 0.42)) # island, x 12..34
	add_cable(CABLE_FROM, CABLE_TO, Vector2(-4.0, ISLAND_Y - 4.0))
	add_sheet(Vector2(10, 6), Vector3(-12, 0, 5), 0.0, [
		{"a": Vector2(-5, 0), "b": Vector2(5, 0), "mv": 1},
	])
	add_goal(Vector3(30, ISLAND_Y, 4), 3.0, ISLAND_Y - 0.4)


func status() -> String:
	return sheet.hook_status()
