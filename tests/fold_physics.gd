extends SceneTree
# Regression tests for how folding interacts with the world and the rigid body:
# folds can't swing paper through the ground, solid things or other paper;
# buried layers can't be grabbed; undo needs room; falling sheets can't be
# steered; grabs end cleanly; sheets respawn the right way round.
# Run:   godot --headless -s tests/fold_physics.gd      (exit code 0 = pass)

const T := PaperModel.THICKNESS * 0.5
var lvl
var ok := true
var frame := 0
var falling: PaperSheet


func _initialize() -> void:
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


## Previews a fold on `s` and returns {ok, reason} without committing it.
func try_fold(s: PaperSheet, facet: int, g: Vector3, t: Vector3) -> Dictionary:
	s.begin_fold(self)
	s.update_fold(facet, g, t)
	var res := {"ok": s._preview.ok, "reason": s._preview.reason}
	s.cancel_fold()
	return res


func _process(_d: float) -> bool:
	frame += 1
	var s: PaperSheet = lvl.sheet
	if frame == 30:
		# The puzzle sheet lies on the island; its right edge (local x=9) is over ground.
		var down := try_fold(s, 0, Vector3(9, T, 0), Vector3(8, -2, 0))
		check(not down.ok and down.reason.begins_with("blocked"), "folding a flap down into the ground is refused (%s)" % down.reason)
		var under := try_fold(s, 0, Vector3(9, T, 0), Vector3(-3, T - 0.5, 0))
		check(not under.ok and under.reason.begins_with("blocked"), "folding a flap under a sheet lying on the floor is refused (%s)" % under.reason)
		var over := try_fold(s, 0, Vector3(9, T, 0), Vector3(-3, T + 0.5, 0))
		check(over.ok, "folding the same flap over the top is fine (%s)" % over.reason)

		# Hang the far edge over the island's side (z < -13) and fold it down.
		s.freeze = true
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, -12))
	elif frame == 32:
		var hang := try_fold(s, 0, Vector3(0, T, -6), Vector3(0, -2, -5))
		check(hang.ok, "a flap over the void can be folded down to hang (%s)" % hang.reason)

		# Undo needs room: fold a ramp, park the sheet so the flat strip would be inside the ledge.
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, 0))
	elif frame == 34:
		s.begin_fold(self)
		var ramp := s.finish_fold(0, Vector3(9, T, 0), Vector3(8.4, 2.63, 0))
		check(ramp, "fold a ramp")
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	elif frame == 36:
		check(not s.undo(), "undo is refused when the unfolded strip would be inside the ledge")
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, 0))
	elif frame == 38:
		check(s.undo(), "...and allowed again once there's room")
		# Turning the big sheet 45 deg right next to the ledge would push a corner into it.
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.5, 0, 0))
		s.turn(PI * 0.25)
		check(not s.is_busy(), "turning a sheet into the ledge is refused")
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, 0))
		s.turn(PI * 0.25)
		check(s.is_busy(), "turning it out in the open works")
		s.freeze = false
		model_tests()

		# A sheet in free fall can't be steered with the slide control.
		falling = lvl.sheets[1]
		falling.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 30, 40))
		falling.linear_velocity = Vector3.ZERO
	elif frame == 39:
		pass
	elif frame > 40 and frame < 70:
		falling.push(Vector3(3, 0, 0))
	elif frame == 70:
		if s.is_busy():
			frame -= 1 # let the test turn finish first
			return false
		check(absf(falling.linear_velocity.x) < 0.1 and falling.linear_velocity.y < -1.0,
			"a falling sheet ignores the slide control (vx=%.2f vy=%.2f)" % [falling.linear_velocity.x, falling.linear_velocity.y])
		var yaw_x: Vector3 = falling.spawn_transform.basis.x
		check(yaw_x.distance_to(Vector3(0, 0, -1)) < 0.01, "the sandbox sheet respawns turned the way it started")

		# Grab ends cleanly when the sheet drops the fold.
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, 0)) # undo the test turn
		var p1 = lvl.players[0]
		p1.global_position = Vector3(-2.4, 0.2, 0)
	elif frame == 90:
		Input.action_press("p1_grab")
	elif frame == 95:
		check(lvl.players[0].grabbing, "P1 grabs the sheet's edge")
		s.cancel_fold()
	elif frame == 100:
		check(not lvl.players[0].grabbing, "P1 lets go when the sheet cancels the fold")
		Input.action_release("p1_grab")
		quit(0 if ok else 1)
	return false


func model_tests() -> void:
	# Paper can't end up passing through other paper: stand a wall up at x=1,
	# then try to lean the left half over through it.
	var fs := PaperModel.make_sheet(Vector2(6, 6))
	var wall := PaperModel.plan_fold(fs, 0, Vector3(3, T, 0), Vector3(1, T + 2, 0), Vector3.UP)
	check(wall.ok, "stand a strip up as a wall")
	fs = wall.facets
	var lean := PaperModel.plan_fold(fs, _facet_at(fs, Vector3(-3, T, 0)), Vector3(-3, T, 0),
		Vector3(2.12, T + 2.12, 0), Vector3.UP)
	check(not lean.ok and lean.reason == "would pass through other paper", "leaning a flap through the wall is refused (%s)" % lean.reason)
	var upright := PaperModel.plan_fold(fs, _facet_at(fs, Vector3(-3, T, 0)), Vector3(-3, T, 0),
		Vector3(0, T + 3, 0), Vector3.UP)
	check(upright.ok, "standing it up beside the wall is fine (%s)" % upright.reason)

	# Buried corners can't be grabbed: fold a corner in, then cover it.
	var sh := PaperModel.make_sheet(Vector2(4, 4))
	var r := PaperModel.plan_fold(sh, 0, Vector3(-2, T, -2), Vector3(-1, T, -1), Vector3.UP)
	sh = r.facets
	var tip := Vector3(-1, T, -1)
	check(_handle_near(sh, tip), "the folded corner's tip can be grabbed while exposed")
	r = PaperModel.plan_fold(sh, _facet_at(sh, Vector3(2, T, 0)), Vector3(2, T, 0), Vector3(-2, T, 0), Vector3.UP)
	check(r.ok, "fold the other half over it")
	check(not _handle_near(r.facets, tip), "once covered, that tip can't be grabbed")


func _handle_near(fs: Array, p: Vector3) -> bool:
	for h in PaperModel.handles(fs, PaperModel.stack_offsets(fs), Vector3.UP):
		if (h.local as Vector3).distance_to(p) < 0.2:
			return true
	return false


func _facet_at(fs: Array, p: Vector3) -> int:
	var best := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		var q: Vector3 = f.xf.affine_inverse() * p
		if absf(q.z) < 0.01 and Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), PaperGeometry.inset(f.pts, -0.01)):
			if best < 0 or f.layer > fs[best].layer:
				best = i
	return best
