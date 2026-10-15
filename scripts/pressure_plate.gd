class_name PressurePlate
extends Node3D
## A plate in the floor that weighs what's on it (S3): props sitting in the
## column above it count, including props inside paper set down on it, and so
## can beans if `counts_players` is set. It's pressed once the load reaches
## `required_kg`. A "scale" plate (`reset_after` > 0) won't wait forever: if it
## carries some load but not enough for that many seconds, it tips and sends
## the props on it back where they came from.

signal pressed
signal released
signal dumped

const COLUMN_HEIGHT := 3.0

var size := Vector2(3, 3)
var required_kg := 90.0
var counts_players := false
var latch := true ## stays pressed once pressed
var reset_after := 0.0 ## seconds before a partly loaded scale tips; 0 = never
var props: Array = [] ## the props it can weigh
var players: Array = []

var load_kg := 0.0
var is_pressed := false
var waiting := 0.0 ## how long it's been partly loaded

var _top: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D


func setup(plate_size: Vector2, kg: float, weighable: Array, beans: Array = []) -> void:
	size = plate_size
	required_kg = kg
	props = weighable
	players = beans
	_top = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.06, size.y)
	_top.mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.85, 0.55, 0.2)
	_mat.emission_enabled = true
	_mat.emission = Color(0.85, 0.55, 0.2)
	_mat.emission_energy_multiplier = 0.3
	_top.material_override = _mat
	_top.position.y = 0.03
	add_child(_top)
	_label = Label3D.new()
	_label.font_size = 72
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 14
	_label.position = Vector3(0, 2.6, 0)
	add_child(_label)
	_update_look()


func _physics_process(delta: float) -> void:
	load_kg = weigh()
	var now := load_kg >= required_kg - 0.01
	if now and not is_pressed:
		is_pressed = true
		waiting = 0.0
		pressed.emit()
	elif not now and is_pressed and not latch:
		is_pressed = false
		released.emit()
	if reset_after > 0.0 and not is_pressed and load_kg > 0.0:
		waiting += delta
		if waiting >= reset_after:
			waiting = 0.0
			for p in props:
				if _on_plate(p.global_position):
					p.respawn()
			dumped.emit()
	elif load_kg <= 0.0:
		waiting = 0.0
	_update_look()


## Kilograms resting in the column above the plate now (carried props don't count).
func weigh() -> float:
	var kg := 0.0
	for p in props:
		if is_instance_valid(p) and not p.is_carried() and _on_plate(p.global_position):
			kg += p.mass
	if counts_players:
		for b in players:
			if _on_plate(b.global_position + Vector3.UP * 0.2):
				kg += 70.0
	return kg


func _on_plate(world: Vector3) -> bool:
	var q := to_local(world)
	return absf(q.x) <= size.x * 0.5 and absf(q.z) <= size.y * 0.5 and q.y > -0.3 and q.y < COLUMN_HEIGHT


func _update_look() -> void:
	var f := clampf(load_kg / maxf(required_kg, 0.01), 0.0, 1.0)
	var c := Color(0.85, 0.55, 0.2).lerp(Color(0.35, 1.0, 0.45), f if not is_pressed else 1.0)
	_mat.albedo_color = c
	_mat.emission = c
	var text := "%d / %d kg" % [roundi(load_kg), roundi(required_kg)]
	if is_pressed:
		text = "%d kg ✓" % roundi(load_kg)
	elif reset_after > 0.0 and load_kg > 0.0:
		text += "  (tips in %d s)" % ceili(reset_after - waiting)
	_label.text = text


## For the HUD.
func status() -> String:
	if is_pressed:
		return "The scale is down: %d kg." % roundi(load_kg)
	var s := "Scale: %d of %d kg" % [roundi(load_kg), roundi(required_kg)]
	if reset_after > 0.0 and load_kg > 0.0:
		s += " (it tips everything back in %d s unless it's all there)" % ceili(reset_after - waiting)
	return s
