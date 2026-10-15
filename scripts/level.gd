class_name Level
extends Node3D
## Prototype level: a start island, a 7 m bottomless gap, and a ledge 2.2 m
## high that you can't jump onto. The paper has real weight: slide a flat sheet
## too far over the edge and it tips into the void. Fold part of the big sheet up
## into a ramp, slide it out until the ramp's tip reaches over the ledge (so it's
## held up at both ends) and walk up. A second, smaller sheet on the island is a
## sandbox for free folding (paper planes, reverse folds...). Both players must
## reach the flag.

const PUZZLE_SIZE := Vector2(18, 12)
const PUZZLE_START := Vector3(-12, 0, 0)
const SANDBOX_SIZE := Vector2(6, 8.5)
const SANDBOX_START := Vector3(-26, 0, 9.5)
const GOAL_POS := Vector3(13, 2.2, 0)
const GOAL_RADIUS := 3.5
const GOAL_MIN_Y := 1.9

var sheet_speed := 3.0
var sheet: PaperSheet ## the puzzle sheet
var sheets: Array = []
var players: Array = []
var complete := false

var cam_yaw := -PI * 0.5 ## orbit yaw; this starts out looking toward +X (the ledge)
var cam_pitch := -0.62
var _camera: Camera3D
var _cam_focus := Vector3(-6, 1, 0)
var _cam_dist := 16.0
var _hud: Label
var _undo_order: Array = [] ## sheets in the order they were folded


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_terrain()

	sheet = _add_sheet(PUZZLE_SIZE, PUZZLE_START, 0.0)
	_add_sheet(SANDBOX_SIZE, SANDBOX_START, PI * 0.5)

	var colors := [Color(0.95, 0.4, 0.35), Color(0.35, 0.62, 0.95)]
	for i in 2:
		var p := Player.new()
		p.id = i + 1
		p.color = colors[i]
		p.level = self
		p.spawn = Vector3(-25, 0.1, -2.0 + i * 4.0)
		add_child(p)
		p.global_position = p.spawn
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
	_update_camera(1.0)


func _add_sheet(size: Vector2, pos: Vector3, yaw: float) -> PaperSheet:
	var s := PaperSheet.new()
	s.setup(size)
	s.position = pos
	s.rotation.y = yaw # before entering the tree, so it's part of the spawn transform
	add_child(s)
	s.folded.connect(func() -> void: _undo_order.append(s))
	sheets.append(s)
	return s


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


func _build_terrain() -> void:
	# Start island (top at y=0, edge at x=-1) and the high ledge (x from 6, top at y=2.2).
	_add_block(Vector3(-16, -2, 0), Vector3(30, 4, 26), Color(0.45, 0.62, 0.45))
	_add_block(Vector3(13, -1.9, 0), Vector3(14, 8.2, 16), Color(0.62, 0.5, 0.72))

	# Goal flag.
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 3.0
	pole.mesh = cm
	pole.material_override = _mat(Color(0.9, 0.9, 0.9))
	pole.position = GOAL_POS + Vector3(0, 1.5, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.4, 0.8, 0.05)
	flag.mesh = fm
	flag.material_override = _mat(Color(1, 0.85, 0.2))
	flag.name = "Flag"
	flag.position = GOAL_POS + Vector3(0.7, 2.5, 0)
	add_child(flag)


func _add_block(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


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
		get_tree().reload_current_scene()
		return

	var in_goal := 0
	for p in players:
		var d := Vector2(p.global_position.x - GOAL_POS.x, p.global_position.z - GOAL_POS.z).length()
		if d < GOAL_RADIUS and p.global_position.y >= GOAL_MIN_Y:
			in_goal += 1
	complete = in_goal == players.size()
	var flag := get_node("Flag") as MeshInstance3D
	(flag.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1, 0.5) if complete else Color(1, 0.85, 0.2)

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
			players[0].nudge_lift(0.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			players[0].nudge_lift(-0.2)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	text += "Mouse / right stick / Q E: camera   Z: undo fold   Backspace: restart   Esc: release mouse"
	for p in players:
		var st: String = p.fold_status()
		if st != "":
			text += "\nP%d %s" % [p.id, st]
	if complete:
		text += "\n\nLEVEL COMPLETE!"
	_hud.text = text


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
	_add_key("cam_left", KEY_Q)
	_add_key("cam_right", KEY_E)
	_add_key("undo", KEY_Z)
	_add_button("undo", JOY_BUTTON_BACK, 0)
	_add_key("reset", KEY_BACKSPACE)
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
