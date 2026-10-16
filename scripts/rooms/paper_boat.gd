extends Room
## P5 "Paper Boat": a river between two banks, with a current running down to
## a waterfall. The crate has to reach the plate on the far bank, and beans
## can't swim. Fold the sheet into a tray on its printed lines (both sides up,
## then both ends: the corners tuck into gussets, so it's watertight), slide
## it down the slipway, load the crate, climb in and paddle across (sheet
## handling) before the current takes you over the falls. Run it aground on
## the far beach and climb out. A flat sheet floats
## as a raft that holds both beans, but not with the crate as well.

const BANK_Y := 0.4
const RIVER_X := Vector2(-6, 10)
const CURRENT := Vector3(0, 0, 0.6)

var river: Water
var plate: PressurePlate
var crate: Prop


func build() -> void:
	title = "Paper Boat"
	hint = "Get the crate to the plate across the river. Fold the sheet into a tray on its lines (sides up, then ends), slide it down the slipway, load up, climb in and paddle across with sheet handling. Mind the falls!"
	spawns = [Vector3(-20, BANK_Y + 0.1, -5), Vector3(-20, BANK_Y + 0.1, -2)]
	cam_yaw = -PI * 0.5 # looking across the river (+X); it flows to the right (+Z)
	var grass := Color(0.5, 0.64, 0.42)
	add_block(Vector3((-26 + RIVER_X.x) * 0.5, BANK_Y - 2, 0), Vector3(RIVER_X.x + 26, 4, 32), grass) # start bank
	add_block(Vector3((RIVER_X.y + 3.0 + 26) * 0.5, BANK_Y - 2, 0), Vector3(26 - RIVER_X.y - 3.0, 4, 32), grass) # far bank, x 13..26
	add_ramp(Vector3(RIVER_X.y - 2.5, -1.0, 0), Vector3(RIVER_X.y + 3.0, BANK_Y, 0), 32.0, Color(0.85, 0.78, 0.55)) # its beach
	add_block(Vector3((RIVER_X.x + RIVER_X.y) * 0.5, -4.25, 0), Vector3(RIVER_X.y - RIVER_X.x, 0.5, 32), Color(0.45, 0.4, 0.3)) # river bed
	river = add_water(Vector3((RIVER_X.x + RIVER_X.y) * 0.5, 0, 0), Vector2(RIVER_X.y - RIVER_X.x, 32), 4.0, CURRENT, true)
	add_ramp(Vector3(-8.0, BANK_Y, -8), Vector3(-3.5, -1.2, -8), 9.0, Color(0.55, 0.45, 0.35)) # slipway
	var tray := []
	for d in [-3.0, 3.0]:
		tray.append({"a": Vector2(d, -4), "b": Vector2(d, 4), "mv": 1})
		tray.append({"a": Vector2(-4, d), "b": Vector2(4, d), "mv": 1})
	add_sheet(Vector2(8, 8), Vector3(-14, BANK_Y, -8), 0.0, tray)
	crate = add_prop(Prop.CRATE, Vector3(-17, BANK_Y + 0.45, 0), 40.0, Color(0.6, 0.42, 0.24))
	plate = add_plate(Vector3(16, BANK_Y, 0), Vector2(2.5, 2.5), 35.0)
	add_goal(Vector3(21, BANK_Y, 6), 3.0, BANK_Y - 0.4)


func is_complete(players: Array) -> bool:
	return plate.is_pressed and super.is_complete(players)


func status() -> String:
	var s := "The crate's on the plate." if plate.is_pressed else "The crate needs to get onto the plate across the river."
	if sheet.water_status() != "":
		s += "  The paper is " + sheet.water_status() + "."
	return s
