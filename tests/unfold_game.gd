extends SceneTree
# In-game unfolding with real inputs: P1 folds a strip over by walking, then
# grabs the flap and walks it back roughly (drifting sideways). The flap should
# swing back about its old crease and lie flat again, with no new crease.
# Run:   godot --headless -s tests/unfold_game.gd      (exit code 0 = pass)

var lvl
var step := 0
var t0 := 0
var ok := true


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


func _process(_d: float) -> bool:
	var p1 = lvl.players[0]
	var s: PaperSheet = lvl.sheet
	if pf() > 6000:
		check(false, "timed out at step %d" % step)
		quit(1)
	match step:
		0:
			if pf() > 30:
				p1.global_position = Vector3(-2.4, 0.2, 0) # beside the sheet's far edge
				next()
		1:
			if pf() - t0 > 20:
				Input.action_press("p1_grab")
				Input.action_press("p1_down") # walk -X, carrying the edge over
				next()
		2:
			if p1.global_position.x <= -8.4:
				Input.action_release("p1_down")
				Input.action_release("p1_grab")
				next()
		3:
			if pf() - t0 > 30:
				check(s.facets.size() == 2 and s.facets[1].normal().y < -0.999, "P1 folded the strip flat over the sheet")
				check(p1.hover != null, "P1 can reach the folded flap")
				Input.action_press("p1_grab")
				next()
		4:
			if pf() - t0 > 5:
				check(p1.grabbing, "P1 grabs the flap")
				Input.action_press("p1_up")
				Input.action_press("p1_right") # drift sideways for a bit
				next()
		5:
			if pf() - t0 > 25:
				Input.action_release("p1_right")
			if p1.global_position.x >= -2.6:
				Input.action_release("p1_up")
				check(p1.fold_status() == "fold, hands +0.0 m", "the preview unfolds cleanly (%s)" % p1.fold_status())
				Input.action_release("p1_grab")
				next()
		6:
			if pf() - t0 > 30:
				var flat := s.facets.size() == 2
				for f in s.facets:
					flat = flat and f.normal().y > 0.999
				check(flat, "walking the flap back roughly (%.2f m off to the side) unfolds it along the old crease" % p1.global_position.z)
				quit(0 if ok else 1)
	return false
