class_name Wind
extends Node3D
## Moving air over a box of the world (S6): a fan blowing across a canyon, an
## updraft over a vent. Paper anywhere feels the air moving past it (still air
## too: that's what lets a plane glide and makes a sheet flutter down; see
## PaperSheet._update_air); inside a Wind box the air itself moves at
## `velocity`. Streaks drift along it so you can see it.

const STREAKS := 24

var size := Vector3(10, 10, 10)
var velocity := Vector3.ZERO ## m/s

var _streaks: Array = []
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


## Call before adding to the tree; `center` is the middle of the box.
func setup(center: Vector3, box: Vector3, air: Vector3) -> void:
	position = center
	size = box
	velocity = air
	_rng.seed = 7
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1, 1, 1, 0.35)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in STREAKS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 1.2)
		mi.mesh = bm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(_rng.randf_range(-0.5, 0.5) * size.x, _rng.randf_range(-0.5, 0.5) * size.y, _rng.randf_range(-0.5, 0.5) * size.z)
		add_child(mi)
		_streaks.append(mi)


func _ready() -> void:
	add_to_group("winds")


func covers(p: Vector3) -> bool:
	var q := p - global_position
	return absf(q.x) <= size.x * 0.5 and absf(q.y) <= size.y * 0.5 and absf(q.z) <= size.z * 0.5


## The air's velocity at `p` (still air, unless a Wind box covers it).
static func at(tree: SceneTree, p: Vector3) -> Vector3:
	var v := Vector3.ZERO
	for n in tree.get_nodes_in_group("winds"):
		var w := n as Wind
		if w.covers(p):
			v += w.velocity
	return v


func _process(delta: float) -> void:
	var speed := velocity.length()
	for mi in _streaks:
		var m := mi as MeshInstance3D
		m.visible = speed > 0.1
		if speed <= 0.1:
			continue
		m.look_at(m.global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)
		m.position += velocity * delta
		var h := size * 0.5
		var q := m.position
		if absf(q.x) > h.x or absf(q.y) > h.y or absf(q.z) > h.z:
			# Round again from the upwind side.
			var back := -velocity.normalized()
			var start := Vector3(_rng.randf_range(-h.x, h.x), _rng.randf_range(-h.y, h.y), _rng.randf_range(-h.z, h.z))
			for k in 3:
				if absf(back[k]) > 0.5:
					start[k] = signf(back[k]) * h[k]
			m.position = start
