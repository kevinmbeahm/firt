extends SceneTree
# Bots solve the Ferry (portage) with real input actions: fold a tray, load
# the crate, paddle the first channel to the island, carry the loaded boat
# over the fence together (walking through the gap one behind the other),
# set it down on the far beach, paddle the second channel, unload the crate
# onto the plate and walk to the flag. Between steps a bean may be placed at
# a spot on land, as a player would walk there.
# Run:   godot --headless --fixed-fps 120 -s tests/solve_ferry.gd   (exit code 0 = pass)
# Shots: godot --fixed-fps 120 -s tests/solve_ferry.gd -- --shots=/some/dir   (needs a display)

const ROOM := 8

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
	if b.held_prop != p:
		print("      couldn't pick it up: hover %s, holding %s, grabbing %s" % [b.hover, b.held_prop, b.grabbing])
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


## Bean `pid` walks toward `goal` and jumps once it's within `at` of it (over
## a wall), then carries on to it.
func jump_to(pid: int, goal: Vector2, at: float) -> void:
	for i in 900:
		var d := goal - flat(bean(pid).global_position)
		if d.length() < 0.3:
			break
		stick(pid, d.normalized())
		if d.length() < at and bean(pid).standing():
			Input.action_press("p%d_jump" % pid)
			await frames(2)
			Input.action_release("p%d_jump" % pid)
			at = -1.0
		await physics_frame
	stick(pid, Vector2.ZERO)
	await frames(30)


## The corner of the boat's floor furthest across the river (+X), world.
func floor_corner(s: PaperSheet) -> Vector3:
	var best := Vector3(-INF, 0, 0)
	var floor_f: PaperModel.Facet = null
	for f in s.facets:
		if absf(f.normal().y) > 0.9 and (floor_f == null or absf(PaperGeometry.signed_area(f.pts)) > absf(PaperGeometry.signed_area(floor_f.pts))):
			floor_f = f
	for q in floor_f.pts:
		var p := s.to_global(floor_f.at(q))
		if p.x > best.x:
			best = p
	return best


## Walks bean `pid` up to prop `p` (it may be pushed along on the way) until
## it's within `reach` of it.
func approach(pid: int, p: Prop, reach: float) -> void:
	for i in 900:
		var d := flat(p.global_position) - flat(bean(pid).global_position)
		if d.length() < reach + p.size:
			break
		stick(pid, d.normalized() * 0.5)
		await physics_frame
	stick(pid, Vector2.ZERO)
	await frames(15)


func in_boat(pid: int) -> bool:
	var s: PaperSheet = lvl.sheet
	var q: Vector3 = s.to_local(bean(pid).global_position)
	return absf(q.x) < 3.0 and absf(q.z) < 3.0 and q.y > -0.3 and q.y < 1.0


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


## The boat's four sides (not the gusset ears): their rims' middles and which
## way they face, outward and level, world: [{mid, out}, ...].
func rims(s: PaperSheet) -> Array:
	var out := []
	var c := s.to_global(s.center_of_mass)
	for f in s.facets:
		if absf(f.normal().y) > 0.1 or absf(PaperGeometry.signed_area(f.pts)) < 3.0:
			continue
		var pts := []
		for q in f.pts:
			pts.append(s.to_global(f.at(q)))
		pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
		var mid: Vector3 = (pts[0] + pts[1]) * 0.5
		var o := mid - c
		o.y = 0.0
		out.append({"mid": mid, "out": o.normalized()})
	return out


## Paddles (bean `pid` holding sheet handling, pushing +X) until the boat's
## bow reaches `shore_x` (or it stops). Returns whether it was afloat on the way.
func paddle(pid: int, s: PaperSheet, min_x: float, shore_x: float) -> bool:
	Input.action_press("p%d_sheet" % pid)
	stick(pid, Vector2(1, 0))
	var afloat := false
	var still := 0
	for i in 4800:
		await physics_frame
		if s.water != null:
			afloat = true
		still = still + 1 if afloat and s.global_position.x > min_x and absf(s.linear_velocity.x) < 0.05 else 0
		if still > 60 or (afloat and floor_corner(s).x > shore_x):
			break
	stick(pid, Vector2.ZERO)
	Input.action_release("p%d_sheet" % pid)
	await frames(60)
	return afloat


## Both beans climb out over the side nearest +X, and step clear of the boat.
func climb_out(s: PaperSheet) -> void:
	for pid in [1, 2]:
		var corner := floor_corner(s)
		var inward := (flat(s.global_position) - flat(corner)).normalized()
		await walk(pid, flat(corner) + inward * 2.2, 0.3)
		await jump_to(pid, flat(corner) - inward * 2.5, 3.4)
		var away := signf(bean(pid).global_position.z - s.global_position.z)
		await walk(pid, Vector2(bean(pid).global_position.x + 0.8, bean(pid).global_position.z + away * 2.5), 0.4)


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	var room = lvl.room
	var s: PaperSheet = lvl.sheet
	var y: float = room.BANK_Y
	check(room.title == "Ferry Across the Flood", "the Ferry room loads")
	var c := Vector2(-15, -6) # the sheet's middle

	# 1. A tray, the crate in it, both aboard.
	for w in [[Vector3(c.x, y + 0.1, c.y - 4.9), Vector3(c.x, y, c.y - 4), Vector2(c.x, c.y - 3)],
			[Vector3(c.x, y + 0.1, c.y + 4.9), Vector3(c.x, y, c.y + 4), Vector2(c.x, c.y + 3)],
			[Vector3(c.x + 4.9, y + 0.1, c.y), Vector3(c.x + 4, y, c.y), Vector2(c.x + 3, c.y)],
			[Vector3(c.x - 4.9, y + 0.1, c.y), Vector3(c.x - 4, y, c.y), Vector2(c.x - 3, c.y)]]:
		if not await grab_sheet(1, w[0], w[1]):
			break
		await lift_to(1, 1.0)
		await move_hands(1, w[2], 0.06)
		await let_go(1)
	check(s.facets.size() == 13, "P1 folds a tray (%d facets)" % s.facets.size())
	check(await pick(2, room.crate), "P2 picks up the crate")
	await walk(2, Vector2(c.x, c.y + 6.0))
	await lift_to(2, 1.0)
	await walk(2, Vector2(c.x, c.y + 3.45), 0.3)
	await frames(30)
	await let_go(2)
	await frames(60)
	bean(1).place(Vector3(c.x, y + 0.1, c.y + 5.5))
	await frames(10)
	await jump_to(1, Vector2(c.x + 1, c.y + 1), 3.0)
	await jump_to(2, Vector2(c.x - 1, c.y + 1), 3.0)
	check(in_boat(1) and in_boat(2), "crate loaded, both aboard")

	# 2. The first channel, to the island.
	check(await paddle(1, s, -3.0, 8.8), "afloat on the first channel")
	check(floor_corner(s).x > 6.0, "it floats over the island's shelf and runs aground at its beach (nearest corner at x=%.1f)" % floor_corner(s).x)
	await climb_out(s)
	check(bean(1).global_position.x > 7.0 and bean(2).global_position.x > 7.0, "both climb out onto the island (%s, %s; boat %s, crate %s)" % [bean(1).global_position, bean(2).global_position, s.global_position, room.crate.global_position])
	# 3. Carry it over the fence: P2 at the front, P1 at the back, in line
	#    with the gap.
	var r := rims(s)
	r.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.mid.x > b.mid.x)
	var front: Dictionary = r[0]
	var back: Dictionary = r[r.size() - 1]
	var fy: float = front.mid.y - 1.0
	var by: float = back.mid.y - 1.0
	check(await grab_sheet(2, Vector3(front.mid.x, fy, front.mid.z) + front.out * 0.9, front.mid), "P2 takes the front rim")
	check(await grab_sheet(1, Vector3(back.mid.x, by, back.mid.z) + back.out * 0.9, back.mid), "P1 takes the back rim")
	check(s.carriers.size() == 2, "they're carrying the boat (with the crate in it)")
	Input.action_press("p1_jump")
	Input.action_press("p2_jump")
	await frames(150) # (high enough for the boat's floor to clear the fence)
	Input.action_release("p1_jump")
	Input.action_release("p2_jump")
	await frames(60)
	# In line with the gap: P2 steps across to it, then P1 lines up behind.
	await carry_to(2, 1, Vector2(bean(2).global_position.x, 0.0), 0.1)
	await walk(1, Vector2(bean(1).global_position.x, 0.0), 0.1)
	await carry_to(2, 1, Vector2(room.FENCE_X + 1.0, 0.0), 0.2)
	await carry_to(2, 1, Vector2(24.5, 0.0), 0.3)
	check(s.carriers.size() == 2 and s.global_position.x > room.FENCE_X + 1.0, "over the fence, through the gap one behind the other (boat at x=%.1f)" % s.global_position.x)
	check(s.to_local(room.crate.global_position).y < 1.0 and absf(s.to_local(room.crate.global_position).x) < 3.0, "the crate's still in it (%s)" % s.to_local(room.crate.global_position))
	await snap("ferry_portage")
	Input.action_press("p1_lower")
	Input.action_press("p2_lower")
	await frames(120)
	Input.action_release("p1_lower")
	Input.action_release("p2_lower")
	await let_go(2)
	await frames(90)
	check(s.carriers.is_empty(), "they set it down on the far side of the island")

	# 4. Aboard again, the second channel, the far beach.
	var bc := flat(s.global_position)
	bean(1).place(Vector3(bc.x - 5.0, y + 0.1, bc.y - 0.5))
	bean(2).place(Vector3(bc.x - 5.0, y + 0.1, bc.y + 0.5))
	await frames(10)
	await jump_to(1, bc + Vector2(-1, -0.5), 3.0)
	await jump_to(2, bc + Vector2(-1, 0.5), 3.0)
	check(in_boat(1) and in_boat(2), "both jump back in")
	check(await paddle(1, s, 24.0, 34.0), "afloat on the second channel")
	check(floor_corner(s).x > 33.0, "aground on the far beach (its nearest corner at x=%.1f)" % floor_corner(s).x)

	# 5. Crate out, beans out, crate to the plate.
	await approach(2, room.crate, 1.0)
	Input.action_press("p2_grab")
	await frames(5)
	check(bean(2).held_prop == room.crate, "P2 picks the crate up in the boat")
	await lift_to(2, 1.0)
	var corner := floor_corner(s)
	var inward := (flat(s.global_position) - flat(corner)).normalized()
	await walk(2, flat(corner) + inward * 1.0, 0.2)
	stick(2, Vector2(1, 0))
	await frames(10)
	stick(2, Vector2.ZERO)
	await frames(30)
	await let_go(2)
	await frames(60)
	check(room.crate.global_position.x > 33.5 and room.crate.global_position.y > -0.5, "and puts it on the far beach (x=%.1f)" % room.crate.global_position.x)
	await climb_out(s)
	for pid in [1, 2]:
		await walk(pid, Vector2(room.FAR_X + 1.0, bean(pid).global_position.z), 0.4)
	check(bean(1).global_position.x > room.FAR_X and bean(2).global_position.x > room.FAR_X, "both climb out and up onto the far bank")
	await walk(1, Vector2(room.FAR_X + 8, 5), 0.5)
	check(await pick(2, room.crate), "P2 picks the crate up again")
	await drop_via(2, Vector2(room.FAR_X + 1.5, 0), Vector2(room.FAR_X + 2.6, 0))
	check(room.plate.is_pressed, "the crate's on the plate (%d kg)" % roundi(room.plate.load_kg))
	await walk(2, Vector2(room.FAR_X + 10, 7), 0.5)
	await frames(10)
	check(lvl.complete, "both beans reach the flag: Ferry complete")
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 60000:
		check(false, "timed out")
		quit(1)
	return false
