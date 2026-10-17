extends SceneTree
# Air and wind (S6), on the Ramp room's start island: a flat sheet flutters
# down far slower than it would fall; a paper plane thrown level glides much
# further than the same paper folded into a compact block; wind pushes a
# sheet lying in it along, and an updraft holds one up; a bean picks the
# plane up, rolls it level and throws it with real inputs.
# Run:   godot --headless --fixed-fps 120 -s tests/air_physics.gd   (exit code 0 = pass)

const T := PaperModel.THICKNESS * 0.5

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


func facet_at(fs: Array, p: Vector3) -> int:
	var best := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		var q: Vector3 = f.xf.affine_inverse() * p
		if absf(q.z) > 0.01:
			continue
		var q2 := Vector2(q.x, q.y)
		var inside := Geometry2D.is_point_in_polygon(q2, f.pts)
		for k in f.pts.size():
			if Geometry2D.get_closest_point_to_segment(q2, f.pts[k], f.pts[(k + 1) % f.pts.size()]).distance_to(q2) < 0.01:
				inside = true
		if inside and (best < 0 or f.layer > fs[best].layer):
			best = i
	return best


func fold(fs: Array, g: Vector3, t: Vector3) -> Array:
	var gi := facet_at(fs, g)
	var r := PaperModel.plan_fold(fs, gi, g, PaperModel.snap_target(fs, gi, g, t), Vector3.UP)
	return r.facets if r.ok else []


## The paper plane from the fold-model test (6 x 8.5, nose toward -Z).
func plane_facets() -> Array:
	var fs := PaperModel.make_sheet(Vector2(6, 8.5))
	fs = PaperModel.plan_fold(fs, 0, Vector3(-3, T, -4.25), Vector3(0, T, -1.25), Vector3.UP).facets
	fs = fold(fs, Vector3(3, T, -4.25), Vector3(0, T, -1.25))
	fs = fold(fs, Vector3(-3, T, 4.25), Vector3(3, T, 4.25))
	fs = fold(fs, Vector3(3, T, 4.25), Vector3(-1, T, 4.25))
	fs = fold(fs, Vector3(3, T, 4.25), Vector3(-1, -0.03, 4.25))
	fs = fold(fs, Vector3(-1, T, 4.25), Vector3(1, 2.0, 4.25))
	var gi := -1
	var best := 0
	for i in fs.size():
		var q: Vector3 = (fs[i] as PaperModel.Facet).xf.affine_inverse() * Vector3(-1, T, 4.25)
		if absf(q.z) < 0.01 and Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), fs[i].pts) and (gi < 0 or fs[i].layer < best):
			gi = i
			best = fs[i].layer
	var r := PaperModel.plan_fold(fs, gi, Vector3(-1, T, 4.25), Vector3(1, -2.0, 4.25), Vector3.UP)
	return r.facets if r.ok else []


func new_sheet(fs: Array, xf: Transform3D) -> PaperSheet:
	var s: PaperSheet = lvl.room.add_sheet(Vector2(6, 8.5), xf.origin)
	s.facets = fs
	s._refresh()
	s.global_transform = xf
	s.linear_velocity = Vector3.ZERO
	s.angular_velocity = Vector3.ZERO
	return s


## Puts a test sheet away (freeing it would leave the level holding it).
func park(s: PaperSheet) -> void:
	s.global_transform = Transform3D(Basis(), Vector3(0, -100, 300 + randf() * 50))
	s.freeze = true


func lowest(s: PaperSheet) -> float:
	return s.global_position.y + s.world_box().position.y


## Flies `s` from `xf` at `v` until it touches down; returns [seconds, metres].
func fly(s: PaperSheet, xf: Transform3D, v: Vector3) -> Array:
	s.global_transform = xf
	s.angular_velocity = Vector3.ZERO
	s.linear_velocity = v
	s.freeze = false
	s.sleeping = false
	await physics_frame
	s.linear_velocity = v
	var start := xf.origin
	for i in 1200:
		await physics_frame
		if lowest(s) < 0.05:
			return [i / 120.0, Vector2(s.global_position.x - start.x, s.global_position.z - start.z).length()]
	return [10.0, Vector2(s.global_position.x - start.x, s.global_position.z - start.z).length()]


func run() -> void:
	await frames(30)
	lvl.load_room(0)
	await frames(30)
	var spot := Vector3(-20, 0, -8)

	# 1. A flat sheet dropped from 10 m.
	var flat := new_sheet(PaperModel.make_sheet(Vector2(6, 8.5)), Transform3D(Basis(), spot + Vector3.UP * 10.0))
	var t := 0.0
	for i in 1200:
		await physics_frame
		if lowest(flat) < 0.05:
			t = i / 120.0
			break
	check(t > 3.0, "a flat sheet flutters down from 10 m in %.1f s (it would fall in 1.4 s)" % t)
	park(flat)
	await frames(5)

	# 2. A plane thrown level vs the same paper folded into a block, and flat.
	var pf := plane_facets()
	check(pf.size() > 0, "a paper plane (%d facets)" % pf.size())
	# Nose to +X, rolled so the keel hangs below the wings.
	var best_xf := Transform3D()
	for roll in [PI * 0.5, -PI * 0.5]:
		var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3(0, 0, -1), roll)
		var keel := Vector3.ZERO
		var wings := Vector3.ZERO
		for f in pf:
			var c: Vector3 = b * f.at(PaperGeometry.centroid(f.pts))
			if absf(f.normal().y) > 0.9:
				keel += c
			else:
				wings += c
		if keel.y < wings.y:
			best_xf = Transform3D(b, Vector3.ZERO)
	var hi_xf := Transform3D(best_xf.basis, spot + Vector3(-8, 20.0, 0))
	var plane := new_sheet(pf, hi_xf)
	await frames(2)
	var pr: Array = await fly(plane, hi_xf, Vector3(10, 0, 0))
	park(plane)
	var block_fs := PaperModel.make_sheet(Vector2(6, 8.5))
	block_fs = fold(block_fs, Vector3(-3, T, 0), Vector3(3, T, 0))
	block_fs = fold(block_fs, Vector3(0, T, -4.25), Vector3(0, T, 4.25))
	var level_xf := Transform3D(Basis(), hi_xf.origin)
	var block := new_sheet(block_fs, level_xf)
	await frames(2)
	var br: Array = await fly(block, level_xf, Vector3(10, 0, 0))
	park(block)
	var fr: Array = await fly(flat, level_xf, Vector3(10, 0, 0))
	park(flat)
	check(pr[1] > br[1] + 8.0 and pr[1] > fr[1] + 8.0, "thrown level from 20 m, the plane glides %.1f m (%.1f s); the same paper folded into a block goes %.1f m, flat %.1f m" % [pr[1], pr[0], br[1], fr[1]])

	# 3. Wind: a sheet dropped in a crosswind drifts with it.
	var gust := Wind.new()
	gust.setup(spot + Vector3(0, 6, 0), Vector3(40, 14, 40), Vector3(0, 0, 5))
	lvl.room.add_child(gust)
	var drop := Transform3D(Basis(), spot + Vector3.UP * 10.0)
	var dr: Array = await fly(flat, drop, Vector3.ZERO)
	var drift := flat.global_position.z - drop.origin.z
	check(drift > 4.0, "dropped in a 5 m/s crosswind, a flat sheet drifts %.1f m downwind (%.1f s)" % [drift, dr[0]])
	park(flat)
	# ...and an updraft holds it up.
	gust.velocity = Vector3(0, 6, 0)
	flat.global_transform = Transform3D(Basis(), spot + Vector3.UP * 6.0)
	flat.linear_velocity = Vector3.ZERO
	flat.angular_velocity = Vector3.ZERO
	flat.freeze = false
	flat.sleeping = false
	var low := 100.0
	for i in 600:
		await physics_frame
		if i > 120:
			low = minf(low, lowest(flat))
	check(low > 2.0, "in a 6 m/s updraft it hangs in the air (no lower than %.1f m over 4 s)" % low)
	park(flat)
	gust.queue_free()
	await frames(5)

	# 4. A bean picks a light sheet up, rolls it on edge and throws it.
	var light := new_sheet(PaperModel.make_sheet(Vector2(4, 6)), Transform3D(Basis(), spot + Vector3(0, 0.2, 0)))
	check(light.mass <= 25.0, "a 4 x 6 sheet weighs %.1f kg: light enough to lift" % light.mass)
	var b1 = lvl.players[0]
	lvl.players[1].place(spot + Vector3(-10, 0.2, 8))
	b1.place(spot + Vector3(-3.0, 0.2, 0))
	await frames(60)
	Input.action_press("p1_sheet")
	await frames(2)
	Input.action_press("p1_grab")
	await frames(2)
	Input.action_release("p1_sheet")
	await frames(30)
	check(b1.held_sheet == light, "sheet + grab picks it up")
	check(light.global_position.y > 2.0, "it's held over the bean's head (%.1f m up)" % light.global_position.y)
	var up0: Vector3 = light.global_basis.y
	Input.action_press("p1_mode")
	await frames(2)
	Input.action_release("p1_mode")
	await frames(10)
	check(absf(light.global_basis.y.dot(up0)) < 0.2, "the mode key rolls it on edge")
	Input.action_press("p1_mode") # (and flat again, upside down, to throw)
	await frames(2)
	Input.action_release("p1_mode")
	await frames(10)
	b1._yaw = -PI * 0.5
	await frames(10)
	var from: Vector3 = light.global_position
	Input.action_release("p1_grab")
	await frames(2)
	check(b1.held_sheet == null and not light.freeze, "letting go throws it")
	var gone := 0.0
	for i in 360:
		await physics_frame
		gone = maxf(gone, light.global_position.x - from.x)
	check(gone > 5.0, "thrown flat, it sails %.1f m the way the bean faces" % gone)
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 20000:
		check(false, "timed out")
		quit(1)
	return false
