extends SceneTree
# Bots solve the Basket Run and Counterweight Lift rooms with real input
# actions: fold a trough on the printed lines, pick up apples and drop them in,
# carry the trough together (keeping it level down a ramp), set it on the
# scale / on the seesaw, and walk to the flag. Along the way it checks the
# rooms' rules: a part-loaded scale tips the apples back, a loose apple rolls
# off the seesaw, and the seesaw tips under a bean with nothing on its near end.
# Between steps a bean may be placed at its starting spot, as a player would
# walk there.
# Run:   godot --headless -s tests/solve_carry_rooms.gd      (exit code 0 = pass)
# Shots: godot -s tests/solve_carry_rooms.gd -- --shots=/some/dir   (needs a display)

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


## Folds a wall up: grab the sheet edge at `edge` (standing at `at`), raise
## the hands to the wall's height and bring them over the printed crease.
func fold_wall(pid: int, at: Vector3, edge: Vector3, crease: Vector2, height: float) -> bool:
	if not await grab_sheet(pid, at, edge):
		return false
	await lift_to(pid, height)
	await move_hands(pid, crease, 0.06)
	await let_go(pid)
	return true


## Picks prop `p` up: bean `pid` starts beside it, on the side away from the
## other props (so it's the one in reach).
func pick(pid: int, p: Prop) -> bool:
	var b = bean(pid)
	var at := flat(p.global_position)
	var ground := p.global_position.y - p.size
	# Stand 1 m from it, on solid ground and as far from other props as can be.
	var spot := at + Vector2(1, 0)
	var best := -INF
	for k in 8:
		var c := at + Vector2.from_angle(k * PI / 4.0)
		var from := Vector3(c.x, ground + 1.0, c.y)
		var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5))
		if hit.is_empty() or hit.collider is Prop or hit.collider is PaperSheet:
			continue
		var score := 0.0
		for q in lvl.room.props:
			if q != p:
				score -= 1.0 / maxf(flat(q.global_position).distance_to(c), 0.3)
		if score > best:
			best = score
			spot = c
	b.place(Vector3(spot.x, p.global_position.y - p.size + 0.1, spot.y))
	await frames(25)
	if b.hover == null or not b.hover.has("prop") or b.hover.prop != p:
		print("      hover: %s" % [b.hover])
		return false
	Input.action_press("p%d_grab" % pid)
	await frames(3)
	return b.held_prop == p


## Walks bean `pid` through `points` in turn.
func route(pid: int, points: Array) -> void:
	for q in points:
		await walk(pid, q, 0.3)


## Carries the held prop in via `approach`, stands at `stand` (so it's held
## over the spot in front) and lets go.
func drop_via(pid: int, approach: Vector2, stand: Vector2, lift := 0.0) -> void:
	await walk(pid, approach, 0.3)
	await lift_to(pid, lift)
	await walk(pid, stand, 0.12)
	await frames(30)
	await let_go(pid)
	await frames(30)


## Keeps the carried sheet level: bean `adjust` raises or lowers its hands to
## match bean `ref`'s.
func level(adjust: int, ref: int) -> void:
	var dh: float = bean(ref).carry_hands().y - bean(adjust).carry_hands().y
	Input.action_release("p%d_jump" % adjust)
	Input.action_release("p%d_lower" % adjust)
	if dh > 0.015:
		Input.action_press("p%d_jump" % adjust, clampf(dh * 12.0, 0.15, 1.0))
	elif dh < -0.015:
		Input.action_press("p%d_lower" % adjust, clampf(-dh * 12.0, 0.15, 1.0))


## Two beans carrying a sheet: `lead` walks to `goal` and `trail` copies its
## movement (so the sheet keeps facing the same way), while `lead` keeps it
## level.
func carry_to(lead: int, trail: int, goal: Vector2, tol := 0.25, max_frames := 2500) -> bool:
	var lead0 := flat(bean(lead).global_position)
	var trail0 := flat(bean(trail).global_position)
	for i in max_frames:
		if not bean(lead).carrying:
			print("      the carry broke off")
			break
		var lp := flat(bean(lead).global_position)
		var tp := flat(bean(trail).global_position)
		var d := goal - lp
		if d.length() < tol:
			break
		stick(lead, d.normalized() * clampf(d.length() * 1.2, 0.3, 1.0))
		stick(trail, (trail0 + (lp - lead0) - tp) * 2.0)
		level(lead, trail)
		await physics_frame
	stick(lead, Vector2.ZERO)
	stick(trail, Vector2.ZERO)
	Input.action_release("p%d_jump" % lead)
	Input.action_release("p%d_lower" % lead)
	await frames(10)
	return bean(lead).carrying


func release_all() -> void:
	for pid in [1, 2]:
		for a in ["left", "right", "up", "down", "jump", "lower", "grab", "sheet"]:
			Input.action_release("p%d_%s" % [pid, a])


func in_box(p: Vector3, lo: Vector3, hi: Vector3) -> bool:
	return p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z


func run() -> void:
	await frames(30)
	await basket_run()
	release_all()
	await counterweight()
	release_all()
	quit(0 if ok else 1)


func basket_run() -> void:
	lvl.load_room(3)
	await frames(40)
	var room = lvl.room
	check(room.title == "Basket Run", "the Basket Run room loads")
	var y: float = room.UPPER_Y
	var apples: Array = room.props

	# A part-loaded scale tips its load back up the hill: carry one apple down
	# (the long way, by hand) and leave it there.
	check(await pick(1, apples[0]), "P1 picks up an apple")
	await walk(1, Vector2(-1.0, -5.0))
	await walk(1, Vector2(15.0, -5.0)) # down the ramp
	await drop_via(1, Vector2(23.0, -3.0), Vector2(23.0, 0.5))
	check(room.scale_plate.load_kg > 14.0, "one apple on the scale weighs %d kg" % roundi(room.scale_plate.load_kg))
	room.scale_plate.waiting = room.scale_plate.reset_after - 1.0 # (skip the wait)
	await frames(150)
	check(room.scale_plate.load_kg < 1.0 and apples[0].global_position.y > y, "left part-loaded, the scale tips the apple back up the hill")

	# 1. Fold the sheet's sides up along the printed lines: a trough along X.
	check(await fold_wall(1, Vector3(-7, y + 0.1, -4.1), Vector3(-7, y, -3.5), Vector2(-7, -2.0), 1.5), "P1 folds up the first side")
	check(await fold_wall(1, Vector3(-7, y + 0.1, 4.1), Vector3(-7, y, 3.5), Vector2(-7, 2.0), 1.5), "P1 folds up the second side")
	var upright := 0
	for f in room.sheet.facets:
		if absf((room.sheet.global_basis * f.normal()).y) < 0.05:
			upright += 1
	check(upright == 2, "the sheet is a trough: two upright sides (%d)" % upright)

	# 2. Roll the apples in, from the far end to the near end.
	var spots := [-9.5, -8.6, -7.7, -6.8, -5.9, -5.0]
	var loaded := 0
	for i in apples.size():
		if not await pick(1, apples[i]):
			continue
		# Round the trough (not through its walls) to its open front end.
		var side := 5.5 if bean(1).global_position.z >= 0.0 else -5.5
		await route(1, [Vector2(bean(1).global_position.x, side), Vector2(-1.5, side), Vector2(-1.5, 0.0)])
		await drop_via(1, Vector2(-2.6, 0.0), Vector2(spots[i] + 1.25, 0.0))
		await walk(1, Vector2(-1.5, 0.0))
		if in_box(apples[i].global_position, Vector3(-10.5, y, -2), Vector3(-3.5, y + 1.0, 2)):
			loaded += 1
		else:
			print("      apple %d ended up at %s" % [i, apples[i].global_position])
	check(loaded == 6, "all six apples are in the trough (%d)" % loaded)

	# 3. Pick it up together, one bean at each open end.
	#    (Off-centre, clear of any apples that rolled to the ends.)
	check(await grab_sheet(1, Vector3(-11.4, y + 0.1, 0.5), Vector3(-10.5, y, 0.5)), "P1 takes the back end")
	check(await grab_sheet(2, Vector3(-2.6, y + 0.1, 0.5), Vector3(-3.5, y, 0.5)), "P2 takes the front end")
	check(bean(1).carrying and bean(2).carrying and room.sheet.carriers.size() == 2, "they're carrying it together")
	Input.action_press("p1_jump")
	Input.action_press("p2_jump")
	await frames(40)
	Input.action_release("p1_jump")
	Input.action_release("p2_jump")
	await frames(30)
	check(room.sheet.global_position.y > y + 0.5, "the trough comes up off the ground (%.2f m)" % (room.sheet.global_position.y - y))

	# 4. Over to the top of the ramp, down it (the front bean raising its end to
	#    keep it level), across to the scale.
	await carry_to(2, 1, Vector2(-1.0, -5.0))
	await carry_to(2, 1, Vector2(24.0, -5.0)) # (the back bean clear of the ramp)
	await carry_to(2, 1, Vector2(27.1, 2.0))
	var still := 0
	for a in apples:
		if in_box(a.global_position, room.sheet.global_position + Vector3(-6, -1, -4), room.sheet.global_position + Vector3(6, 3, 4)):
			still += 1
	check(still == 6, "carried level, all six apples are still in the trough (%d)" % still)
	await snap("basket_carry")
	# 5. Set it down on the scale and let go.
	Input.action_press("p1_lower")
	Input.action_press("p2_lower")
	await frames(90)
	Input.action_release("p1_lower")
	Input.action_release("p2_lower")
	await let_go(2)
	await frames(60)
	check(not room.sheet.carriers.size(), "they let go and the trough settles")
	check(room.scale_plate.is_pressed, "all six apples on the scale at once: %d kg" % roundi(room.scale_plate.load_kg))
	await snap("basket_scale")
	await route(1, [Vector2(17.5, -3.0), Vector2(26.0, -5.0)]) # (round the trough)
	await walk(2, Vector2(28.0, -5.0), 0.5)
	await frames(10)
	check(lvl.complete, "both beans reach the flag: Basket Run complete")


func counterweight() -> void:
	lvl.load_room(4)
	await frames(60)
	var room = lvl.room
	check(room.title == "Counterweight Lift", "the Counterweight Lift room loads")
	var plank: RigidBody3D = room.plank
	var start_angle := rad_to_deg(plank.rotation.z)
	check(start_angle > 14.0, "the plank rests with its near end down (%.1f deg)" % start_angle)

	# With nothing on its near end, the plank tips under a bean past the middle.
	bean(1).place(Vector3(-9, 0.1, 0))
	await frames(10)
	await walk(1, Vector2(6, 0), 0.4, 600)
	await frames(200)
	check(rad_to_deg(plank.rotation.z) < -10.0, "alone, it tips once P1 is past the middle (%.1f deg)" % rad_to_deg(plank.rotation.z))
	await walk(1, Vector2(-10, 0), 0.4, 900)
	await frames(120)
	check(rad_to_deg(plank.rotation.z) > 14.0, "with P1 off it, it settles back onto its near end (%.1f deg)" % rad_to_deg(plank.rotation.z))

	# ...and there's no outrunning it.
	bean(1).place(Vector3(-9, 0.1, 0))
	await frames(10)
	await walk(1, Vector2(10, 0), 0.4, 600)
	await frames(60)
	check(bean(1).global_position.y < room.LEDGE_Y - 1.0, "running up it alone doesn't get you onto the ledge")
	bean(1).place(Vector3(-10, 0.1, 0))
	await frames(200)

	# A loose apple just rolls off the slope.
	var apples: Array = []
	for p in room.props:
		if p.kind == Prop.BALL:
			apples.append(p)
	var loose: Prop = apples[7] # (the one on the corner nearest the plank)
	check(await pick(1, loose), "P1 picks up an apple")
	await drop_via(1, Vector2(-9, 0), Vector2(-4, 0))
	await walk(1, Vector2(-9, 3), 0.4) # out of its way
	await frames(180)
	check(loose.global_position.x < -7.0, "dropped on the plank, it rolls back down off it (x=%.1f)" % loose.global_position.x)
	await frames(120)
	if await pick(1, loose): # (back with the others, out of the way)
		await walk(1, Vector2(-19.0, -1.5))
		await let_go(1)

	# 1. A trough, as in the Basket Run (walls across the plank's slope).
	check(await fold_wall(1, Vector3(-17.6, 0.1, 4.5), Vector3(-17, 0, 4.5), Vector2(-15.5, 4.5), 1.5), "P1 folds up the first side")
	check(await fold_wall(1, Vector3(-10.4, 0.1, 4.5), Vector3(-11, 0, 4.5), Vector2(-12.5, 4.5), 1.5), "P1 folds up the second side")
	# 2. Load all eight apples through the open end at +Z.
	var spots := [Vector2(-14.5, 3.0), Vector2(-13.5, 3.0), Vector2(-14.5, 4.0), Vector2(-13.5, 4.0),
		Vector2(-14.5, 5.0), Vector2(-13.5, 5.0), Vector2(-14.5, 6.0), Vector2(-13.5, 6.0)]
	var loaded := 0
	for i in apples.size():
		if not await pick(1, apples[i]):
			continue
		# Out of the bunch (not through it), round the trough's side to its open end.
		var p0: Vector3 = bean(1).global_position
		var out := -2.5 if p0.z > -4.9 else -7.5
		await route(1, [Vector2(p0.x, out), Vector2(-16.5, out), Vector2(-16.5, 9.0), Vector2(spots[i].x, 9.0)])
		await drop_via(1, Vector2(spots[i].x, 8.0), spots[i] + Vector2(0, 1.25))
		await walk(1, Vector2(spots[i].x, 9.0))
		if in_box(apples[i].global_position, Vector3(-15.5, 0, 2), Vector3(-12.5, 0.8, 7)):
			loaded += 1
	check(loaded == 8, "all eight apples are in the trough (%d)" % loaded)
	# 3. Carry it onto the plank's near end, side by side up the slope.
	check(await grab_sheet(1, Vector3(-14, 0.1, 1.1), Vector3(-14, 0, 2)), "P1 takes one open end")
	check(await grab_sheet(2, Vector3(-14, 0.1, 7.9), Vector3(-14, 0, 7)), "P2 takes the other")
	Input.action_press("p1_jump")
	Input.action_press("p2_jump")
	await frames(40)
	Input.action_release("p1_jump")
	Input.action_release("p2_jump")
	await carry_to(1, 2, Vector2(-14, -3.4)) # line up across the plank
	Input.action_press("p1_jump") # high enough to clear the plank's end
	Input.action_press("p2_jump")
	await frames(30)
	Input.action_release("p1_jump")
	Input.action_release("p2_jump")
	await carry_to(1, 2, Vector2(-5.2, -3.4)) # walk it up onto the near end
	Input.action_press("p1_lower")
	Input.action_press("p2_lower")
	await frames(90)
	Input.action_release("p1_lower")
	Input.action_release("p2_lower")
	await let_go(1)
	await frames(90)
	var aboard := 0
	for a in apples:
		if a.global_position.x > -8.0 and a.global_position.x < -2.0 and absf(a.global_position.z) < 4.0:
			aboard += 1
	check(aboard >= 7, "the trough sits on the plank's near end with its apples (%d of 8)" % aboard)
	await snap("counterweight_loaded")
	# 4. Up to the ledge, one at a time, beside the trough.
	for pid in [1, 2]:
		var lane := -3.4 if pid == 1 else 3.4
		await walk(pid, Vector2(-3.0, lane), 0.4)
		await walk(pid, Vector2(10.0, lane), 0.4, 900)
		check(bean(pid).global_position.y > room.LEDGE_Y - 0.3, "P%d walks up the plank onto the ledge (plank at %.1f deg)" % [pid, rad_to_deg(plank.rotation.z)])
		await walk(pid, Vector2(14.0 + pid, lane * 0.3), 0.5)
	await frames(10)
	await snap("counterweight_done")
	check(lvl.complete, "both beans reach the flag: Counterweight Lift complete")


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 60000:
		check(false, "timed out")
		quit(1)
	return false
