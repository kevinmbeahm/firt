extends "res://scripts/rooms/doorway.gd"
## Doorway 1: a 3 x 3 m square. The 6 x 6 m sheet has two printed valley
## creases: fold it in half along one, stand half of it up along the other,
## then slide it against the wall over the outline. (Standing up half of the
## unfolded sheet makes a 6 m wide wall that spills far outside the square.)


func layout() -> Dictionary:
	title = "Doorway: Square"
	hint = "Fill the glowing square on the wall with paper standing against it. Fold along the printed lines, then slide the sheet into place."
	return {
		"outline": PackedVector2Array([Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(1.5, 3), Vector2(-1.5, 3)]),
		"size": Vector2(6, 6),
		"pos": Vector3(0.5, 0, 0.5),
		"creases": [
			{"a": Vector2(0, -3), "b": Vector2(0, 3), "mv": 1},
			{"a": Vector2(-3, 0), "b": Vector2(3, 0), "mv": 1},
		],
	}
