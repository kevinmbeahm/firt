extends SceneTree
# Solo play with real inputs: P1 grabs the ramp room's sheet and lifts a flap,
# swaps to the other bean while still holding grab (bean 1 keeps holding the
# fold live), walks bean 2 around, swaps back, takes over the hold and lets go
# to crease it.
# Run:   godot --headless -s tests/solo_swap.gd      (exit code 0 = pass)

var lvl
var b1
var b2
var step := 0
var t0 := 0
var ok := true
var mark := Vector3.ZERO


func _initialize() -> void:
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


func pf() -> int:
	return Engine.get_physics_frames()


func next() -> void:
	step += 1
	t0 = pf()


func waited(n: int) -> bool:
	return pf() - t0 >= n


func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)


func _process(_d: float) -> bool:
	b1 = lvl.players[0]
	b2 = lvl.players[1]
	var s: PaperSheet = lvl.sheet
	if pf() > 6000:
		check(false, "timed out at step %d" % step)
		quit(1)
	match step:
		0:
			if pf() > 30:
				b1.place(Vector3(-2.4, 0.2, 0)) # just past the big sheet's far edge
				b2.place(Vector3(-16, 0.3, -2))
				next()
		1:
			if waited(20):
				check(b1.hover != null, "bean 1 can reach the sheet's edge")
				Input.action_press("p1_grab")
				next()
		2: # raise hands and step back: the far strip comes up as a ramp
			Input.action_press("p1_jump")
			Input.action_press("p1_down")
			if waited(60):
				Input.action_release("p1_jump")
				Input.action_release("p1_down")
				check(b1.grabbing and s.fold_owner == b1, "bean 1 holds the sheet")
				tap("p1_swap") # still holding grab
				next()
		3:
			if waited(5):
				Input.action_release("p1_grab")
				check(lvl.solo and b1.controlled_by == 0 and b2.controlled_by == 1, "swapped: P1's controls now drive bean 2")
				mark = b1.global_position
				next()
		4: # walk bean 2 with P1's keys; bean 1 keeps holding
			Input.action_press("p1_right")
			if waited(60):
				Input.action_release("p1_right")
				check(b2.global_position.distance_to(Vector3(-16, 0.3, -2)) > 1.0, "P1's keys move bean 2 (%.1f m)" % b2.global_position.distance_to(Vector3(-16, 0.3, -2)))
				check(b1.global_position.distance_to(mark) < 0.2, "bean 1 stays put")
				check(b1.grabbing and s.fold_owner == b1 and s._preview.get("ok", false), "bean 1 still holds the flap up (live fold)")
				check(s.facets.size() == 1, "nothing is creased yet")
				tap("p1_swap")
				next()
		5:
			if waited(10):
				check(b1.controlled_by == 1 and b2.controlled_by == 2, "swapped back: bean 2 is P2's again")
				check(b1.grabbing, "bean 1 is still holding after P1 comes back without pressing grab")
				Input.action_press("p1_grab") # take over the hold...
				next()
		6:
			if waited(5):
				Input.action_release("p1_grab") # ...and let go
				next()
		7:
			if waited(10):
				check(not b1.grabbing and s.facets.size() == 2, "letting go creases the fold (%d facets)" % s.facets.size())
				quit(0 if ok else 1)
	return false
