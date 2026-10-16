extends SceneTree
# Bots solve Tight Squeeze with real input actions: fold the 12 x 12 sheet in
# half three times, slide the strip into the sizer box (the tunnel door opens
# only then), push it into the tunnel, go round by the passage and pull it out
# on the far side, unfold the last fold (undo) and slide it over the square.
# Checks on the way: the sheet unfolded doesn't fit the sizer, and the folded
# strip really goes through the tunnel.
# Run:   godot --headless -s tests/solve_squeeze.gd      (exit code 0 = pass)
# Shots: godot -s tests/solve_squeeze.gd -- --shots=/some/dir   (needs a display)

const ROOM := 3

var lvl
var ok := true
var shots_dir := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
	lvl = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)
	run.call_deferred()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


func snap(name: String) -> void:
	if shots_dir != "":
		await frames(2)
		root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))


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


func sheet_center() -> Vector2:
	var s: PaperSheet = lvl.sheet
	var b := s.world_box()
	return flat(s.global_position + b.get_center())


func sheet_size() -> Vector3:
	return lvl.sheet.world_box().size


## Bean `pid` (near the sheet) slides it until its middle reaches `goal`, or
## it stops moving (blocked, or out of reach).
func slide(pid: int, goal: Vector2, tol := 0.05) -> void:
	Input.action_press("p%d_sheet" % pid)
	var still := 0
	var last := sheet_center()
	for i in 1500:
		var d := goal - sheet_center()
		if d.length() < tol:
			break
		stick(pid, d.normalized() * clampf(d.length() * 0.8, 0.12, 1.0))
		await physics_frame
		still = still + 1 if sheet_center().distance_to(last) < 0.001 else 0
		last = sheet_center()
		if still > 60:
			break
	stick(pid, Vector2.ZERO)
	Input.action_release("p%d_sheet" % pid)
	await frames(40)


## A fold: bean `pid` stands at `at`, grabs the handle at `edge` and carries
## it (hands low) to `to`.
func fold(pid: int, at: Vector3, edge: Vector3, to: Vector2) -> bool:
	if not await grab_sheet(pid, at, edge):
		return false
	await move_hands(pid, to, 0.06)
	await let_go(pid)
	await frames(20)
	return true


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	var room = lvl.room
	var s: PaperSheet = lvl.sheet
	check(room.title == "Tight Squeeze", "the Tight Squeeze room loads")
	room.sizer.measure()
	check(not room.sizer.is_open and room.sizer.coverage < 0.5, "unfolded, the sheet doesn't fit the sizer")

	# 1. Fold it in half three times: a 3 x 6 m strip.
	check(await fold(1, Vector3(-18, 0.1, 6.9), Vector3(-18, 0, 6), Vector2(-18, -6)), "fold 1")
	check(await fold(1, Vector3(-24.9, 0.1, -3), Vector3(-24, 0, -3), Vector2(-12, -3)), "fold 2")
	check(await fold(1, Vector3(-15, 0.1, -6.9), Vector3(-15, 0, -6), Vector2(-15, 0)), "fold 3")
	var size := sheet_size()
	check(s.facets.size() == 8 and absf(size.x - 6.0) < 0.1 and absf(size.z - 3.0) < 0.1, "folded down to a 3 x 6 m strip (%d facets, %.1f x %.1f m)" % [s.facets.size(), size.z, size.x])

	# 2. Slide it into the sizer: the tunnel door opens.
	var c := sheet_center()
	bean(1).place(Vector3(c.x - 4.0, 0.1, c.y))
	await frames(10)
	await slide(1, Vector2(-8, 0))
	await frames(20)
	check(room.sizer.is_open, "in the sizer box, it fits: %s" % room.sizer.status())
	await frames(90)
	check(room.door.position.y < -0.5, "the tunnel door opens")
	await snap("squeeze_sizer")

	# 3. Push it into the tunnel as far as P1 can reach.
	await slide(1, Vector2(8, 0))
	check(sheet_center().x > -1.0, "P1 pushes it into the tunnel (middle at x=%.1f)" % sheet_center().x)

	# 4. P2 goes round by the passage and pulls it out the far side.
	var pz: float = (room.PASSAGE_Z.x + room.PASSAGE_Z.y) * 0.5
	await walk(2, Vector2(-6, pz), 0.3)
	await walk(2, Vector2(4, pz), 0.2)
	check(bean(2).global_position.x > 3.0, "P2 gets through the passage")
	await walk(2, Vector2(sheet_center().x + 2.5, 2.6), 0.3)
	await slide(2, Vector2(11, 0))
	check(sheet_center().x > 9.0, "P2 pulls it out on the far side (middle at x=%.1f)" % sheet_center().x)

	# 5. Unfold the last fold (undo) and lay it over the square.
	Input.action_press("undo")
	await frames(3)
	Input.action_release("undo")
	await frames(80)
	size = sheet_size()
	check(s.facets.size() == 4 and absf(size.x - 6.0) < 0.1 and absf(size.z - 6.0) < 0.1, "undo unfolds it to 6 x 6 m (%d facets)" % s.facets.size())
	var pad: Vector3 = room.PAD
	await walk(2, Vector2(sheet_center().x - 4.0, sheet_center().y), 0.3)
	await slide(2, Vector2(pad.x, pad.z))
	await frames(30)
	check(room.pad.is_open, "it covers the square (%s)" % room.status())
	await snap("squeeze_done")

	# 6. Both to the flag (P1 by the passage too).
	await walk(1, Vector2(-6, pz), 0.3)
	await walk(1, Vector2(4, pz), 0.2)
	await walk(1, Vector2(21, 7), 0.5)
	await walk(2, Vector2(23, 9), 0.5)
	await frames(10)
	check(lvl.complete, "both beans reach the flag: Tight Squeeze complete")
	release_all()
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 30000:
		check(false, "timed out")
		quit(1)
	return false
