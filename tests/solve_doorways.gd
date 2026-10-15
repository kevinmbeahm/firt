extends SceneTree
# Bots solve the two Doorway rooms with real input actions (walk, grab, raise
# hands, release, slide the sheet), checking the shape gate opens only when the
# paper really fills the outline, then walk both beans through the door to the
# flag. Between steps a bean may be placed at its starting spot, as a player
# would walk there.
# Run:   godot --headless -s tests/solve_doorways.gd      (exit code 0 = pass)
# Shots: godot -s tests/solve_doorways.gd -- --shots=/some/dir   (needs a display)

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


func release_all() -> void:
	for pid in [1, 2]:
		for a in ["left", "right", "up", "down", "jump", "lower", "grab", "sheet"]:
			Input.action_release("p%d_%s" % [pid, a])


## Holds the stick of player `pid` toward world direction `dir` (x, z). The
## rooms start with the camera looking down -Z, so stick x = world x and stick
## down = world +z.
func stick(pid: int, dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 1.0 else dir
	for pair in [["right", maxf(d.x, 0.0)], ["left", maxf(-d.x, 0.0)], ["down", maxf(d.y, 0.0)], ["up", maxf(-d.y, 0.0)]]:
		if pair[1] > 0.01:
			Input.action_press("p%d_%s" % [pid, pair[0]], pair[1])
		else:
			Input.action_release("p%d_%s" % [pid, pair[0]])


## Walks bean `pid` until `pos()` (a callable giving a world point that moves
## with it: the bean, or the paper in its hands) is within `tol` of `goal`
## (x, z). Slows down near the goal.
func walk(pid: int, pos: Callable, goal: Vector2, tol := 0.08, max_frames := 900) -> bool:
	for i in max_frames:
		var p: Vector3 = pos.call()
		var d := goal - Vector2(p.x, p.z)
		if d.length() < tol:
			stick(pid, Vector2.ZERO)
			await frames(10)
			return true
		stick(pid, d.normalized() * clampf(d.length() * 1.5, 0.25, 1.0))
		await physics_frame
	stick(pid, Vector2.ZERO)
	return false


func bean(pid: int):
	return lvl.players[pid - 1]


## Places bean `pid` at `at`, grabs the handle nearest `handle` and returns
## whether it got hold of it.
func grab(pid: int, at: Vector3, handle: Vector3) -> bool:
	var b = bean(pid)
	b.place(at)
	await frames(15)
	if b.hover == null or (b.hover.world as Vector3).distance_to(handle) > 0.6:
		print("      hover: %s" % [b.hover.world if b.hover != null else null])
		return false
	Input.action_press("p%d_grab" % pid)
	await frames(3)
	return b.grabbing


## Holds raise (or lower) until bean `pid`'s hands are `lift` m up.
func lift_to(pid: int, lift: float) -> void:
	var b = bean(pid)
	var action := "p%d_jump" % pid if lift > b._lift else "p%d_lower" % pid
	Input.action_press(action)
	for i in 400:
		if absf(b._lift - lift) < 0.05:
			break
		await physics_frame
	Input.action_release(action)


func let_go(pid: int) -> void:
	Input.action_release("p%d_grab" % pid)
	await frames(10)


## Bean `pid` (near the sheet) slides it until its origin reaches `goal` (x, z)
## or it stops moving (against the wall).
func slide(pid: int, goal: Vector2, tol := 0.05) -> void:
	var s: PaperSheet = lvl.sheet
	Input.action_press("p%d_sheet" % pid)
	var still := 0
	var last := s.global_position
	for i in 900:
		var d := goal - Vector2(s.global_position.x, s.global_position.z)
		if d.length() < tol:
			break
		stick(pid, d.normalized() * clampf(d.length() * 0.8, 0.12, 1.0))
		await physics_frame
		still = still + 1 if s.global_position.distance_to(last) < 0.002 else 0
		last = s.global_position
		if still > 30:
			break # blocked (by the wall)
	stick(pid, Vector2.ZERO)
	Input.action_release("p%d_sheet" % pid)
	await frames(40)


## Walks bean `pid` out toward the camera (+z) first, then across: around the
## sheet rather than into the paper standing up on it.
func around_to(pid: int, goal: Vector2) -> void:
	var p: Vector3 = bean(pid).global_position
	await walk(pid, body(pid), Vector2(p.x, goal.y), 0.4)
	await walk(pid, body(pid), goal, 0.4)


func gate():
	return lvl.room.gate


func hands(pid: int) -> Callable:
	return func() -> Vector3: return bean(pid)._hands_world()


func body(pid: int) -> Callable:
	return func() -> Vector3: return bean(pid).global_position


## Both beans walk through the door to the flag.
func finish_room() -> void:
	var door_x: float = lvl.room.DOOR_X
	var wall_z: float = lvl.room.WALL_Z
	for pid in [1, 2]:
		await walk(pid, body(pid), Vector2(door_x, wall_z + 2.0), 0.3)
		await walk(pid, body(pid), Vector2(door_x + (pid - 1.5), wall_z - 5.0), 0.4)
	await frames(10)


func run() -> void:
	await frames(30)

	# --- Doorway: Square ----------------------------------------------------
	lvl.load_room(1)
	await frames(30)
	var s: PaperSheet = lvl.sheet
	check(lvl.room.title == "Doorway: Square", "the square doorway room loads")
	# 1. Fold the sheet in half along the printed line: carry the left edge over
	#    to the right edge.
	check(await grab(1, Vector3(-3.2, 0.1, 0.5), Vector3(-2.5, 0, 0.5)), "P1 grabs the sheet's left edge")
	await walk(1, hands(1), Vector2(3.5, 0.5))
	await let_go(1)
	check(s.facets.size() == 2 and absf(s.world_box().size.x - 3.0) < 0.05, "folded in half along the printed line (%d facets, %.2f m wide)" % [s.facets.size(), s.world_box().size.x])
	# Standing up half of an unfolded sheet would spill: covered by the house
	# room's check below; here just make sure nothing's open yet.
	check(not gate().is_open, "the door is still shut")
	# 2. Stand the wall-side half up along the other printed line.
	check(await grab(1, Vector3(2.0, 0.1, -3.2), Vector3(2.0, 0, -2.5)), "P1 grabs the wall-side edge")
	await lift_to(1, 3.0)
	await walk(1, hands(1), Vector2(2.0, 0.5), 0.15)
	await let_go(1)
	var standing := 0
	for f in s.facets:
		if absf(f.normal().y) < 0.02:
			standing += 1
	check(standing == 2, "half the folded sheet stands straight up (%d upright facets)" % standing)
	# 3. P1 steps aside; P2 slides the sheet over to the outline and back
	#    against the wall.
	print("      step: P1 walks off")
	await walk(1, body(1), Vector2(7.0, 2.0), 0.4)
	print("      step: slide")
	bean(2).place(Vector3(5.5, 0.1, 2.0))
	await frames(10)
	await slide(2, Vector2(-4.5, s.global_position.z))
	await around_to(2, Vector2(-3.0, 6.0)) # behind the sheet, to push it to the wall
	await slide(2, Vector2(-4.5, -8.0))
	await frames(20)
	gate().measure()
	print("      gate: %d%% filled, %d%% spilling" % [roundi(gate().coverage * 100), roundi(gate().spill * 100)])
	check(gate().is_open, "the paper fills the square outline and the door opens")
	await frames(120)
	await snap("square_open")
	await finish_room()
	check(lvl.complete, "both beans reach the flag: square room complete")
	release_all()

	# --- Doorway: House -----------------------------------------------------
	lvl.load_room(2)
	await frames(30)
	s = lvl.sheet
	check(lvl.room.title == "Doorway: House", "the house doorway room loads")
	# Spill check: standing the unfolded end up gives a square that pokes out
	# past the roof lines: the gate must stay shut.
	check(await grab(1, Vector3(1.0, 0.1, -3.6), Vector3(1.0, 0, -3.0)), "P1 grabs the end of the sheet")
	await lift_to(1, 3.2)
	await walk(1, hands(1), Vector2(1.0, 1.0), 0.15)
	await let_go(1)
	await walk(1, body(1), Vector2(7.0, 2.0), 0.4)
	bean(2).place(Vector3(5.0, 0.1, 3.0))
	await frames(10)
	await slide(2, Vector2(-3.0, s.global_position.z))
	await around_to(2, Vector2(-3.0, 7.5))
	await slide(2, Vector2(-3.0, -8.0))
	await frames(20)
	gate().measure()
	check(not gate().is_open and gate().spill > 0.1, "a plain square of paper spills past the roof: the door stays shut (%d%% spilling)" % roundi(gate().spill * 100))
	lvl.load_room(2) # restart the room
	await frames(30)
	s = lvl.sheet
	# 1. and 2. Fold both top corners down along the printed roof lines.
	check(await grab(1, Vector3(-1.5, 0.1, -3.5), Vector3(-1.0, 0, -3.0)), "P1 grabs the left corner")
	await walk(1, hands(1), Vector2(0.44, -1.08), 0.06)
	await let_go(1)
	check(await grab(1, Vector3(3.5, 0.1, -3.5), Vector3(3.0, 0, -3.0)), "P1 grabs the right corner")
	await walk(1, hands(1), Vector2(1.56, -1.08), 0.06)
	await let_go(1)
	check(s.facets.size() == 3 and absf(s.world_box().size.x - 4.0) < 0.05, "both roof corners folded down (%d facets, %.2f m wide)" % [s.facets.size(), s.world_box().size.x])
	# 3. Stand the end up along the printed line, holding it by the peak.
	check(await grab(1, Vector3(1.0, 0.1, -3.6), Vector3(1.0, 0, -3.0)), "P1 grabs the roof's peak")
	await lift_to(1, 3.2)
	await walk(1, hands(1), Vector2(1.0, 1.0), 0.15)
	await let_go(1)
	var top := -INF
	for f in s.facets:
		for q in f.pts:
			top = maxf(top, s.to_global(f.at(q)).y)
	check(absf(top - 4.0) < 0.1, "the house stands up, its peak 4 m up (%.2f m)" % top)
	# 4. Slide it into place against the wall.
	await walk(1, body(1), Vector2(7.0, 2.0), 0.4)
	bean(2).place(Vector3(5.0, 0.1, 3.0))
	await frames(10)
	await slide(2, Vector2(-3.0, s.global_position.z))
	await around_to(2, Vector2(-3.0, 7.5))
	await slide(2, Vector2(-3.0, -8.0))
	await frames(20)
	gate().measure()
	print("      gate: %d%% filled, %d%% spilling" % [roundi(gate().coverage * 100), roundi(gate().spill * 100)])
	check(gate().is_open, "the folded house fills the outline and the door opens")
	await frames(120)
	await snap("house_open")
	await finish_room()
	check(lvl.complete and lvl.all_complete, "both beans reach the flag: house room complete (last room)")
	release_all()
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 30000:
		check(false, "timed out")
		quit(1)
	return false
