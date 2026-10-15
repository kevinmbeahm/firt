class_name Level
extends Node3D
## Prototype level: a start island, a bottomless gap, and a ledge 2.6 m high.
## One giant sheet of paper spans the gap. Fold it into a stack of three or more
## layers, slide it up against the ledge with both players riding on it, and hop
## across. Both players must reach the flag.

const PAPER_SIZE := Vector2(18, 12)
const SHEET_START := Vector3(-1, 0, 0)
## Region (world XZ) the sheet's bounding box must stay inside, so it can't be
## slid through the ledge or lost in the void.
const SHEET_LIMIT := Rect2(-38, -14, 51.5, 28)
const GOAL_POS := Vector3(21, 2.6, 0)
const GOAL_RADIUS := 3.5
const GOAL_MIN_Y := 2.3

var sheet_speed := 3.0
var sheet: PaperSheet
var players: Array = []
var complete := false

var cam_yaw := -PI * 0.5 ## orbit yaw; this starts out looking toward +X (the ledge)
var cam_pitch := -0.62
var _camera: Camera3D
var _cam_focus := Vector3(-6, 1, 0)
var _cam_dist := 16.0
var _hud: Label


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_terrain()

	sheet = PaperSheet.new()
	sheet.setup(PAPER_SIZE)
	sheet.position = SHEET_START
	add_child(sheet)
	sheet.folded.connect(_lift_players)

	var colors := [Color(0.95, 0.4, 0.35), Color(0.35, 0.62, 0.95)]
	for i in 2:
		var p := Player.new()
		p.id = i + 1
		p.color = colors[i]
		p.level = self
		p.spawn = Vector3(-24, 0.1, -2.0 + i * 4.0)
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
	# Start island (top at y=0) and the high ledge (top at y=2.6).
	_add_block(Vector3(-20, -2, 0), Vector3(22, 4, 26), Color(0.45, 0.62, 0.45))
	_add_block(Vector3(21, -1.7, 0), Vector3(14, 8.6, 16), Color(0.62, 0.5, 0.72))

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


## Slides the whole (folded) sheet; anyone standing on it is carried by physics.
func push_sheet(v: Vector3) -> void:
	var b := sheet.local_bounds()
	var p := sheet.position + Vector3(v.x, 0.0, v.z)
	p.x = clampf(p.x, SHEET_LIMIT.position.x - b.position.x, SHEET_LIMIT.end.x - b.end.x)
	p.z = clampf(p.z, SHEET_LIMIT.position.y - b.position.y, SHEET_LIMIT.end.y - b.end.y)
	sheet.position = p


## After a fold changes the stack under someone's feet, raise them onto it.
func _lift_players() -> void:
	for p in players:
		var top: float = sheet.top_at(p.global_position)
		if top < 0.0:
			continue
		var y: float = sheet.global_position.y + top
		if p.global_position.y < y and p.global_position.y > y - 4.0:
			p.global_position.y = y + 0.05
			p.velocity.y = 0.0


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("undo"):
		sheet.undo()
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
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Shared orbit camera that keeps both players (and their reach) in frame.
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
	var text := "P1: WASD move  Space jump  hold F / LMB near a corner or edge, then walk = fold  hold R / RMB + move = slide sheet\n"
	text += "P2: Arrows move  / jump  hold . to fold  hold , + move to slide sheet   (pads: A jump, X fold, RB slide sheet)\n"
	text += "Mouse / right stick / Q E: camera   Z: undo fold   Backspace: restart   Esc: release mouse   (click to capture mouse)"
	if complete:
		text += "\n\nLEVEL COMPLETE!"
	_hud.text = text


# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	if InputMap.has_action("undo"):
		return # already configured (scene reload)
	var keys := {
		1: {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
			"jump": KEY_SPACE, "grab": KEY_F, "sheet": KEY_R},
		2: {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
			"jump": KEY_SLASH, "grab": KEY_PERIOD, "sheet": KEY_COMMA},
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
		_add_button("p%d_grab" % pid, JOY_BUTTON_X, device)
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
