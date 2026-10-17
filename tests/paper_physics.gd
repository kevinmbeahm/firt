extends SceneTree
# Physics test: paper rests on the ground, tips and falls when pushed too far
# over an edge, comes back if lost, and players' weight can tip an overhang.
# Run:   godot --headless -s tests/paper_physics.gd      (exit code 0 = pass)

var lvl
var p1
var p2
var s: PaperSheet
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


func waited(n: int) -> bool:
	return pf() - t0 >= n


func next() -> void:
	step += 1
	t0 = pf()


func hold(actions: Array, on: bool) -> void:
	for a in actions:
		if on:
			Input.action_press(a)
		else:
			Input.action_release(a)


func _process(_d: float) -> bool:
	p1 = lvl.players[0]
	p2 = lvl.players[1]
	s = lvl.sheet
	if pf() > 12000:
		check(false, "timed out at step %d" % step)
		quit(1)
	match step:
		0:
			if pf() > 240:
				check(absf(s.global_position.y) < 0.05 and s.linear_velocity.length() < 0.05,
					"sheet rests on the island (y=%.3f)" % s.global_position.y)
				var sb: PaperSheet = lvl.sheets[1]
				check(absf(sb.global_position.y) < 0.05, "sandbox sheet rests too")
				# P1 stands beside the sheet (not on it) and slides it off the
				# island's side edge (z=-13); the camera looks along +X so "left" is -Z.
				p1.global_position = Vector3(-22, 0.1, 5)
				next()
		1:
			hold(["p1_sheet", "p1_left"], true)
			if s.global_position.y < -3.0 or waited(2400):
				hold(["p1_sheet", "p1_left"], false)
				check(s.global_position.y < -3.0, "pushed past its balance point, the sheet tips into the void")
				next()
		2:
			if s.global_position.y > -1.0 and s.global_position.distance_to(lvl.room.PUZZLE_START) < 0.5:
				check(true, "the lost sheet respawned at its start")
				next()
			elif waited(3600):
				check(false, "the lost sheet respawned at its start (y=%.1f)" % s.global_position.y)
				next()
		3: # slide it out to overhang the edge by a bit less than half: still balanced
			if pf() - t0 == 1:
				p1.global_position = Vector3(-22, 0.1, 5)
			if waited(120):
				hold(["p1_sheet", "p1_left"], true)
				if s.global_position.z <= -12.0:
					hold(["p1_sheet", "p1_left"], false)
					next()
				elif waited(2400):
					hold(["p1_sheet", "p1_left"], false)
					check(false, "slid the sheet out to z=-12 (z=%.2f)" % s.global_position.z)
					next()
		4:
			if waited(240):
				check(s.global_position.y > -0.2, "a sheet hanging 5 m over the edge stays balanced (z=%.2f y=%.2f)" % [s.global_position.z, s.global_position.y])
				# Both players walk out onto the overhanging end.
				p1.global_position = s.global_position + Vector3(-2, 0.4, -5.5)
				p2.global_position = s.global_position + Vector3(2, 0.4, -5.5)
				next()
		5:
			if s.global_position.y < -3.0:
				check(true, "the players' weight on the overhang tips it over")
				quit(0 if ok else 1)
			elif waited(600):
				check(false, "the players' weight on the overhang tips it over (y=%.2f)" % s.global_position.y)
				quit(0 if ok else 1)
	return false
