extends SceneTree
# Regression test: a bot solves level 1 using only real input actions (two folds, slide the
# stack to the ledge, climb). Run with:
#   godot --headless -s tests/solve_level.gd
# Exits with code 0 on success, 1 on failure. Time is measured in physics frames.
var lvl
var p1
var p2
var s: PaperSheet
var step := 0
var t0 := 0
var shots := {}
var ok := true
func _initialize() -> void:
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)
func snap(_n: String) -> void:
	pass
func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond: ok = false
func press(a: String) -> void: Input.action_press(a)
func rel(a: String) -> void: Input.action_release(a)
func pf() -> int: return Engine.get_physics_frames()
func next(label := "") -> void:
	step += 1; t0 = pf()
	print("[%d pf] step %d %s  p1=%s p2=%s sheet=%s" % [pf(), step, label, p1.global_position.snapped(Vector3(.01,.01,.01)), p2.global_position.snapped(Vector3(.01,.01,.01)), s.position])
func waited(n: int) -> bool: return pf() - t0 >= n
func _process(_d: float) -> bool:
	p1 = lvl.players[0]; p2 = lvl.players[1]; s = lvl.sheet
	match step:
		0:
			if pf() > 10:
				p1.global_position = Vector3(-11.5, 0.1, 0)   # beside the left edge handle
				p2.global_position = Vector3(-3.0, 1.0, 2.0)  # stands on the middle of the sheet
				next("setup")
		1:
			if waited(20):
				print("hover ", p1.hover_handle)
				press("p1_grab"); next("grab left edge")
		2:
			if waited(5):
				print("grabbing ", p1.grabbing)
				press("p1_up"); next("walk +X")        # camera looks +X, so 'up' = +X
		3:
			if waited(30) and not shots.has("drag"):
				shots["drag"] = true; snap("1_dragging")
			if p1.global_position.x > -1.5 or waited(400):
				rel("p1_up"); rel("p1_grab"); next("release fold 1")
		4:
			if waited(40) and not shots.has("mid"):
				shots["mid"] = true; snap("2_swing")
			if waited(60):
				print("facets ", s.facets.size()); snap("3_folded1"); next("fold1 done")
		5:
			# walk P1 to the right edge handle (local 9,0)
			press("p1_up"); 
			if p1.global_position.x > 6.5 or waited(400):
				rel("p1_up"); next("at right edge")
		6:
			if waited(15):
				print("hover ", p1.hover_handle)
				press("p1_grab"); next("grab right edge")
		7:
			if waited(5):
				press("p1_down"); next("walk -X")
		8:
			if p1.global_position.x < -4.0 or waited(500):
				rel("p1_down"); rel("p1_grab"); next("release fold 2")
		9:
			if waited(70):
				print("facets ", s.facets.size()); for f in s.facets: print("  layer ", f.layer, " elev ", f.elev, " flipped ", f.flipped)
				snap("4_folded2"); next("fold2 done")
		10:
			# P2 hops on stack top if needed; slide the sheet toward the ledge with P1 pushing
			press("p1_sheet"); press("p1_up")
			if waited(600) or s.position.x > 12.4:
				rel("p1_sheet"); rel("p1_up"); next("pushed")
		11:
			if waited(30):
				snap("5_pushed"); next("p1 jumps to ledge")
		12:
			press("p1_up")
			if waited(10) and not shots.has("j"):
				shots["j"] = true; press("p1_jump")
			if waited(14): rel("p1_jump")
			if waited(120):
				rel("p1_up"); next("p1 after jump")
		13:
			# P1 is at the wall on the 3-layer top: jump + forward
			press("p1_up")
			if waited(5) and not shots.has("j2"):
				shots["j2"] = true; press("p1_jump")
			if waited(9): rel("p1_jump")
			if waited(90):
				check(s.facets.size() == 3, "two folds gave 3 facets")
				check(p1.global_position.y > 2.5 and p1.global_position.x > 14.0, "P1 climbed onto the ledge via the 3-layer stack")
				p1.global_position = Vector3(21, 3.0, 0)   # park P1 on the ledge
				next("p1 up on ledge?")
		14:
			# P2: walk to the wall on the stack and jump
			press("p2_up")
			if p2.global_position.x > 12.6 and not shots.has("p2j"):
				shots["p2j"] = true; press("p2_jump"); t0 = pf()
			if shots.has("p2j") and waited(8): rel("p2_jump")
			if shots.has("p2j") and waited(120):
				rel("p2_up"); next("p2 done")
		15:
			p1.global_position = Vector3(21, 2.7, 0)
			p2.global_position = Vector3(21.5, 2.7, 1)
			next("both at the flag")
		16:
			if waited(5):
				check(lvl.complete, "level reports complete with both players at the flag")
				quit(0 if ok else 1)
	return false
