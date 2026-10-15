class_name Player
extends Node2D
## A co-op player. Moves in a top-down view with a vertical `z` axis measured in
## paper-layer units, so platforming over folded stacks works like climbing steps.

const RADIUS := 40.0
const SPEED := 360.0
const GRAVITY := 40.0
const JUMP_SPEED := 15.5 ## apex of about 3 layers
const STEP := 1.01 ## walk up a single layer without jumping
const GRAB_RADIUS := 130.0
const UNIT_PX := 22.0
const FALL_DEATH_Z := -10.0

var id := 1
var color := Color.TOMATO
var level ## Level (untyped to avoid a circular class dependency)
var spawn := Vector2.ZERO

var z := 0.0
var vz := 0.0
var grounded := true
var grabbing := false
var grab_point := Vector2.ZERO
var hover_handle = null ## Vector2 in sheet-local space, or null


func _a(action: String) -> String:
	return "p%d_%s" % [id, action]


func respawn() -> void:
	if grabbing:
		level.sheet.cancel_fold()
		grabbing = false
	position = spawn
	z = level.ground_height(position)
	vz = 0.0


func _physics_process(delta: float) -> void:
	var sheet: PaperSheet = level.sheet
	var dir := Input.get_vector(_a("left"), _a("right"), _a("up"), _a("down"))

	# Separate control: while held, movement pushes the whole folded sheet.
	var pushing_sheet := Input.is_action_pressed(_a("sheet")) and not grabbing
	if pushing_sheet:
		level.push_sheet(dir * level.SHEET_SPEED * delta)
		dir = Vector2.ZERO

	_update_grab(sheet, pushing_sheet)
	_move(dir * SPEED * delta)
	_update_vertical(delta)


func _update_grab(sheet: PaperSheet, pushing_sheet: bool) -> void:
	var local := position - sheet.position
	if grabbing:
		if Input.is_action_pressed(_a("grab")):
			sheet.update_preview(grab_point, local)
		else:
			sheet.finish_fold(grab_point, local)
			grabbing = false
		return
	hover_handle = null
	if pushing_sheet or sheet.fold_owner != null:
		return
	hover_handle = sheet.nearest_handle(local, GRAB_RADIUS)
	if hover_handle != null and Input.is_action_just_pressed(_a("grab")):
		if sheet.begin_fold(self):
			grabbing = true
			grab_point = hover_handle


func _move(step: Vector2) -> void:
	if step == Vector2.ZERO:
		return
	var target := position + step
	if _can_enter(target):
		position = target
	elif _can_enter(Vector2(target.x, position.y)):
		position.x = target.x
	elif _can_enter(Vector2(position.x, target.y)):
		position.y = target.y


func _can_enter(p: Vector2) -> bool:
	return level.ground_height(p) <= z + STEP


func _update_vertical(delta: float) -> void:
	if grounded and Input.is_action_just_pressed(_a("jump")):
		vz = JUMP_SPEED
		grounded = false
	vz -= GRAVITY * delta
	z += vz * delta
	var g: float = level.ground_height(position)
	if g >= 0.0 and z <= g:
		z = g # also lifts the player if paper slides underneath them
		vz = 0.0
		grounded = true
	else:
		grounded = false
	if z < FALL_DEATH_Z:
		respawn()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var g: float = maxf(level.ground_height(position), 0.0)
	var lift := Vector2(0, -z * UNIT_PX)
	var shadow_scale := clampf(1.0 - (z - g) * 0.08, 0.4, 1.0)
	draw_set_transform(Vector2(0, -g * UNIT_PX), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, RADIUS * shadow_scale, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var body := lift + Vector2(0, -RADIUS * 0.6)
	draw_circle(body, RADIUS, color.darkened(0.3))
	draw_circle(body + Vector2(0, -3), RADIUS - 4.0, color)
	draw_circle(body + Vector2(-12, -8), 6.0, Color.WHITE)
	draw_circle(body + Vector2(12, -8), 6.0, Color.WHITE)
	draw_string(ThemeDB.fallback_font, body + Vector2(-8, -RADIUS - 8), "P%d" % id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	var sheet: PaperSheet = level.sheet
	if grabbing:
		# Tether to the corner being dragged.
		var corner := sheet.position + grab_point - position
		draw_line(body, corner, color, 4.0)
		draw_circle(corner, 12.0, color)
	elif hover_handle != null:
		var corner := sheet.position + (hover_handle as Vector2) - position
		draw_arc(corner, 18.0, 0.0, TAU, 24, color, 4.0)
