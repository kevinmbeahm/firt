extends SceneTree
# Solo carrying with real inputs, in the Basket Run room: P1's bean grabs one
# end of the sheet, P1 swaps to the other bean (the first keeps holding) and
# grabs the other end, so both beans carry it. The idle bean walks and lifts in
# step with the one P1 drives; letting go drops it.
# Run:   godot --headless -s tests/solo_carry.gd      (exit code 0 = pass)

var lvl
var ok := true


func _initialize() -> void:
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)
	run.call_deferred()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func run() -> void:
	await frames(30)
	lvl.load_room(4)
	await frames(40)
	var y: float = lvl.room.UPPER_Y
	var s: PaperSheet = lvl.sheet
	var b1 = lvl.players[0]
	var b2 = lvl.players[1]
	b2.place(Vector3(-12, y + 0.1, 5))
	b1.place(Vector3(-11.4, y + 0.1, 0.5))
	await frames(15)
	Input.action_press("p1_grab")
	await frames(3)
	check(b1.grabbing and s.fold_owner == b1, "bean 1 takes the back edge")
	Input.action_press("p1_swap") # still holding grab
	await frames(2)
	Input.action_release("p1_swap")
	await frames(3)
	Input.action_release("p1_grab")
	await frames(5)
	check(b1.controlled_by == 0 and b2.controlled_by == 1 and b1.grabbing, "swapped: bean 1 keeps holding, P1 drives bean 2")

	b2.place(Vector3(-2.6, y + 0.1, 0.5)) # (as if walked round to the front)
	await frames(15)
	Input.action_press("p1_grab")
	await frames(3)
	check(b1.carrying and b2.carrying and s.carriers.size() == 2, "bean 2 takes the front edge: they carry it together")

	Input.action_press("p1_jump")
	await frames(40)
	Input.action_release("p1_jump")
	await frames(30)
	check(b1._lift > 0.4 and b2._lift > 0.4, "raising lifts both ends (%.2f, %.2f m)" % [b1._lift, b2._lift])
	check(s.global_position.y > y + 0.4, "the sheet comes up off the ground (%.2f m)" % (s.global_position.y - y))

	# The camera looks down +X here: stick up walks that way.
	var p1 := b1.global_position as Vector3
	var p2 := b2.global_position as Vector3
	var sp := s.global_position
	Input.action_press("p1_up")
	await frames(60)
	Input.action_release("p1_up")
	await frames(20)
	var d1: float = b1.global_position.x - p1.x
	var d2: float = b2.global_position.x - p2.x
	check(d2 > 1.0 and absf(d1 - d2) < 0.3, "the idle bean walks in step (%.2f m, %.2f m)" % [d1, d2])
	check(s.carriers.size() == 2 and absf(s.global_position.x - sp.x - d2) < 0.3, "the sheet goes with them (%.2f m)" % (s.global_position.x - sp.x))

	Input.action_release("p1_grab")
	await frames(60)
	check(s.carriers.is_empty() and not b1.carrying and not b2.carrying, "letting go drops it")
	check(absf(s.global_position.y - y) < 0.1, "and it lands flat on the ground (%.2f m)" % (s.global_position.y - y))
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 3000:
		check(false, "timed out")
		quit(1)
	return false
