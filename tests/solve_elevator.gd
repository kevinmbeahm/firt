extends SceneTree
# Bots solve the Paper Elevator with real input actions: fold the sheet in
# half, carry it up to the hook bar together until it hooks on; one hangs on
# while the other stands on the bottom plate, rides up and hops off onto the
# ledge; then the first steps off the plate (the lift comes down), hangs on,
# and the one up top brings it back up from the top plate.
# Run:   godot --headless -s tests/solve_elevator.gd      (exit code 0 = pass)
# Shots: godot -s tests/solve_elevator.gd -- --shots=/some/dir   (needs a display)

const ROOM := 6

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


## Waits (up to `n` frames) until the lift is at height `y`.
func lift_at(y: float, n := 900) -> bool:
	for i in n:
		if absf(lvl.room.lift.position.y - y) < 0.02:
			return true
		await physics_frame
	return false


## Bean `pid` lets go of its ride while pushing toward `dir`: hops off.
func hop(pid: int, dir: Vector2) -> void:
	stick(pid, dir)
	await frames(2)
	Input.action_release("p%d_grab" % pid)
	await frames(60)
	stick(pid, Vector2.ZERO)
	await frames(120)


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	var room = lvl.room
	var s: PaperSheet = lvl.sheet
	check(room.title == "Paper Elevator", "the Paper Elevator room loads")
	check(not room.lift_up() and absf(room.lift.position.y - room.BAR_Y) < 0.01, "the lift waits at the bottom")

	# 1. Fold the sheet in half on its line.
	check(await grab_sheet(1, Vector3(-8, 0.1, 3.4), Vector3(-8, 0, 2.5)), "P1 grabs the far edge")
	await move_hands(1, Vector2(-8, -2.5))
	await let_go(1)
	check(s.crease_segments().size() == 1, "folded in half")
	await walk(1, Vector2(-11, 3))

	# 2. Carry it up to the bar until the crease hooks on.
	check(await grab_sheet(1, Vector3(-11.9, 0.1, 0), Vector3(-11, 0, 0)), "P1 takes one end of the crease")
	check(await grab_sheet(2, Vector3(-4.1, 0.1, 0), Vector3(-5, 0, 0)), "P2 takes the other")
	await lift_to(1, room.BAR_Y - 0.08)
	await lift_to(2, room.BAR_Y - 0.08)
	for i in 900:
		if s.is_hooked():
			break
		stick(1, Vector2(1, 0))
		stick(2, Vector2(1, 0))
		await physics_frame
	stick(1, Vector2.ZERO)
	stick(2, Vector2.ZERO)
	check(s.is_hooked() and bean(1).riding and bean(2).riding, "the crease hooks onto the bar; both hang on (%s)" % s.hook_status())
	await frames(60)

	# 3. P1 drops off and stands on the plate; P2 rides up and hops onto the ledge.
	await let_go(1)
	await frames(30)
	await walk(1, Vector2(-11, -6), 0.4)
	check(room.low_plate.is_pressed and room.lift_up(), "P1 on the bottom plate: the lift goes up")
	check(await lift_at(room.TOP_Y), "it reaches the top")
	check(bean(2).riding and bean(2).global_position.y > room.LEDGE_Y, "with P2 hanging on, above the ledge (y=%.1f)" % bean(2).global_position.y)
	await snap("elevator_top")
	await hop(2, Vector2(1, 0))
	check(not bean(2).riding and bean(2).is_on_floor() and absf(bean(2).global_position.y - room.LEDGE_Y) < 0.3, "P2 hops off onto the ledge")

	# 4. P1 steps off the plate: the lift comes back down. P1 hangs on.
	await walk(1, Vector2(-6, -3), 0.4)
	check(await lift_at(room.BAR_Y), "off the plate, the lift comes back down")
	await walk(1, Vector2(3.0, -0.8), 0.15)
	Input.action_press("p1_grab")
	await frames(30)
	check(bean(1).riding, "P1 hangs on to the near end of the crease")

	# 5. P2 brings it up from the top plate; P1 hops off too.
	await walk(2, Vector2(8, 4), 0.4)
	check(room.high_plate.is_pressed and room.lift_up(), "P2 on the top plate: the lift goes up again")
	check(await lift_at(room.TOP_Y), "it reaches the top")
	await hop(1, Vector2(1, 0))
	check(not bean(1).riding and absf(bean(1).global_position.y - room.LEDGE_Y) < 0.3, "P1 hops off onto the ledge")
	await walk(1, Vector2(11, -4), 0.5)
	await walk(2, Vector2(13, -3), 0.5)
	await frames(10)
	check(lvl.complete, "both beans reach the flag: Paper Elevator complete")
	release_all()
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 20000:
		check(false, "timed out")
		quit(1)
	return false
