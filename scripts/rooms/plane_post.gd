extends Room
## P8 "Paper Plane Post": a canyon too wide to bridge, with warm air rising
## out of it, and a target on a board on the far side. Fold the light sheet
## into a paper plane (its creases are printed), hold it up over your head and
## throw it across: hit the ring and a bridge slides out. The updraft has three
## strengths, one for each plate on this side: too gentle and the plane sinks
## below the ring, too strong and it sails over the board. A flat sheet only
## hangs in the rising air, and a crumpled one drops.

const CANYON := Vector2(0, 24) ## x from..to
const RING := Vector3(24.3, 3.0, 0) ## the target's centre, on the board's face
const RING_R := 1.6
const BOARD_TOP := 5.6
const UPDRAFTS := [1.0, 2.0, 3.0] ## m/s, for the plates from left to right
const HOVER_TIME := 10.0 ## seconds a sheet can be out over the canyon (or past it) before it's blown back to its start

var plates: Array = []
var updraft: Wind
var bridge: AnimatableBody3D
var hit := false
var _hover := 0.0


func build() -> void:
	title = "Paper Plane Post"
	hint = "Hit the ring on the far board with a paper plane to bring out the bridge. Fold the plane on its printed creases, pick it up (sheet handling + grab), aim it (fold type rolls it, with sheet handling it turns round) and let go to throw. One of you picks the updraft's strength on the plates."
	spawns = [Vector3(-14, 0.1, 2), Vector3(-14, 0.1, -2)]
	cam_yaw = -PI * 0.5
	var rock := Color(0.62, 0.55, 0.47)
	add_block(Vector3(-13, -4, 0), Vector3(26, 8, 24), rock) # near side, x -26..0
	add_block(Vector3(36, -4, 0), Vector3(24, 8, 24), rock) # far side, x 24..48
	add_block(Vector3(12, -24, 0), Vector3(24, 1, 24), Color(0.3, 0.28, 0.27)) # the canyon floor, far below
	for i in 4:
		add_block(Vector3(3 + i * 6, -23.4, 0), Vector3(4, 0.2, 10), Color(0.2, 0.2, 0.22)) # vents
	updraft = Wind.new()
	updraft.setup(Vector3(12, -6, 0), Vector3(CANYON.y - CANYON.x, 36, 18), Vector3.ZERO)
	add_child(updraft)
	# The target board, the ring on it, and the bridge hidden in the far side.
	add_block(Vector3(RING.x + 0.25, BOARD_TOP * 0.5, RING.z), Vector3(0.5, BOARD_TOP, 6), Color(0.85, 0.82, 0.74))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - 0.15
	tm.outer_radius = RING_R + 0.15
	ring.mesh = tm
	ring.material_override = mat(Color(0.85, 0.2, 0.15))
	ring.position = RING + Vector3(-0.05, 0, 0)
	ring.rotation.z = PI * 0.5
	add_child(ring)
	bridge = add_door(Vector3(36, -0.25, 7), Vector3(CANYON.y - CANYON.x, 0.5, 3), Color(0.55, 0.4, 0.28))
	# The plates that set the updraft.
	var names := ["gentle", "steady", "strong"]
	for i in 3:
		var p := add_plate(Vector3(-4, 0, -6 + i * 3.5), Vector2(2.5, 2.5), 50.0)
		p.counts_players = true
		p.latch = false
		plates.append(p)
		var l := Label3D.new()
		l.text = names[i]
		l.font_size = 64
		l.pixel_size = 0.008
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.outline_size = 12
		l.position = Vector3(-4, 1.2, -6 + i * 3.5)
		add_child(l)
	# A 4 x 6 sheet (light enough to pick up), printed with a paper plane:
	# the nose's two corner folds, the middle, and the wings.
	var k := 2.0 / 3.0
	add_sheet(Vector2(4, 6), Vector3(-10, 0, 7), 0.0, [
		{"a": Vector2(0, -3), "b": Vector2(-2, -1), "mv": 1},
		{"a": Vector2(0, -3), "b": Vector2(2, -1), "mv": 1},
		{"a": Vector2(0, -3), "b": Vector2(0, 3), "mv": 1},
		{"a": Vector2(-k, k - 3), "b": Vector2(-k, 3), "mv": -1},
		{"a": Vector2(k, k - 3), "b": Vector2(k, 3), "mv": -1},
		{"a": Vector2(-k, k - 3), "b": Vector2(k, k - 3), "mv": -1},
	])
	add_weight_block(Vector3(-20, 0.5, -8))
	add_goal(Vector3(32, 0, 7), 3.0, -0.4)


## The updraft's strength: the strongest plate pressed, or none.
func setting() -> int:
	var out := -1
	for i in plates.size():
		if plates[i].is_pressed:
			out = i
	return out


func update_room(delta: float, complete: bool) -> void:
	super.update_room(delta, complete)
	var i := setting()
	updraft.velocity = Vector3(0, UPDRAFTS[i] if i >= 0 else 0.0, 0)
	if not hit:
		for s in sheets:
			if _in_ring(s):
				hit = true
				open_bridge()
	# Paper hanging in the updraft would never come down, and paper on the
	# far side can't be fetched: after a while it's blown back to its start.
	var gone := false
	for s in sheets:
		if s.holder == null and s.global_position.x > CANYON.x + 1.0:
			gone = true
	_hover = _hover + delta if gone else 0.0
	if _hover > HOVER_TIME:
		_hover = 0.0
		for s in sheets:
			if s.global_position.x > CANYON.x + 1.0:
				s.respawn()


## Whether any of `s` has flown into the board, inside the ring. (Not slid
## down into it after hitting the board higher up.)
func _in_ring(s: PaperSheet) -> bool:
	if s.global_position.x < RING.x - 8.0 or s.linear_velocity.x < 2.0:
		return false
	for p in s._all_points():
		var w: Vector3 = s.global_transform * p
		if w.x > RING.x - 0.4 and w.x < RING.x + 0.2 and Vector2(w.y - RING.y, w.z - RING.z).length() < RING_R:
			return true
	return false


func open_bridge() -> void:
	var tw := create_tween()
	tw.tween_property(bridge, "position:x", (CANYON.x + CANYON.y) * 0.5, 2.5)


func status() -> String:
	var i := setting()
	var s: String = "Updraft: " + (["gentle", "steady", "strong"][i] if i >= 0 else "off")
	s += ".  The bridge is out." if hit else ".  Hit the ring to bring out the bridge."
	return s
