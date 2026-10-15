extends SceneTree
# Regression test: bots solve level 1 using real input actions:
#   slide the sheet onto the island, fold its far strip up into a ramp (grab the
#   edge, raise hands, step back), ride the sheet to the ledge, walk up the ramp.
# Run:   godot --headless -s tests/solve_level.gd
# Shots: godot -s tests/solve_level.gd -- --shots=/some/dir   (needs a display)
# Exits 0 on success, 1 on failure. Time is measured in physics frames.

var lvl
var p1
var p2
var s: PaperSheet
var step := 0
var t0 := 0
var ok := true
var shots_dir := ""
var done := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)


func snap(n: String) -> void:
	if shots_dir != "" and not done.has("snap" + n):
		done["snap" + n] = true
		root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join(n + ".png"))


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
	if pf() > 6000:
		check(false, "timed out at step %d" % step)
		quit(1)
	match step:
		0:
			if pf() > 10:
				p1.global_position = Vector3(-3, 0.3, 3)
				p2.global_position = Vector3(-5, 0.3, -3)
				next()
		1: # slide the sheet back onto the island
			hold(["p1_sheet", "p1_down"], true)
			if s.position.x <= -19.0 or waited(900):
				hold(["p1_sheet", "p1_down"], false)
				check(s.position.x <= -18.9, "sheet slid onto the island (x=%.1f)" % s.position.x)
				next()
		2: # stand on the island just past the sheet's far edge
			p1.global_position = Vector3(-9.6, 0.2, 0)
			p2.global_position = Vector3(-24, 0.3, -2)
			next()
		3:
			if waited(20):
				check(p1.hover != null, "P1 can reach the sheet's far edge")
				snap("1_reach")
				hold(["p1_grab"], true)
				next()
		4: # raise hands
			hold(["p1_jump"], p1._lift < 2.6)
			if p1._lift >= 2.6 and waited(5):
				next()
		5: # step back so the edge comes up and over a little
			snap("2_lifting")
			hold(["p1_down"], true)
			if p1.global_position.x <= p1._grab_start_player.x - 0.6:
				hold(["p1_down"], false)
				snap("3_preview")
				hold(["p1_grab"], false)
				next()
		6:
			if waited(10):
				var tilt := 0.0
				for f in s.facets:
					tilt = maxf(tilt, rad_to_deg(f.normal().angle_to(Vector3.UP)))
				check(s.facets.size() == 2, "one fold made 2 facets")
				check(tilt > 15.0 and tilt < 40.0, "the strip stands up as a ramp (%.0f deg)" % tilt)
				snap("4_ramp")
				p1.global_position = Vector3(-24, 0.3, 2)
				next()
		7: # both ride the flat part while P1 slides the sheet to the ledge
			if waited(20):
				hold(["p1_sheet", "p1_up"], true)
				if s.position.x >= 5.4 or waited(900):
					hold(["p1_sheet", "p1_up"], false)
					check(s.position.x >= 5.3, "sheet slid up to the ledge (x=%.1f)" % s.position.x)
					check(p2.global_position.x > 0.0, "P2 rode along on the sheet")
					next()
		8:
			snap("5_at_ledge")
			if waited(20):
				next()
		9: # P1 walks up the ramp onto the ledge
			hold(["p1_up"], true)
			if p1.global_position.x >= 20.0 or waited(600):
				hold(["p1_up"], false)
				check(p1.global_position.y > 2.5 and p1.global_position.x > 14.0, "P1 walked up the ramp onto the ledge")
				next()
		10:
			hold(["p2_up"], true)
			if p2.global_position.x >= 20.0 or waited(600):
				hold(["p2_up"], false)
				check(p2.global_position.y > 2.5 and p2.global_position.x > 14.0, "P2 walked up the ramp onto the ledge")
				next()
		11:
			if waited(10):
				snap("6_goal")
				check(lvl.complete, "level complete")
				quit(0 if ok else 1)
	return false
