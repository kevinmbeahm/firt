extends SceneTree
# Bots ride the Zipline with real input actions: fold the sheet in half on its
# printed line, carry it up to the cable together until the crease hooks on,
# ride it down hanging on, let go over the island and walk to the flag. Then a
# rule check: a short hook (a corner folded over) holds one bean but slips off
# under two.
# Run:   godot --headless -s tests/solve_zipline.gd      (exit code 0 = pass)
# Shots: godot -s tests/solve_zipline.gd -- --shots=/some/dir   (needs a display)

const ROOM := 10

var lvl
var ok := true
var shots_dir := ""


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


## Holds bean `pid`'s stick toward world direction `dir` (x, z). These rooms
## start with the camera looking down +X, so stick up = world +x and stick
## right = world +z.
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


## Moves bean `pid`'s grabbed point (its hands) to `goal`.
func move_hands(pid: int, goal: Vector2, tol := 0.08) -> void:
	for i in 900:
		var d := goal - flat(bean(pid)._hands_world())
		if d.length() < tol:
			break
		stick(pid, d.normalized() * clampf(d.length() * 1.5, 0.25, 1.0))
		await physics_frame
	stick(pid, Vector2.ZERO)
	await frames(10)


func lift_to(pid: int, lift: float) -> void:
	var b = bean(pid)
	var action := "p%d_jump" % pid if lift > b._lift else "p%d_lower" % pid
	Input.action_press(action)
	for i in 400:
		if absf(b._lift - lift) < 0.05:
			break
		await physics_frame
	Input.action_release(action)


## Places bean `pid` at `at` and grabs the sheet handle nearest `handle`.
func grab_sheet(pid: int, at: Vector3, handle: Vector3) -> bool:
	var b = bean(pid)
	b.place(at)
	await frames(15)
	if b.hover == null or b.hover.has("prop") or (b.hover.world as Vector3).distance_to(handle) > 1.0:
		print("      hover: %s" % [b.hover])
		return false
	Input.action_press("p%d_grab" % pid)
	await frames(3)
	return b.grabbing


func let_go(pid: int) -> void:
	Input.action_release("p%d_grab" % pid)
	await frames(10)


func release_all() -> void:
	for pid in [1, 2]:
		for a in ["left", "right", "up", "down", "jump", "lower", "grab", "sheet"]:
			Input.action_release("p%d_%s" % [pid, a])


func cable_y(x: float) -> float:
	var room = lvl.room
	var a: Vector3 = room.CABLE_FROM
	var b: Vector3 = room.CABLE_TO
	return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	var room = lvl.room
	var s: PaperSheet = lvl.sheet
	check(room.title == "Zipline Delivery", "the Zipline room loads")

	# 1. Fold the sheet in half on its printed line: far edge over to the near one.
	check(await grab_sheet(1, Vector3(-12, 0.1, 8.9), Vector3(-12, 0, 8)), "P1 grabs the far edge")
	await move_hands(1, Vector2(-12, 2.0))
	await let_go(1)
	check(s.facets.size() == 2 and s.crease_segments().size() == 1, "folded in half: one crease (%d facets)" % s.facets.size())
	await walk(1, Vector2(-14, 8.5))

	# 2. Take the crease's two ends and lift them to the cable's height there.
	check(await grab_sheet(1, Vector3(-17.9, 0.1, 5), Vector3(-17, 0, 5)), "P1 takes the uphill end of the crease")
	check(await grab_sheet(2, Vector3(-6.1, 0.1, 5), Vector3(-7, 0, 5)), "P2 takes the downhill end")
	check(s.carriers.size() == 2, "they're carrying it together")
	await lift_to(1, cable_y(-17) - 0.1)
	await lift_to(2, cable_y(-7) - 0.1)
	# 3. Walk it in under the cable until the crease hooks on.
	for i in 600:
		if s.is_hooked():
			break
		stick(1, Vector2(0, -0.5))
		stick(2, Vector2(0, -0.5))
		await physics_frame
	stick(1, Vector2.ZERO)
	stick(2, Vector2.ZERO)
	check(s.is_hooked(), "the crease hooks onto the cable (%s)" % s.hook_status())
	check(bean(1).riding and bean(2).riding, "and both beans are hanging on to it")
	check(s.hook_len > 8.0, "the whole 10 m crease is on the cable (%.1f m)" % s.hook_len)
	await frames(60)
	await snap("zipline_hooked")

	# 4. Ride it down.
	var moved := false
	for i in 2400:
		if s.hook_speed > 0.5:
			moved = true
		if moved and absf(s.hook_speed) < 0.01 and i > 200:
			break
		await physics_frame
	check(moved, "it slides down the cable with them")
	check(s.is_hooked() and bean(1).riding and bean(2).riding, "still hooked, both still hanging on")
	var over := 0
	for pid in [1, 2]:
		var p: Vector3 = bean(pid).global_position
		if p.x > 13.0 and p.x < 33.0 and p.y > room.ISLAND_Y:
			over += 1
	check(over == 2, "it stops at the end with both of them over the island")
	await snap("zipline_ride")
	await let_go(1)
	await let_go(2)
	await frames(90)
	for pid in [1, 2]:
		var p: Vector3 = bean(pid).global_position
		check(bean(pid).is_on_floor() and absf(p.y - room.ISLAND_Y) < 0.3, "P%d lets go and lands on the island (y=%.1f)" % [pid, p.y])
	await walk(1, Vector2(29, 3), 0.5)
	await walk(2, Vector2(31, 5), 0.5)
	await frames(10)
	check(lvl.complete, "both beans reach the flag: Zipline complete")
	release_all()

	# A short hook: a corner folded over the cable holds one bean, not two.
	lvl.load_room(ROOM)
	await frames(40)
	s = lvl.sheet
	check(await grab_sheet(1, Vector3(-6.2, 0.1, 8.8), Vector3(-7, 0, 8)), "P1 grabs a corner")
	await move_hands(1, Vector2(-9, 6.0), 0.06)
	await let_go(1)
	var segs := s.crease_segments()
	check(segs.size() == 1, "one crease across the corner (%d)" % segs.size())
	var crease_len: float = (segs[0][1] - segs[0][0]).length()
	# (Hung on the cable by hand: the bots can't lift a corner fold up there.)
	var cable = get_root_cable()
	s._hook({"cable": cable, "a": segs[0][0], "b": segs[0][1], "len": crease_len})
	await frames(2)
	for pid in [1, 2]: # (each where they'd hang from their end of the crease)
		bean(pid).place(s.to_global(segs[0][pid - 1]) - Vector3.UP * Player.HANG)
	await frames(3)
	Input.action_press("p1_grab")
	s.add_rider(bean(1), segs[0][0])
	await frames(30)
	check(bean(1).riding, "P1 hangs on")
	check(s.is_hooked(), "a %.1f m crease holds the sheet and one bean (%d of %d kg)" % [crease_len, roundi(s.hook_load()), roundi(s.hook_capacity())])
	Input.action_press("p2_grab") # (bean 2 grabs on too)
	s.add_rider(bean(2), segs[0][1])
	await frames(5)
	check(not s.is_hooked() and s.hook_note.contains("slipped"), "with two hanging on it slips off (%s)" % s.hook_note)
	check(not bean(1).riding and not bean(2).riding, "and they drop")
	release_all()
	quit(0 if ok else 1)


func get_root_cable() -> Cable:
	return root.get_tree().get_nodes_in_group("cables")[0]


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 20000:
		check(false, "timed out")
		quit(1)
	return false
