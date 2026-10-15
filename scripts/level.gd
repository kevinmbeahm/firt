class_name Level
extends Node2D
## Prototype level: a start island, a bottomless gap, and a ledge six layers
## high. One sheet of paper spans the gap. Fold it into a stack of three or more
## layers, slide it next to the ledge, and climb it. Both players must reach the
## goal flag.

const UNIT_PX := 22.0
const SHEET_SPEED := 320.0
const PAPER_SIZE := Vector2(1000, 700)
const SHEET_START := Vector2(-150, 0)
const GOAL_POS := Vector2(950, 0)
const GOAL_RADIUS := 100.0
const GOAL_MIN_Z := 5.5

var islands: Array = [
	{"rect": Rect2(-1500, -450, 900, 900), "h": 0, "color": Color(0.36, 0.5, 0.38)},
	{"rect": Rect2(650, -300, 600, 600), "h": 6, "color": Color(0.5, 0.42, 0.55)},
]
var sheet: PaperSheet
var players: Array = []
var complete := false
var _camera: Camera2D
var _hud: Label


func _ready() -> void:
	_setup_input()

	sheet = PaperSheet.new()
	sheet.setup(PAPER_SIZE)
	sheet.position = SHEET_START
	add_child(sheet)

	var colors := [Color(0.93, 0.35, 0.3), Color(0.3, 0.6, 0.95)]
	for i in 2:
		var p := Player.new()
		p.id = i + 1
		p.color = colors[i]
		p.level = self
		p.spawn = Vector2(-1300, -90 + i * 180)
		add_child(p)
		p.respawn()
		players.append(p)

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_camera.position = Vector2(-100, 0)

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)


# --- World queries -----------------------------------------------------------

func island_height(p: Vector2) -> float:
	var h := -1.0
	for isl in islands:
		if (isl.rect as Rect2).has_point(p):
			h = maxf(h, float(isl.h))
	return h


## Height of whatever you could stand on at world point `p` (-1 = void).
func ground_height(p: Vector2) -> float:
	var paper := float(sheet.height_at(p - sheet.position))
	return maxf(island_height(p), paper if paper > 0.0 else -1.0)


func _is_riding(p: Player) -> bool:
	var paper := float(sheet.height_at(p.position - sheet.position))
	return paper > 0.0 and paper > island_height(p.position) and p.z <= paper + 0.05


## Slides the whole (folded) sheet, carrying anyone standing on it.
func push_sheet(v: Vector2) -> void:
	var riders: Array = []
	for p in players:
		if _is_riding(p):
			riders.append(p)
	sheet.position += v
	for p in riders:
		p.position += v


# --- Frame update ------------------------------------------------------------

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("undo"):
		sheet.undo()
	if Input.is_action_just_pressed("reset"):
		get_tree().reload_current_scene()
		return

	var in_goal := 0
	for p in players:
		if p.position.distance_to(GOAL_POS) < GOAL_RADIUS and p.z >= GOAL_MIN_Z:
			in_goal += 1
	complete = in_goal == players.size()

	_update_camera(delta)
	_update_hud()
	queue_redraw()


func _update_camera(delta: float) -> void:
	var lo: Vector2 = players[0].position
	var hi: Vector2 = lo
	for p in players:
		lo = lo.min(p.position)
		hi = hi.max(p.position)
	var span := (hi - lo) + Vector2(900, 700)
	var view := get_viewport_rect().size
	var target_zoom := clampf(minf(view.x / span.x, view.y / span.y), 0.3, 0.8)
	var t := 1.0 - exp(-4.0 * delta)
	_camera.position = _camera.position.lerp((lo + hi) * 0.5, t)
	_camera.zoom = _camera.zoom.lerp(Vector2(target_zoom, target_zoom), t)


func _update_hud() -> void:
	var text := "P1: WASD move  Space jump  F hold on a corner/edge + walk to fold  E hold + move = slide sheet\n"
	text += "P2: Arrows move  / jump  . fold  , slide sheet   (pads: A jump, X fold, RB slide)\n"
	text += "Z undo fold   Backspace restart"
	if complete:
		text += "\n\nLEVEL COMPLETE!"
	_hud.text = text


func _draw() -> void:
	for isl in islands:
		var r: Rect2 = isl.rect
		var h: float = isl.h
		var c: Color = isl.color
		var lift := h * UNIT_PX
		if h > 0.0:
			draw_rect(Rect2(r.position.x, r.end.y - lift, r.size.x, lift), c.darkened(0.45))
		draw_rect(Rect2(r.position - Vector2(0, lift), r.size), c)
		draw_rect(Rect2(r.position - Vector2(0, lift), r.size), c.lightened(0.3), false, 4.0)

	# Goal flag on the ledge.
	var base := GOAL_POS + Vector2(0, -6 * UNIT_PX)
	draw_arc(base, GOAL_RADIUS, 0.0, TAU, 48, Color(1, 0.85, 0.2, 0.6), 4.0)
	draw_line(base, base + Vector2(0, -110), Color(0.9, 0.9, 0.9), 5.0)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -110), base + Vector2(60, -90), base + Vector2(0, -70)
	]), Color(1, 0.85, 0.2) if not complete else Color(0.4, 1, 0.5))


# --- Input -------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		1: {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
			"jump": KEY_SPACE, "grab": KEY_F, "sheet": KEY_E},
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
