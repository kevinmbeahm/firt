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
var before_y := 0.0
var before_pos := Vector3.ZERO


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
	var res := {"ok": s._preview.ok, "reason": s._preview.reason,
		"theta": rad_to_deg(s._preview.get("theta", 0.0)), "status": s.fold_status}
	s.cancel_fold()
	return res


func _process(_d: float) -> bool:
	frame += 1
	var s: PaperSheet = lvl.sheet
	if frame == 30:
		# The puzzle sheet lies on the island; its right edge (local x=9) is over ground.
		var down := try_fold(s, 0, Vector3(9, T, 0), Vector3(8, -2, 0))
		check(not down.ok and down.reason.begins_with("blocked"), "folding a flap down into the ground is refused (%s)" % down.reason)
		for h in [0.0, -0.02, -0.1, -0.5]:
			var low := try_fold(s, 0, Vector3(9, T, 0), Vector3(-3, T + h, 0))
			check(low.ok and low.theta > 179.0, "a flat fold with hands %+.2f m from the paper goes over the top (theta %.0f %s)" % [h, low.theta, low.reason])
		var over := try_fold(s, 0, Vector3(9, T, 0), Vector3(-3, T + 0.5, 0))
		check(over.ok, "folding the same flap over the top is fine (%s)" % over.reason)
		var ramp_up := try_fold(s, 0, Vector3(9, T, 0), Vector3(8.4, 2.63, 0))
		check(ramp_up.ok and absf(ramp_up.theta - 26.0) < 2.0, "lifting a ramp off the floor is unaffected (theta %.0f)" % ramp_up.theta)

		# Hang the far edge over the island's side (z < -13) and fold it down.
		s.freeze = true
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 0, -12))
	elif frame == 32:
		var hang := try_fold(s, 0, Vector3(0, T, -6), Vector3(0, -2, -5))
		check(hang.ok and hang.status == "", "a flap over the void can be folded down to hang freely (%s)" % hang.reason)

		# Over the void nothing stops a flap going either way, so this is just
		# about following the hands: a flap carried over the top and then pressed
		# a little below the paper stays on top (pressed flat), instead of jumping
		# through the paper to underneath.
		var g := Vector3(0, T, -6)
		s.begin_fold(self)
		s.update_fold(0, g, Vector3(0, T + 0.3, -3), PaperModel.FOLD_NORMAL, true)
		var on_top: bool = s._preview.ok and s._preview.above
		s.update_fold(0, g, Vector3(0, T - 0.3, -3), PaperModel.FOLD_NORMAL, true)
		check(on_top and s._preview.ok and s._preview.above and absf(absf(s._preview.theta) - PI) < 1e-3,
			"hands pushed below the paper press a flap that's over the top flat, not through to underneath")
		s.cancel_fold()
		s.begin_fold(self)
		s.update_fold(0, g, Vector3(0, T - 0.3, -3), PaperModel.FOLD_NORMAL, true)
		check(s._preview.ok and not s._preview.above, "taken under from the start, the same flap folds underneath")
		s.cancel_fold()

		# Raised 1 m above the island, a flap lowered toward the floor stops on it.
		s.global_transform = Transform3D(Basis.IDENTITY, Vector3(-12, 1, 0))
	elif frame == 33:
		var rest := try_fold(s, 0, Vector3(9, T, 0), Vector3(8, -3, 0))
		check(rest.ok and rest.theta < -8.0 and rest.theta > -15.0 and rest.status.begins_with("resting"),
			"a flap lowered from a raised sheet comes to rest on the ground (theta %.1f, %s)" % [rest.theta, rest.status])

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
		# Folding a flap over onto someone standing on the paper puts them on top
		# of it; the sheet isn't shoved out from under them.
		lvl.players[1].place(Vector3(-8, 0.1, 2)) # on the big sheet's right half
	elif frame == 130:
		before_y = lvl.players[1].global_position.y
		before_pos = s.global_position
		s.begin_fold(self)
		check(s.finish_fold(0, Vector3(-9, T, 0), Vector3(6, T, 0)), "fold the left part of the sheet over onto P2")
	elif frame == 150:
		var flap := PaperModel.THICKNESS * 0.5 + PaperModel.LAYER_GAP # middle of the second layer
		check(before_y < flap - 0.01 and lvl.players[1].global_position.y > flap,
			"P2 ends up standing on top of the folded flap (%.3f -> %.3f m)" % [before_y, lvl.players[1].global_position.y])
		check(s.global_position.distance_to(before_pos) < 0.03, "the sheet stays put (moved %.3f m)" % s.global_position.distance_to(before_pos))
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
