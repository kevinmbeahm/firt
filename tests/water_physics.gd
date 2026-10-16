extends SceneTree
# Water (S5) in the Paper Boat room: a flat sheet floats as a raft that holds
# both beans but not the crate as well; a tray (folded with the model) floats
# all three with room to spare and drifts with the current; the crate floats,
# the weight block sinks; beans can't swim; things that go over the falls come
# back where they started.
# Run:   godot --headless --fixed-fps 120 -s tests/water_physics.gd   (exit code 0 = pass)

const ROOM := 8
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


func bean(pid: int):
	return lvl.players[pid - 1]


## Puts sheet `s` down at `pos` (its origin), still.
func put(s: PaperSheet, pos: Vector3) -> void:
	s.global_transform = Transform3D(Basis(), pos)
	s.linear_velocity = Vector3.ZERO
	s.angular_velocity = Vector3.ZERO
	s.sleeping = false


func lowest(s: PaperSheet) -> float:
	return s.global_position.y + s.world_box().position.y


func fold(fs: Array, g: Vector3, t: Vector3) -> Array:
	var gi := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		var q: Vector3 = f.xf.affine_inverse() * g
		if absf(q.z) < 0.01 and (Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), f.pts) or _on_edge(Vector2(q.x, q.y), f.pts)):
			if gi < 0 or f.layer > fs[gi].layer:
				gi = i
	var r := PaperModel.plan_fold(fs, gi, g, t, Vector3.UP)
	return r.facets if r.ok else []


func _on_edge(q: Vector2, pts: PackedVector2Array) -> bool:
	for k in pts.size():
		if Geometry2D.get_closest_point_to_segment(q, pts[k], pts[(k + 1) % pts.size()]).distance_to(q) < 0.01:
			return true
	return false


func run() -> void:
	await frames(30)
	lvl.load_room(ROOM)
	await frames(40)
	var room = lvl.room
	var s: PaperSheet = lvl.sheet
	check(room.title == "Paper Boat", "the Paper Boat room loads")
	var mid := Vector3(2, 0.3, -10)
	room.river.current = Vector3.ZERO # (still water while we weigh things)

	# A flat sheet: a raft.
	put(s, mid)
	await frames(360)
	check(s.water != null and absf(lowest(s)) < 0.15, "a flat sheet floats (bottom at %.2f m)" % lowest(s))
	check(s.dry_volume < 0.05, "as a raft: it keeps no water out (%.2f m3)" % s.dry_volume)
	for pid in [1, 2]:
		bean(pid).place(s.global_position + Vector3(pid * 2 - 3, 0.3, 0))
	await frames(360)
	check(bean(1).global_position.y > -0.35 and bean(2).global_position.y > -0.35, "it holds both beans up (feet at %.2f, %.2f m)" % [bean(1).global_position.y, bean(2).global_position.y])
	var crate: Prop = room.crate
	crate.global_position = s.global_position + Vector3(0, 0.8, 1.5)
	crate.linear_velocity = Vector3.ZERO
	crate.sleeping = false
	var spawn1: Vector3 = bean(1).spawn
	var drowned := false
	for i in 600:
		await physics_frame
		if bean(1).global_position.distance_to(spawn1) < 1.0:
			drowned = true
			break
	check(drowned, "with the crate as well it goes under, and the beans are back on the bank (they can't swim)")

	# A tray: sides up, then ends (gussets).
	var fs: Array = PaperModel.make_sheet(Vector2(8, 8))
	for step in [[Vector3(0, T, -4), Vector3(0, 1.0, -3)], [Vector3(0, T, 4), Vector3(0, 1.0, 3)],
			[Vector3(4, T, 0), Vector3(3, 1.0, 0)], [Vector3(-4, T, 0), Vector3(-3, 1.0, 0)]]:
		fs = fold(fs, step[0], step[1])
		if fs.is_empty():
			break
	check(fs.size() == 13, "a tray folded from the sheet (%d facets)" % fs.size())
	if fs.is_empty():
		quit(1)
		return
	await frames(200) # (let the raft finish sinking and come back)
	s.facets = fs
	s._refresh()
	put(s, mid)
	await frames(360)
	check(s.water != null and lowest(s) > -0.3, "the tray floats (bottom at %.2f m; %.2f m3 of dry hull)" % [lowest(s), s.dry_volume])
	for pid in [1, 2]:
		bean(pid).place(s.global_position + Vector3(pid * 2 - 3, 0.3, -1))
	crate.global_position = s.global_position + Vector3(0, 0.8, 1.5)
	crate.linear_velocity = Vector3.ZERO
	crate.sleeping = false
	await frames(480)
	var top := s.global_position.y + s.world_box().end.y
	check(top > 0.5 and s.dry_volume > 0.2, "with both beans and the crate in it, it rides high on its hull (rim %.2f m above the water, %.2f m3 dry)" % [top, s.dry_volume])
	check(bean(1).global_position.y > -0.3 and bean(2).global_position.y > -0.3, "no one's wet (feet at %.2f, %.2f m)" % [bean(1).global_position.y, bean(2).global_position.y])
	room.river.current = room.CURRENT
	var z0 := s.global_position.z
	await frames(240)
	check(s.global_position.z - z0 > 0.4, "the current carries it downstream (%.1f m in 2 s)" % (s.global_position.z - z0))
	# Paddling: bean 1 holds sheet handling and pushes across the river.
	var x0 := s.global_position.x
	Input.action_press("p1_sheet")
	Input.action_press("p1_up") # (stick up = +X here)
	await frames(240)
	Input.action_release("p1_up")
	Input.action_release("p1_sheet")
	check(s.global_position.x - x0 > 1.5, "paddling moves it across (%.1f m in 2 s)" % (s.global_position.x - x0))

	# Props on their own: the crate floats, the weight block sinks.
	for pid in [1, 2]:
		bean(pid).place(Vector3(-20, room.BANK_Y + 0.1, pid * 3))
	var block := lvl.room.add_weight_block(Vector3(4, 1.0, 8)) as Prop
	crate.global_position = Vector3(0, 1.0, 8)
	crate.linear_velocity = Vector3.ZERO
	room.river.current = Vector3.ZERO
	await frames(360)
	check(absf(crate.global_position.y) < 0.45, "a crate floats (centre at %.2f m)" % crate.global_position.y)
	check(block.global_position.y < -3.0, "the weight block sinks (%.2f m)" % block.global_position.y)

	# Over the falls: back where it started.
	room.river.current = Vector3(0, 0, 3.0)
	put(s, Vector3(2, -0.1, -4)) # (in the water: a sheet put down still in mid-air would doze off)
	var came_back := false
	for i in 2400:
		await physics_frame
		if s.global_position.distance_to(s.spawn_transform.origin) < 0.5:
			came_back = true
			break
	check(came_back, "the tray goes over the falls and comes back on its bank")
	quit(0 if ok else 1)


func _process(_d: float) -> bool:
	if Engine.get_physics_frames() > 20000:
		check(false, "timed out")
		quit(1)
	return false
