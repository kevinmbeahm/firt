extends Room
## P7 "Ferry Across the Flood" (portage version): two channels with an island
## between them, their currents running opposite ways to waterfalls at either
## end, and a crate that has to reach the plate on the far bank. A fence runs
## the length of the island with one narrow gap: beans fit through it, a boat
## doesn't. Fold the sheet into a tray, load the crate, paddle the first
## channel and run aground on the island's shallow shelf (you can wade there,
## not in the channels); then carry the boat over the fence
## together (hands up, walking through the gap one behind the other), set it
## down on the far beach, climb in, slide it in and paddle the second channel.

const BANK_Y := 0.4
const SHELF_Y := -0.5 ## the island's shallow shelves: a boat floats over them, a bean can wade
const CH1 := Vector2(-6, 10) ## the first channel's water, x from..to (deep only up to x=0)
const CH2 := Vector2(17, 34) ## the second's (deep from x=26 to 32)
const ISLAND := Vector2(11, 17) ## the island's dry top
const FENCE_X := 14.0
const FENCE_H := 0.7
const GAP := 1.4 ## the gap in the fence, centred on z = 0
const FAR_X := 36.0 ## the far bank's dry top starts here

var plate: PressurePlate
var crate: Prop
var channel1: Water
var channel2: Water


func build() -> void:
	title = "Ferry Across the Flood"
	hint = "Get the crate to the plate on the far bank. Boat it across the first channel, carry the boat over the island's fence together (walk through the gap one behind the other, hands up), and paddle the second channel."
	spawns = [Vector3(-20, BANK_Y + 0.1, -5), Vector3(-20, BANK_Y + 0.1, -2)]
	cam_yaw = -PI * 0.5
	var grass := Color(0.5, 0.64, 0.42)
	var sand := Color(0.85, 0.78, 0.55)
	add_block(Vector3(-17, BANK_Y - 2, 0), Vector3(18, 4, 32), grass) # start bank, x -26..-8
	add_ramp(Vector3(-8.0, BANK_Y, 0), Vector3(-4.5, -1.0, 0), 32.0, sand)
	add_block(Vector3(-3, -4.25, 0), Vector3(10, 0.5, 32), Color(0.45, 0.4, 0.3)) # first channel's bed
	# The island: a shallow shelf (a boat floats over it, a bean can wade),
	# a short beach, the dry top with its fence, and the same on the far side.
	add_block(Vector3(4.5, SHELF_Y - 2, 0), Vector3(9, 4, 32), sand)
	add_ramp(Vector3(9, SHELF_Y, 0), Vector3(ISLAND.x, BANK_Y, 0), 32.0, sand)
	add_block(Vector3((ISLAND.x + ISLAND.y) * 0.5, BANK_Y - 2, 0), Vector3(ISLAND.y - ISLAND.x, 4, 32), grass)
	add_ramp(Vector3(ISLAND.y, BANK_Y, 0), Vector3(19, SHELF_Y, 0), 32.0, sand)
	add_block(Vector3(22.5, SHELF_Y - 2, 0), Vector3(7, 4, 32), sand)
	add_block(Vector3(29, -4.25, 0), Vector3(6, 0.5, 32), Color(0.45, 0.4, 0.3)) # second channel's bed
	add_ramp(Vector3(32, -1.0, 0), Vector3(FAR_X, BANK_Y, 0), 32.0, sand) # far beach
	add_block(Vector3(FAR_X + 6, BANK_Y - 2, 0), Vector3(12, 4, 32), grass) # far bank
	channel1 = add_water(Vector3((CH1.x + CH1.y) * 0.5, 0, 0), Vector2(CH1.y - CH1.x, 32), 4.0, Vector3(0, 0, 0.6), true)
	channel2 = add_water(Vector3((CH2.x + CH2.y) * 0.5, 0, 0), Vector2(CH2.y - CH2.x, 32), 4.0, Vector3(0, 0, -0.6), true)
	var fence := Color(0.5, 0.36, 0.24)
	var half := GAP * 0.5
	for zr in [Vector2(-16, -half), Vector2(half, 16)]:
		add_block(Vector3(FENCE_X, BANK_Y + FENCE_H * 0.5, (zr.x + zr.y) * 0.5), Vector3(0.3, FENCE_H, zr.y - zr.x), fence)
	var tray := []
	for d in [-3.0, 3.0]:
		tray.append({"a": Vector2(d, -4), "b": Vector2(d, 4), "mv": 1})
		tray.append({"a": Vector2(-4, d), "b": Vector2(4, d), "mv": 1})
	add_sheet(Vector2(8, 8), Vector3(-15, BANK_Y, -6), 0.0, tray)
	crate = add_prop(Prop.CRATE, Vector3(-20, BANK_Y + 0.45, 3), 40.0, Color(0.6, 0.42, 0.24))
	plate = add_plate(Vector3(FAR_X + 4, BANK_Y, 0), Vector2(2.5, 2.5), 35.0)
	add_goal(Vector3(FAR_X + 9, BANK_Y, 6), 3.0, BANK_Y - 0.4)


func is_complete(players: Array) -> bool:
	return plate.is_pressed and super.is_complete(players)


func status() -> String:
	var s := "The crate's on the plate." if plate.is_pressed else "The crate needs to get onto the plate on the far bank."
	if sheet.water_status() != "":
		s += "  The paper is " + sheet.water_status() + "."
	return s
