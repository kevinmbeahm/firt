class_name Water
extends Node3D
## A body of water (S5): everything over a rectangle of the world, between its
## surface (this node's height) and `depth` below. Folded paper floats on the
## dry space its hull keeps out (Hull), a flat sheet floats as a thin raft,
## props float or sink, and beans can't swim. A `current` carries things
## along; with `falls`, its downstream edge is a waterfall: whatever goes over
## comes back where it started.

const DENSITY := 250.0 ## kg per cubic metre (this world's paper is huge: so is its water's lift)
const GRAVITY := 9.8

var size := Vector2(10, 10) ## x, z
var depth := 6.0
var current := Vector3.ZERO ## m/s, horizontal
var falls := false

var _mat: StandardMaterial3D


## Call before adding to the tree; `center` is the middle of the surface.
func setup(center: Vector3, extent: Vector2, water_depth: float, flow := Vector3.ZERO, waterfall := false) -> void:
	position = center
	size = extent
	depth = water_depth
	current = flow
	falls = waterfall
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, depth, size.y)
	mi.mesh = bm
	mi.position.y = -depth * 0.5 - 0.01
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.2, 0.45, 0.75, 0.55)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.15
	_mat.metallic_specular = 0.8
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _ready() -> void:
	add_to_group("waters")


func surface() -> float:
	return global_position.y


## Whether `p` is over this water (within its rectangle) and above its bottom.
func over(p: Vector3) -> bool:
	var q := p - global_position
	return absf(q.x) <= size.x * 0.5 and absf(q.z) <= size.y * 0.5 and q.y > -depth


## The water any part of `box` (world) is over, if any.
static func find_box(tree: SceneTree, box: AABB) -> Water:
	for n in tree.get_nodes_in_group("waters"):
		var w := n as Water
		var q := w.global_position
		if box.position.x <= q.x + w.size.x * 0.5 and box.end.x >= q.x - w.size.x * 0.5 \
				and box.position.z <= q.z + w.size.y * 0.5 and box.end.z >= q.z - w.size.y * 0.5 \
				and box.end.y > q.y - w.depth:
			return w
	return null


## The water under (or around) `p`, if any.
static func find(tree: SceneTree, p: Vector3) -> Water:
	for w in tree.get_nodes_in_group("waters"):
		if (w as Water).over(p):
			return w
	return null


func _physics_process(_delta: float) -> void:
	if not falls or current.length() < 0.01:
		return
	# Over the falls: whatever floats past the downstream edge goes back to
	# where it started.
	var flow := current.normalized()
	var edge := absf(flow.x) * size.x * 0.5 + absf(flow.z) * size.y * 0.5
	for n in get_tree().get_nodes_in_group("sheets") + get_tree().get_nodes_in_group("props") + get_tree().get_nodes_in_group("players"):
		var p: Vector3 = (n as Node3D).global_position - global_position
		var side := Vector3(p.x, 0.0, p.z)
		var across := side - flow * side.dot(flow)
		if side.dot(flow) > edge and across.length() < maxf(size.x, size.y) and p.y < 1.0:
			n.call("respawn")
