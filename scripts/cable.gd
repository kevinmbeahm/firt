class_name Cable
extends Node3D
## A taut rope between two points (S7). Paper hangs on it by a crease: carry a
## folded sheet up to it with the crease lying along the rope and it hooks on
## (see PaperSheet.try_hook). A hooked sheet slides downhill along it once
## someone hangs on, and anything that moves this node (a lift) moves the rope
## and what hangs on it.

const RADIUS := 0.05
const PAPER_LAYER := 2 ## the cable's collision layer: paper collides with it, beans and props don't

var _b := Vector3.ZERO ## the far end, in this node's space (the near end is its origin)


## `from` and `to` are in the parent's space; call before adding to the tree.
func setup(from: Vector3, to: Vector3, color := Color(0.85, 0.8, 0.65)) -> void:
	position = from
	_b = to - from
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS
	cm.bottom_radius = RADIUS
	cm.height = _b.length()
	cm.radial_segments = 8
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	mi.material_override = m
	# The cylinder runs along its local Y: turn it to run from here to `to`.
	var y := _b.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), _b * 0.5)
	add_child(mi)
	# Something solid for loose paper to land on (a little fatter than it
	# looks, so thin paper falling onto it doesn't slip through).
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_collision_layer_value(PAPER_LAYER, true)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.1
	cap.height = _b.length() + 0.2
	cs.shape = cap
	cs.transform = mi.transform
	body.add_child(cs)
	add_child(body)


func _ready() -> void:
	add_to_group("cables")


func start() -> Vector3:
	return global_position


func end() -> Vector3:
	return to_global(_b)


func length() -> float:
	return _b.length()


## Unit direction from start to end.
func dir() -> Vector3:
	return (end() - start()).normalized()


## The point `s` metres along it from the start.
func point(s: float) -> Vector3:
	return start() + dir() * s


## How far along it (metres from the start, clamped to the rope) the point
## nearest `p` is.
func along(p: Vector3) -> float:
	return clampf((p - start()).dot(dir()), 0.0, length())


func distance_to(p: Vector3) -> float:
	return p.distance_to(point(along(p)))
