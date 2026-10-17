extends SceneTree
# Bots solve Paper Plane Post with real input actions: P2 stands on an updraft
# plate while P1 picks up the paper plane (folded with the model, on the
# printed creases), turns it nose first and keel down in its hands, walks to
# the rim and throws it. On "gentle" it sinks below the ring, on "strong" it
# sails over the board (each time it's blown back to its start); on "steady"
# it hits, the bridge slides out and both walk over to the flag.
# Run:   godot --headless --fixed-fps 120 -s tests/solve_plane_post.gd   (exit code 0 = pass)
# Shots: godot --fixed-fps 120 -s tests/solve_plane_post.gd -- --shots=/some/dir   (needs a display)

const ROOM := 9
const T := PaperModel.THICKNESS * 0.5

var lvl
var room
var ok := true
var shots_dir := ""
var flight := "" ## how the last throw went


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
	if shots_dir != "":
		RenderingServer.render_loop_enabled = false # (see snap())
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)
	run.call_deferred()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


## Saves a screenshot. (Rendering is only switched on for these: drawn in
## software on a machine without a GPU, every frame would cost ~150 ms.)
func snap(name: String) -> void:
	if shots_dir != "":
		RenderingServer.render_loop_enabled = true
		await frames(3)
		root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))
		RenderingServer.render_loop_enabled = false


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func bean(pid: int):
	return lvl.players[pid - 1]


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Holds bean `pid`'s stick toward world direction `dir` (x, z). The camera
## starts looking down +X, so stick up = world +x and stick right = world +z.
func stick(pid: int, dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 1.0 else dir
	var s := Vector2(d.y, -d.x) # (right, down) stick axes
	for pair in [["right", maxf(s.x, 0.0)], ["left", maxf(-s.x, 0.0)], ["down", maxf(s.y, 0.0)], ["up", maxf(-s.y, 0.0)]]:
		if pair[1] > 0.01:
			Input.action_press("p%d_%s" % [pid, pair[0]], pair[1])
		else:
			Input.action_release("p%d_%s" % [pid, pair[0]])


func walk(pid: int, goal: Vector2, tol := 0.3, max_frames := 1200) -> bool:
	for i in max_frames:
		var d := goal - flat(bean(pid).global_position)
		if d.length() < tol:
			stick(pid, Vector2.ZERO)
			await frames(8)
			return true
		stick(pid, d.normalized() * clampf(d.length() * 1.5, 0.3, 1.0))
		await physics_frame
	stick(pid, Vector2.ZERO)
	return false


func tap(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(4)


# --- The plane ------------------------------------------------------------------

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


## The printed plane on a 4 x 6 sheet: the nose's corners to the middle, in
## half, and the wings out (nose toward -Z).
func plane() -> Array:
	var a := 2.0
	var b := 3.0
	var k := a / 3.0
	var fs := PaperModel.make_sheet(Vector2(2 * a, 2 * b))
	fs = fold(fs, Vector3(-a, T, -b), Vector3(0, T, a - b))
	fs = fold(fs, Vector3(a, T, -b), Vector3(0, T, a - b))
	fs = fold(fs, Vector3(-a, T, b), Vector3(a, T, b))
	fs = fold(fs, Vector3(a, T, b), Vector3(2 * k - a, T, b))
	fs = fold(fs, Vector3(a, T, b), Vector3(2 * k - a, -0.03, b))
	fs = fold(fs, Vector3(2 * k - a, T, b), Vector3(k, a - k, b))
	var gi := -1
	var low := 0
	for i in fs.size():
		var q: Vector3 = (fs[i] as PaperModel.Facet).xf.affine_inverse() * Vector3(2 * k - a, T, b)
		if absf(q.z) < 0.01 and Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), fs[i].pts) and (gi < 0 or fs[i].layer < low):
			gi = i
			low = fs[i].layer
	var r := PaperModel.plan_fold(fs, gi, Vector3(2 * k - a, T, b), Vector3(k, -(a - k), b), Vector3.UP)
	return r.facets if r.ok else []


## Whether the held plane points the way bean 1 faces, keel hanging below its
## wings.
func aimed(s: PaperSheet) -> bool:
	var fwd := Vector3(-sin(bean(1)._yaw), 0, -cos(bean(1)._yaw))
	var nose := s.global_basis * Vector3(0, 0, -1)
	var keel := 0.0
	var wings := 0.0
	for f in s.facets:
		var c: Vector3 = s.global_basis * f.at(PaperGeometry.centroid(f.pts))
		if absf(f.normal().y) > 0.9:
			keel += c.y / 4.0
		else:
			wings += c.y / 4.0
	return nose.dot(fwd) > 0.9 and keel < wings - 0.15


## P1 picks the plane up where it lies, aims it with the hand controls, walks
## to the rim and throws it. Returns whether it hit the ring.
func throw_plane(s: PaperSheet, aim := true) -> bool:
	await walk(1, flat(s.global_position) + Vector2(-2.5, 0), 0.3)
	await walk(1, flat(s.global_position) + Vector2(-1.5, 0), 0.2)
	Input.action_press("p1_sheet")
	await frames(2)
	Input.action_press("p1_grab")
	await frames(4)
	Input.action_release("p1_sheet")
	await frames(10)
	if bean(1).held_sheet != s:
		Input.action_release("p1_grab")
		flight = "not picked up"
		return false
	# Round end for end, and over a quarter at a time, until it's aimed.
	for turn in (4 if aim else 0):
		for r in 4:
			if aimed(s):
				break
			await tap("p1_mode")
		if aimed(s):
			break
		Input.action_press("p1_sheet")
		await tap("p1_mode")
		Input.action_release("p1_sheet")
		await frames(4)
	if aim and not aimed(s):
		Input.action_release("p1_grab")
		flight = "couldn't aim it"
		return false
	# To the rim, facing across, and throw.
	await walk(1, Vector2(-4, 0), 0.3)
	await walk(1, Vector2(-0.8, 0), 0.15)
	await frames(20)
	await snap("plane_aimed")
	Input.action_release("p1_grab")
	flight = "thrown"
	var crossed := false
	for i in 960:
		await physics_frame
		var nose := Vector3(-INF, 0, 0)
		for p in s._all_points():
			var w: Vector3 = s.global_transform * p
			if w.x > nose.x:
				nose = w
		if not crossed and nose.x > room.RING.x - 0.5:
			crossed = true
			flight += ", reached the board at height %.1f, %.1f off to the side" % [nose.y, nose.z]
		if room.hit:
			return true
		if i == 240:
			await snap("plane_flying")
	if not crossed:
		flight += ", %.1f m short of the board when it gave up" % (room.RING.x - (s.global_position + s.global_basis * s.center_of_mass).x)
	return false


func stand_on(pid: int, plate: int) -> void:
	var p: Node3D = room.plates[plate]
	await walk(pid, flat(p.global_position), 0.3)
	await frames(30)


## Waits until the sheet has been blown back to its start (it keeps its folds).
func wait_back(s: PaperSheet) -> bool:
	for i in 2400:
		await physics_frame
		if s.global_position.distance_to(s.spawn_transform.origin) < 1.0 and s.linear_velocity.length() < 0.2:
			await frames(60)
			return true
	return false


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	room = lvl.room
	var s: PaperSheet = room.sheet
	check(room.title == "Paper Plane Post", "the Paper Plane Post room loads")
	check(s.mass <= bean(1).LIFT_KG, "its sheet (%.1f kg) is light enough to pick up" % s.mass)
	# Flat, it won't go: it hangs in the rising air.
	await stand_on(2, 1)
	var r: bool = await throw_plane(s, false)
	check(not r and flight.contains("short"), "thrown flat on the steady updraft, the sheet doesn't get across (%s)" % flight)
	check(await wait_back(s), "it's blown back to its start")
	var pf := plane()
	check(pf.size() == 8, "the printed creases fold into a paper plane (%d facets)" % pf.size())
	s.facets = pf
	s._refresh()
	s.respawn() # (set down where it started, clear of the floor)
	await frames(240)
	await snap("plane_folded")

	# Too gentle: it sinks below the ring.
	await stand_on(2, 0)
	check(room.setting() == 0 and is_equal_approx(room.updraft.velocity.y, room.UPDRAFTS[0]), "P2 on the first plate: a gentle updraft")
	r = await throw_plane(s)
	check(not r, "on the gentle updraft the plane sinks below the ring (%s)" % flight)
	check(await wait_back(s), "it's blown back to its start, still a plane")
	# Too strong: over the board.
	await stand_on(2, 2)
	r = await throw_plane(s)
	check(not r, "on the strong updraft it sails over the board (%s)" % flight)
	check(await wait_back(s), "back again")
	# Just right.
	await stand_on(2, 1)
	check(room.setting() == 1, "P2 on the middle plate: a steady updraft")
	r = await throw_plane(s)
	check(r, "on the steady updraft it flies into the ring (%s)" % flight)
	await frames(360)
	check(room.bridge.position.x < 13.0, "the bridge slides out across the canyon")
	await snap("plane_bridge")

	# Over the bridge to the flag.
	for pid in [1, 2]:
		await walk(pid, Vector2(-2, 7), 0.4)
		await walk(pid, Vector2(31 + pid, 7), 0.5)
	await frames(10)
	check(lvl.complete or lvl.room_index != ROOM, "both cross the bridge to the flag: Paper Plane Post complete")
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 60000:
		check(false, "timed out")
		quit(1)
	return false
