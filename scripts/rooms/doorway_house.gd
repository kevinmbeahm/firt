extends "res://scripts/rooms/doorway.gd"
## Doorway 2: a house, 4 m wide with 2.5 m walls and a roof peak at 4 m. The
## 4 x 8 m sheet has the stand-up line and the two roof lines printed. Fold the
## top corners down along the roof lines while the sheet is flat (once it
## stands up they're out of reach), stand the end up, slide it into place.


func layout() -> Dictionary:
	title = "Doorway: House"
	hint = "Fill the house shape. Fold the corners down for the roof while the paper is flat, then stand it up and slide it into place."
	return {
		"outline": PackedVector2Array([Vector2(-2, 0), Vector2(2, 0), Vector2(2, 2.5), Vector2(0, 4), Vector2(-2, 2.5)]),
		"size": Vector2(4, 8),
		"pos": Vector3(1, 0, 1),
		"creases": [
			{"a": Vector2(-2, 0), "b": Vector2(2, 0), "mv": 1},
			{"a": Vector2(-2, 2.5), "b": Vector2(0, 4), "mv": 1},
			{"a": Vector2(2, 2.5), "b": Vector2(0, 4), "mv": 1},
		],
	}
