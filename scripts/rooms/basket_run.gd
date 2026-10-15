extends Room
## P6 "Basket Run": six apples on an upper terrace, a scale on the lower one
## that needs all six (90 kg) at once, and a long ramp between them. The scale
## tips everything back up the hill if it's left part-loaded for too long, so
## ferrying apples one at a time is too slow. Fold the sheet's sides up into a
## trough (the printed lines), roll the apples in, and carry it down with both
## beans holding its open ends: keep it level or the apples roll out.

const UPPER_Y := 3.0
const APPLE_KG := 15.0

var scale_plate: PressurePlate


func build() -> void:
	title = "Basket Run"
	hint = "Get all six apples onto the scale at once. Fold the sides of the sheet up into a trough, load it, and carry it down together, each holding an open end. Keep it level!"
	spawns = [Vector3(-12, UPPER_Y + 0.1, -3), Vector3(-12, UPPER_Y + 0.1, 3)]
	cam_yaw = -PI * 0.5 # looking toward +X, down the hill
	var grass := Color(0.5, 0.66, 0.42)
	add_block(Vector3(-8, UPPER_Y - 3.5, 0), Vector3(16, 7, 16), grass) # upper terrace, x -16..0
	add_ramp(Vector3(-0.5, UPPER_Y, -5), Vector3(14.5, 0, -5), 4.0, Color(0.62, 0.55, 0.45))
	add_block(Vector3(22, -2, 0), Vector3(16, 4, 16), grass) # lower terrace, x 14..30
	# Printed so the trough runs along X: down the ramp, open ends front and back.
	add_sheet(Vector2(7, 7), Vector3(-7, UPPER_Y, 0), 0.0, [
		{"a": Vector2(-3.5, -2), "b": Vector2(3.5, -2), "mv": 1},
		{"a": Vector2(-3.5, 2), "b": Vector2(3.5, 2), "mv": 1},
	])
	var red := Color(0.85, 0.15, 0.12)
	for p in [Vector2(-13, -6), Vector2(-14, 5), Vector2(-3, 6), Vector2(-2.5, -6.5), Vector2(-10, 6.5), Vector2(-15, -1)]:
		add_prop(Prop.BALL, Vector3(p.x, UPPER_Y + 0.5, p.y), APPLE_KG, red)
	scale_plate = add_plate(Vector3(23, 0, 2), Vector2(8, 5.5), APPLE_KG * 6.0)
	scale_plate.reset_after = 30.0
	add_goal(Vector3(27, 0, -5), 3.0)


func is_complete(players: Array) -> bool:
	return scale_plate.is_pressed and super.is_complete(players)


func status() -> String:
	return scale_plate.status()
