class_name Level
extends Node3D
## The game: a series of puzzle rooms (scripts/rooms/), loaded one at a time.
## The level hosts what's shared between rooms: the two players, the shared
## camera, the HUD, input and undo. Each Room builds its own terrain, sheets and
## goal. Solving a room moves both players on to the next.
## Backspace restarts the current room; Page Up / Page Down skip between rooms.
## Run with `-- --room=N` to start in room N (1-based).

const ROOMS := [
	preload("res://scripts/rooms/ramp.gd"),
	preload("res://scripts/rooms/doorway_square.gd"),
	preload("res://scripts/rooms/doorway_house.gd"),
]
const ADVANCE_DELAY := 3.0 ## seconds between solving a room and loading the next

var sheet_speed := 3.0
var room: Room
var room_index := 0
var sheet: PaperSheet ## the current room's main sheet
var sheets: Array = [] ## the current room's sheets
var players: Array = []
var complete := false
var all_complete := false
var solo := false ## P1 has swapped beans at least once (solo play)

var cam_yaw := -PI * 0.5
var cam_pitch := -0.62
var _camera: Camera3D
var _cam_focus := Vector3(-6, 1, 0)
var _cam_dist := 16.0
var _hud: Label
var _room_hud: Label ## room title, hint and progress, at the bottom of the screen
var _undo_order: Array = [] ## sheets in the order they were folded
var _advance_in := -1.0


func _ready() -> void:
	_setup_input()
	_build_environment()

	var colors := [Color(0.95, 0.4, 0.35), Color(0.35, 0.62, 0.95)]
	for i in 2:
		var p := Player.new()
		p.id = i + 1
		p.color = colors[i]
		p.level = self
		add_child(p)
		players.append(p)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
	_room_hud = Label.new()
	_room_hud.add_theme_font_size_override("font_size", 18)
	_room_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_room_hud.add_theme_constant_override("outline_size", 6)
	_room_hud.anchor_top = 1.0
	_room_hud.anchor_bottom = 1.0
	_room_hud.offset_left = 16
	_room_hud.offset_top = -110
	_room_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_room_hud)

	var start := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room="):
			start = clampi(int(a.trim_prefix("--room=")) - 1, 0, ROOMS.size() - 1)
	load_room(start)


## Replaces the current room with room `index` (0-based) and puts both players
## at its start.
func load_room(index: int) -> void:
	for p in players:
		p.release()
	if room != null:
		remove_child(room)
		room.queue_free()
	_undo_order.clear()
	sheets = []
	sheet = null
	room_index = clampi(index, 0, ROOMS.size() - 1)
	room = ROOMS[room_index].new()
	room.level = self
	room.name = "Room"
	add_child(room)
	room.build()
	sheets = room.sheets
	sheet = room.sheet
	complete = false
	all_complete = false
	_advance_in = -1.0
	for i in players.size():
		players[i].place(room.spawns[i])
	cam_yaw = room.cam_yaw
	var mid: Vector3 = (room.spawns[0] + room.spawns[1]) * 0.5
	_cam_focus = mid + Vector3(0, 1, 0)
	_update_camera(1.0)


## Solo play: P1's controls move to the other bean. The bean left behind
## stands still but keeps holding whatever it holds (and keeps its weight).
## When P1 comes back to bean 1, bean 2 goes back to P2's controls.
func swap() -> void:
	solo = true
	if players[1].controlled_by == 1:
		players[1].set_controller(2)
		players[0].set_controller(1)
	else:
		players[0].set_controller(0)
		players[1].set_controller(1)


## The bean P1's controls drive right now.
func p1_bean() -> Player:
	return players[1] if players[1].controlled_by == 1 else players[0]


## Rooms call this for every sheet they add.
func register_sheet(s: PaperSheet) -> void:
	s.folded.connect(func() -> void: _undo_order.append(s))


# --- Scene construction ------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.65, 0.92)
	sky_mat.sky_horizon_color = Color(0.82, 0.9, 0.97)
	sky_mat.ground_bottom_color = Color(0.82, 0.88, 0.95)
	sky_mat.ground_horizon_color = Color(0.82, 0.9, 0.97)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.8)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.9, 0.97)
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	# A soft sea of clouds far below the gap.
	var clouds := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	clouds.mesh = pm
	clouds.material_override = _mat(Color(0.7, 0.78, 0.9))
	clouds.position.y = -30.0
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


# --- Gameplay hooks ----------------------------------------------------------

func camera_basis() -> Basis:
	return Basis(Vector3.UP, cam_yaw)


## Nearest grabbable corner/edge on any sheet: {sheet, world, local, facet} or null.
func find_handle(from_world: Vector3, radius: float):
	var best = null
	for s in sheets:
		var h = s.nearest_handle(from_world, radius)
		if h != null and (best == null or h.dist < best.dist):
			h.sheet = s
			best = h
	return best


## The sheet a player is standing on or right next to, for the slide/flip/turn
## controls.
func sheet_near(p: Node3D) -> PaperSheet:
	var best: PaperSheet = null
	var best_d := 3.0
	for s in sheets:
		var box: AABB = s.world_box()
		box.position += s.global_position
		var q := p.global_position
		var closest := Vector3(clampf(q.x, box.position.x, box.end.x),
			clampf(q.y, box.position.y - 2.0, box.end.y + 0.5), clampf(q.z, box.position.z, box.end.z))
		var d := closest.distance_to(q)
		if d < best_d:
			best = s
			best_d = d
	return best


func undo() -> void:
	while not _undo_order.is_empty():
		var s: PaperSheet = _undo_order.back()
		if not s.can_undo():
			_undo_order.pop_back() # nothing left there (e.g. the sheet was reset)
			continue
		if s.undo():
			_undo_order.pop_back()
		return # refused (busy, or no room to unfold): keep it for later


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("undo"):
		undo()
	if Input.is_action_just_pressed("reset"):
		load_room(room_index)
		return
	if Input.is_action_just_pressed("room_next") and room_index + 1 < ROOMS.size():
		load_room(room_index + 1)
		return
	if Input.is_action_just_pressed("room_prev") and room_index > 0:
		load_room(room_index - 1)
		return

	if Input.is_action_just_pressed("p1_swap"):
		swap()

	for cp in room.checkpoints:
		for p in players:
			if p.global_position.distance_to(cp.pos) < cp.radius:
				for i in players.size():
					players[i].spawn = cp.spawns[i]

	complete = room.is_complete(players)
	room.update_room(delta, complete)
	if complete and _advance_in < 0.0:
		if room_index + 1 < ROOMS.size():
			_advance_in = ADVANCE_DELAY
		else:
			all_complete = true
	elif not complete and room_index + 1 < ROOMS.size():
		_advance_in = -1.0 # stepped back out of the goal
	if _advance_in >= 0.0:
		_advance_in -= delta
		if _advance_in < 0.0:
			load_room(room_index + 1)
			return

	var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	cam_yaw -= look.x * 2.2 * delta
	cam_pitch = clampf(cam_pitch - look.y * 1.5 * delta, -1.3, -0.15)
	_update_camera(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.003
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.003, -1.3, -0.15)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			p1_bean().nudge_lift(0.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			p1_bean().nudge_lift(-0.2)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed)):
		toggle_fullscreen()


func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Shared orbit camera that keeps both players in frame.
func _update_camera(delta: float) -> void:
	var lo: Vector3 = players[0].global_position
	var hi: Vector3 = lo
	for p in players:
		lo = lo.min(p.global_position)
		hi = hi.max(p.global_position)
	var focus := (lo + hi) * 0.5 + Vector3(0, 1.0, 0)
	var dist := clampf(11.0 + (hi - lo).length() * 0.9, 11.0, 55.0)
	var t := 1.0 - exp(-4.0 * delta)
	_cam_focus = _cam_focus.lerp(focus, t)
	_cam_dist = lerpf(_cam_dist, dist, t)
	var rot := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	_camera.global_transform = Transform3D(rot, _cam_focus + rot * Vector3(0, 0, _cam_dist))


func _update_hud() -> void:
	var text := "P1: WASD move  Space jump  |  hold F/LMB on a glowing corner, walk to move it, Space/C or wheel raise/lower hands, Tab fold type, release to crease\n"
	text += "      hold R/RMB: move = slide sheet, Space = flip it over, F/LMB = turn it\n"
	text += "P2: Arrows  / jump  . grab  ; lower  ' fold type  , sheet     Pads: A jump/raise  B lower  X grab  Y fold type  RB sheet\n"
	text += "Solo: V / LB swaps which bean you control (the other keeps holding what it holds)\n"
	text += "Mouse / right stick / Q E: camera   Z: undo fold   Backspace: restart room   PgUp/PgDn: change room   Esc: release mouse   F11: fullscreen\n"
	var room_text := "Room %d of %d: %s\n%s" % [room_index + 1, ROOMS.size(), room.title, room.hint]
	var room_status := room.status()
	if room_status != "":
		room_text += "\n" + room_status
	if solo:
		text += "\nSolo: you're controlling bean %d" % p1_bean().id
	for p in players:
		var st: String = p.fold_status()
		if st != "":
			text += "\nP%d %s" % [p.id, st]
	if all_complete:
		room_text += "\nALL ROOMS COMPLETE!"
	elif complete:
		room_text += "\nROOM COMPLETE! Next room in %d..." % ceili(maxf(_advance_in, 0.0))
	_hud.text = text
	_room_hud.text = room_text


# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	if InputMap.has_action("undo"):
		return # already configured (scene reload)
	var keys := {
		1: {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
			"jump": KEY_SPACE, "lower": KEY_C, "grab": KEY_F, "sheet": KEY_R, "mode": KEY_TAB},
		2: {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
			"jump": KEY_SLASH, "lower": KEY_SEMICOLON, "grab": KEY_PERIOD, "sheet": KEY_COMMA, "mode": KEY_APOSTROPHE},
	}
	for pid in [1, 2]:
		var device: int = pid - 1
		for action in keys[pid]:
			_add_key("p%d_%s" % [pid, action], keys[pid][action])
		_add_axis("p%d_left" % pid, JOY_AXIS_LEFT_X, -1.0, device)
		_add_axis("p%d_right" % pid, JOY_AXIS_LEFT_X, 1.0, device)
		_add_axis("p%d_up" % pid, JOY_AXIS_LEFT_Y, -1.0, device)
		_add_axis("p%d_down" % pid, JOY_AXIS_LEFT_Y, 1.0, device)
		_add_button("p%d_jump" % pid, JOY_BUTTON_A, device)
		_add_button("p%d_lower" % pid, JOY_BUTTON_B, device)
		_add_button("p%d_grab" % pid, JOY_BUTTON_X, device)
		_add_button("p%d_mode" % pid, JOY_BUTTON_Y, device)
		_add_button("p%d_sheet" % pid, JOY_BUTTON_RIGHT_SHOULDER, device)
		_add_axis("cam_left", JOY_AXIS_RIGHT_X, -1.0, device)
		_add_axis("cam_right", JOY_AXIS_RIGHT_X, 1.0, device)
		_add_axis("cam_up", JOY_AXIS_RIGHT_Y, -1.0, device)
		_add_axis("cam_down", JOY_AXIS_RIGHT_Y, 1.0, device)
	_add_mouse("p1_grab", MOUSE_BUTTON_LEFT)
	_add_mouse("p1_sheet", MOUSE_BUTTON_RIGHT)
	_add_key("p1_swap", KEY_V)
	_add_button("p1_swap", JOY_BUTTON_LEFT_SHOULDER, 0)
	_add_key("cam_left", KEY_Q)
	_add_key("cam_right", KEY_E)
	_add_key("undo", KEY_Z)
	_add_button("undo", JOY_BUTTON_BACK, 0)
	_add_key("reset", KEY_BACKSPACE)
	_add_key("room_next", KEY_PAGEDOWN)
	_add_key("room_prev", KEY_PAGEUP)
	_add_button("reset", JOY_BUTTON_START, 0)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _add_key(action: String, key: Key) -> void:
	_ensure_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	_ensure_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_axis(action: String, axis: JoyAxis, value: float, device: int) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = device
	InputMap.action_add_event(action, ev)


func _add_button(action: String, button: JoyButton, device: int) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.device = device
	InputMap.action_add_event(action, ev)
