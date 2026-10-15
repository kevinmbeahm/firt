extends SceneTree
# BENCHMARK: fold a traditional paper crane from a square, step by step, using
# only the game's folding operations (the same ones players use):
#   precreases (fold + unfold), a collapse into a square base, kite folds,
#   petal folds (multi-crease collapses) into a bird base, leg narrowing, inside
#   reverse folds for the neck, tail and head, and partial folds to spread the
#   wings.
# After EVERY step the whole sheet is checked: no tears, no paper passing through
# paper, no paper lost, and a physically valid stacking of every flat layer.
# Prints a per-step table (facets, planning time) and exits 0 if the crane is good.
# Run:   godot --headless -s tests/crane.gd
# Look:  godot -s tests/crane.gd -- --shots=/some/dir   (renders the finished crane; needs a display)
#
# Rigid paper only bends at creases, so two steps differ a little from folding
# a crane by hand:
#  * Narrowing the legs also folds a small gusset into the layers above each
#    leg (the crease can't just stop at the wing's hinge); the wings then hinge
#    on the line where those gussets end, a little higher than the bird base's
#    own hinge.
#  * Real cranes puff out their body as the wings open; here the body stays
#    flat and the wings swing out square to it.

const T := PaperModel.THICKNESS * 0.5
const SIZE := 8.0
const AREA := SIZE * SIZE
const UP_DIR := Vector3(0.7071068, 0, -0.7071068) # the bird's "up" in the sheet plane
const LEFT_DIR := Vector3(-0.7071068, 0, -0.7071068) # the bird's left (its neck side)

var fs: Array
var ok := true
var table: Array = []
var total_ms := 0
## Where the neck and tail are folded up (fractions of the leg, from its tip;
## the first that works) and how far they lean out from straight up.
const NECK_AT := [0.9, 0.85, 0.8, 0.75, 0.7]
const NECK_LEAN := 35.0
## The head: how much of the neck's end bends over, and how far it turns from
## the neck's direction (outward and down, like a beak).
const HEAD_LENGTH := 0.9
const HEAD_TURN := 110.0
var last_pivot := Vector3.ZERO
 ## where the last reverse fold's crease crossed its flap


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


## The facet holding paper point p (just inside it), top layer or bottom layer.
func facet_of(p: Vector2, lowest := false) -> int:
	var best := -1
	for i in fs.size():
		if Geometry2D.is_point_in_polygon(p, fs[i].pts):
			if best < 0 or (fs[i].layer < fs[best].layer if lowest else fs[i].layer > fs[best].layer):
				best = i
	return best


## Where paper point p is now.
func at(p: Vector2) -> Vector3:
	for f in fs:
		for q in f.pts:
			if q.distance_to(p) < 1e-3:
				return f.at(p)
	for f in fs:
		if Geometry2D.is_point_in_polygon(p * 0.999, f.pts):
			return f.at(p)
	return Vector3.INF


## Paper point p of the flat, unfolded sheet.
func flat(p: Vector2) -> Vector3:
	return Vector3(p.x, T, -p.y)


func plan(gi: int, g: Vector3, t: Vector3, mode: int, up: Vector3, choice := 0) -> Dictionary:
	if mode == PaperModel.FOLD_COLLAPSE:
		return PaperModel.plan_collapse(fs, gi, g, t, up, {}, choice)
	return PaperModel.plan_fold(fs, gi, g, PaperModel.snap_target(fs, gi, g, t), up, mode)


## Commits a planned step after checking the whole sheet.
func commit(label: String, r: Dictionary, ms: int) -> bool:
	total_ms += ms
	if not r.ok:
		check(false, "%s (%s)" % [label, r.reason])
		return false
	var problems: Array = PaperModel.validate(r.facets, AREA) + PaperLayers.check(r.facets)
	table.append([label, r.facets.size(), ms])
	if not problems.is_empty():
		check(false, "%s leaves the paper in an impossible state: %s" % [label, problems.slice(0, 3)])
		if OS.get_environment("CRANE_DEBUG") != "":
			for f in r.facets:
				print("   layer %2d n=%s centroid %s paper %s moved=%s" % [f.layer, f.normal().snapped(Vector3(.01,.01,.01)),
					f.at(PaperGeometry.centroid(f.pts)).snapped(Vector3(.01,.01,.01)), PaperGeometry.centroid(f.pts).snapped(Vector2(.01,.01)), r.moved.has(f)])
		return false
	fs = r.facets
	PaperModel.remember_creases(fs)
	return true


## One fold: grab paper point p (picking the facet just inside it) and carry it to t.
func step(label: String, p: Vector2, inside: Vector2, t: Vector3, mode := PaperModel.FOLD_NORMAL,
		up := Vector3.UP, lowest := false) -> bool:
	var gi := facet_of(inside, lowest)
	if gi < 0:
		check(false, "%s: nothing to grab" % label)
		return false
	var t0 := Time.get_ticks_msec()
	var r := plan(gi, fs[gi].at(p), t, mode, up)
	return commit(label, r, Time.get_ticks_msec() - t0)


## Fold then unfold, leaving a crease.
func crease(label: String, p: Vector2, inside: Vector2, t: Vector3, up := Vector3.UP, lowest := false) -> bool:
	var start := at(p)
	return step(label + " (fold)", p, inside, t, PaperModel.FOLD_NORMAL, up, lowest) \
		and step(label + " (unfold)", p, inside, start, PaperModel.FOLD_NORMAL, up, lowest)


## A reverse fold the way a player would do it: try crease positions and angles,
## nearest to the intended direction first, and keep the first one that works.
func reverse_fold(label: String, paper_tip: Vector2, inside: Vector2, base: Vector3, axis_dir: Vector3,
		length: float, fractions: Array, ideal_deg: float) -> bool:
	var gi := facet_of(inside)
	var tip := at(paper_tip)
	var angles: Array = []
	for k in range(0, 181, 15):
		angles.append(ideal_deg + k)
		if k > 0:
			angles.append(ideal_deg - k)
	var t0 := Time.get_ticks_msec()
	for deg in angles:
		for frac in fractions:
			var pivot: Vector3 = base + axis_dir * length * frac
			var to: Vector3 = pivot + axis_dir.rotated(Vector3.UP, deg_to_rad(deg)) * tip.distance_to(pivot)
			var r := PaperModel.plan_fold(fs, gi, tip, to, Vector3.UP, PaperModel.FOLD_INSIDE_REVERSE)
			if r.ok:
				last_pivot = pivot
				print("      %s: crease %.0f%% along, turned %+.0f deg (aimed %+.0f)" % [label, frac * 100.0, deg, ideal_deg])
				return commit(label, r, Time.get_ticks_msec() - t0)
	check(false, "%s: no physically possible reverse fold found" % label)
	return false


## Sheet-local point of the bird's own frame: `u` up from the bottom of the
## bird base, `l` to the bird's left, in the body's plane.
func bird(u: float, l: float) -> Vector3:
	return flat(Vector2(-SIZE * 0.5, -SIZE * 0.5)) + UP_DIR * u + LEFT_DIR * l


## The flat facet at bird point (u, l): the top one, or the bottom one.
func facet_at_bird(u: float, l: float, lowest := false) -> int:
	var p := bird(u, l)
	var best := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		if absf(f.normal().y) < 0.99:
			continue
		var q: Vector3 = f.xf.affine_inverse() * p
		if Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), f.pts):
			if best < 0 or (f.layer < fs[best].layer if lowest else f.layer > fs[best].layer):
				best = i
	return best


## A fold given in the bird's frame: grab the paper at `from` (on the facet
## found at `probe`) and carry it to `to`.
func bird_step(label: String, from: Vector2, probe: Vector2, to: Vector2, back := false, lift := 0.0) -> bool:
	var gi := facet_at_bird(probe.x, probe.y, back)
	if gi < 0:
		check(false, "%s: nothing to grab" % label)
		return false
	var t0 := Time.get_ticks_msec()
	var up := Vector3.DOWN if back else Vector3.UP
	var r := PaperModel.plan_fold(fs, gi, bird(from.x, from.y), bird(to.x, to.y) + up * lift, up)
	return commit(label, r, Time.get_ticks_msec() - t0)


## Inside reverse folds one narrow leg up into a neck or tail leaning out
## `side * NECK_LEAN` from straight up, creased as high up the leg as it will go.
func neck_fold(label: String, corner: Vector2, side: float) -> bool:
	var gi := facet_of(corner * 0.99)
	var tip := at(corner)
	var dir := UP_DIR.rotated(Vector3.UP, deg_to_rad(side * NECK_LEAN))
	var t0 := Time.get_ticks_msec()
	for frac in NECK_AT:
		var pivot := bird(SIZE * 0.5 * frac, 0.0)
		var to := pivot + dir * tip.distance_to(pivot)
		var r := PaperModel.plan_fold(fs, gi, tip, to, Vector3.UP, PaperModel.FOLD_INSIDE_REVERSE)
		if r.ok:
			last_pivot = pivot
			print("      %s: crease %.0f%% up the leg, leaning out %.0f deg" % [label, frac * 100.0, NECK_LEAN])
			return commit(label, r, Time.get_ticks_msec() - t0)
	check(false, "%s: no physically possible reverse fold found" % label)
	return false


func outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for f in fs:
		for p in f.pts:
			var w: Vector3 = f.at(p)
			pts.append(Vector2(w.x, w.z))
	return Geometry2D.convex_hull(pts)


func _init() -> void:
	fs = PaperModel.make_sheet(Vector2(SIZE, SIZE))
	var h := SIZE * 0.5
	var A := Vector2(-h, h)
	var B := Vector2(h, h)
	var C := Vector2(h, -h)
	var D := Vector2(-h, -h)
	var go := true

	print("== square base ==")
	go = go and crease("valley diagonal B-D", A, A * 0.97, flat(C))
	go = go and crease("valley diagonal A-C", B, B * 0.97, flat(D))
	go = go and crease("mountain midline", Vector2(0, h), Vector2(0.1, h - 0.1), flat(Vector2(0, -h)) - Vector3(0, 0.05, 0), Vector3.DOWN)
	go = go and crease("mountain midline 2", Vector2(-h, 0), Vector2(-h + 0.1, 0.1), flat(Vector2(h, 0)) - Vector3(0, 0.05, 0), Vector3.DOWN)
	if go:
		# Collapse: carry corner B onto corner D; of the shapes that fit, take the
		# square base (a square a quarter of the paper's area).
		var gi := facet_of(B * 0.97)
		var t0 := Time.get_ticks_msec()
		var first := plan(gi, at(B), flat(D), PaperModel.FOLD_COLLAPSE, Vector3.UP)
		var picked := {}
		for c in first.get("choices", 0):
			var r := plan(gi, at(B), flat(D), PaperModel.FOLD_COLLAPSE, Vector3.UP, c)
			if not r.ok:
				continue
			var saved := fs
			fs = r.facets
			var hull := outline()
			fs = saved
			var area := absf(PaperGeometry.signed_area(hull))
			var box := Rect2(hull[0], Vector2.ZERO)
			for q in hull:
				box = box.expand(q)
			# A square base folds every crease but the B-D diagonal, whose halves
			# lie flat down the middle of the front and back flaps. (Paper folded
			# in quarters has the same outline.)
			var folded := true
			for hg in PaperModel.hinges(r.facets):
				var mid: Vector2 = (hg.seg[0] + hg.seg[1]) * 0.5
				var on_bd := absf(mid.x - mid.y) < 0.01
				folded = folded and hg.state == (0 if on_bd else 1)
			if folded and absf(area - AREA / 4.0) < 0.1 and absf(box.size.x - h) < 0.01 and absf(box.size.y - h) < 0.01:
				picked = r
				print("      collapse option %d of %d is the square base" % [c + 1, first.choices])
				break
		go = commit("collapse into square base", picked if not picked.is_empty() else first, Time.get_ticks_msec() - t0)

	# Bird base: kite folds, top triangle, unfold, petal fold -- front, then back.
	var kite_tip := flat(D) + UP_DIR * h # where the side corners land on the centre line
	var hinge_mid := flat(D) + UP_DIR * h
	var top_fold_to := Vector3(-2.343146, T, 2.343146) * (SIZE / 8.0)
	var petal_tip := Vector3(1.656854, T, -1.656854) * (SIZE / 8.0)
	# Carrying B over onto D put B's flap on top: that's the front.
	var front_corner := B
	var back_corner := D
	if go and fs[facet_of(D * 0.97)].layer > fs[facet_of(B * 0.97)].layer:
		front_corner = D
		back_corner = B
	for side in ["front", "back"]:
		if not go:
			break
		var back: bool = side == "back"
		var up := Vector3.DOWN if back else Vector3.UP
		var corner: Vector2 = back_corner if back else front_corner
		var s1: Vector2 = Vector2(0, h) if corner == B else Vector2(-h, 0)
		var s2: Vector2 = Vector2(h, 0) if corner == B else Vector2(0, -h)
		print("== %s petal fold ==" % side)
		var k1 := at(s1)
		var k2 := at(s2)
		var o0 := at(Vector2.ZERO)
		go = go and step("kite fold left (%s)" % side, s1, s1 * 0.97 + corner * 0.03, kite_tip, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("kite fold right (%s)" % side, s2, s2 * 0.97 + corner * 0.03, kite_tip, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("top triangle down (%s)" % side, Vector2.ZERO, corner * 0.02, top_fold_to, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("top triangle back up (%s)" % side, Vector2.ZERO, corner * 0.02, o0, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("unfold kite right (%s)" % side, s2, s2 * 0.97 + corner * 0.03, k2, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("unfold kite left (%s)" % side, s1, s1 * 0.97 + corner * 0.03, k1, PaperModel.FOLD_NORMAL, up, back)
		go = go and step("PETAL FOLD (%s)" % side, corner, corner * 0.97, petal_tip, PaperModel.FOLD_COLLAPSE, up, back)
	if go:
		var bottom := flat(D)
		check(at(D).distance_to(petal_tip) < 0.05 and at(B).distance_to(petal_tip) < 0.05,
			"bird base: both petals point up")
		check(at(A).distance_to(bottom) < 0.05 and at(C).distance_to(bottom) < 0.05,
			"bird base: both legs (A, C) point down")

	# Narrow the legs: fold the lower edges of each leg to the centre line, on
	# the front and then the back. (With rigid paper the crease carries on a
	# little way into the layers above the leg, under the wings.)
	if go:
		print("== narrow the legs ==")
		var w := h * tan(PI / 8.0) # half-width of the bird base at the wing hinge
		var reach := sqrt(h * h + w * w) # where a side corner lands on the centre line
		for back in [false, true]:
			var side_name := "back" if back else "front"
			go = go and bird_step("narrow left leg (%s)" % side_name, Vector2(h, w), Vector2(h * 0.75, w * 0.6), Vector2(reach, 0), back)
			go = go and bird_step("narrow right leg (%s)" % side_name, Vector2(h, -w), Vector2(h * 0.75, -w * 0.6), Vector2(reach, 0), back)

	# The narrowing creases end where they meet the wings' edges: the shoulders.
	# The wings will hinge on the line through them.
	var shoulder := 2.0 * h * tan(PI / 8.0) / (tan(PI / 16.0) + tan(PI / 8.0))

	# Neck and tail: inside reverse fold each narrow leg up and out between the
	# body's layers, creased high up the leg so they're long; then bend the head
	# down at the end of the neck.
	var neck_base := Vector3.ZERO
	var neck_top := Vector3.ZERO # where the neck ends and the head bends off
	if go:
		print("== neck, tail, head ==")
		go = go and neck_fold("NECK (inside reverse fold)", A, 1.0)
		neck_base = last_pivot
		go = go and neck_fold("TAIL (inside reverse fold)", C, -1.0)
	if go:
		var neck_tip := at(A)
		neck_top = neck_tip
		var neck_dir := (neck_tip - neck_base).normalized()
		go = go and reverse_fold("HEAD (inside reverse fold)", A, A * 0.99, neck_tip - neck_dir * HEAD_LENGTH, neck_dir, HEAD_LENGTH, [0.0, 0.2, -0.2], HEAD_TURN)

	# Wings: swing each petal 90 degrees about the line across the shoulders
	# (front up, back down). (The bird base's own hinge is lower, but there the
	# narrowed shoulders would have to bend as the wings open, which real paper
	# does by puffing out the body and rigid paper can't.)
	if go:
		print("== wings ==")
		var span := SIZE - shoulder
		go = go and bird_step("FRONT WING spread", Vector2(SIZE, 0), Vector2(SIZE - 0.3, 0), Vector2(shoulder, 0), false, span)
		go = go and bird_step("BACK WING spread", Vector2(SIZE, 0), Vector2(SIZE - 0.3, 0), Vector2(shoulder, 0), true, span)

	if go:
		print("== the crane ==")
		var body_n := Vector3.UP
		var head := at(A)
		var tail := at(C)
		var wing1 := at(front_corner)
		var wing2 := at(back_corner)
		var centre := bird(shoulder, 0.0)
		var left := Vector3(-0.7071068, 0, -0.7071068) # the bird's left in the sheet plane
		check(absf(head.y - T) < 0.3 and absf(tail.y - T) < 0.3, "neck and tail lie in the body's plane")
		check((head - centre).dot(left) > 0.3 and (tail - centre).dot(left) < -0.3,
			"neck and tail stick out on opposite sides of the body")
		var up_of := func(p: Vector3) -> float: return (p - flat(D)).dot(UP_DIR)
		check(up_of.call(neck_top) > shoulder + 0.5 and up_of.call(tail) > shoulder + 0.5,
			"neck and tail rise well above the wings, as on a real crane")
		check(up_of.call(head) < up_of.call(neck_top) - 0.3 and (head - centre).dot(left) > (neck_top - centre).dot(left) - 0.1,
			"the head bends forward and down off the end of the neck")
		check(wing1.y > (SIZE - shoulder) * 0.9 and wing2.y < -(SIZE - shoulder) * 0.9, "the wings spread out of the body's plane on both sides")
		var vertical := 0
		for f in fs:
			if absf(f.normal().dot(body_n)) < 0.01:
				vertical += 1
		check(vertical > 0, "wing paper stands perpendicular to the body (%d facets)" % vertical)
		var problems: Array = PaperModel.validate(fs, AREA) + PaperLayers.check(fs)
		check(problems.is_empty(), "the finished crane is physically valid: no tears, no paper through paper, valid layering")
		# Proportions in the bird's own frame (from the bottom of the body).
		var base := flat(D)
		var describe := func(name: String, p: Vector3) -> void:
			print("      %-10s %4.1f m up, %+4.1f m to the left, %+4.1f m out of the body plane" % [name, (p - base).dot(UP_DIR), (p - centre).dot(left), p.y - T])
		describe.call("neck top", neck_top)
		describe.call("head", head)
		describe.call("tail", tail)
		describe.call("wing tips", wing1)
		describe.call("wing hinge", centre)

	print("\n step                                   facets   ms")
	for row in table:
		print(" %-38s %6d %6d" % row)
	print(" %d steps, %d facets, %.1f s planning in total" % [table.size(), fs.size(), total_ms / 1000.0])
	check(go and ok, "PAPER CRANE FOLDED")
	exit_code = 0 if ok and go else 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
	if shots_dir == "":
		quit(exit_code)


var exit_code := 0
var shots_dir := ""
var level
var frames := 0


## With --shots, show the finished crane in the game world and photograph it
## from the side (the classic crane profile), three-quarters and above.
const SHOTS := [
	["crane_side.png", Vector3(0, 0.15, 1), 10.0],
	["crane_three_quarter.png", Vector3(0.9, 0.5, 0.8), 10.0],
	["crane_above.png", Vector3(0.3, 1.0, 0.45), 11.0],
]


func _process(_delta: float) -> bool:
	if shots_dir == "":
		return false
	frames += 1
	if frames == 1:
		level = load("res://scenes/main.tscn").instantiate()
		root.add_child(level)
	elif frames == 3:
		var sheet: PaperSheet = level.sheets[1]
		sheet.freeze = true
		sheet.facets = fs
		sheet._refresh()
		# Stand it up: the bird's "up" points up and its body faces +Z.
		var local := Basis(UP_DIR, Vector3.UP, UP_DIR.cross(Vector3.UP))
		var world := Basis(Vector3.UP, Vector3(0, 0, 1), Vector3.UP.cross(Vector3(0, 0, 1)))
		var pose := world * local.transposed()
		var centre: Vector3 = pose * bird(SIZE * 0.5, 0.0)
		sheet.global_transform = Transform3D(pose, Vector3(-25, 0.6 + SIZE * 0.5, 9) - centre)
		for p in level.players:
			p.global_position = Vector3(-22 + p.id * 1.2, 0.1, 6)
		level.set_process(false) # hold the camera still
		level._hud.visible = false
	elif frames >= 30 and (frames - 30) % 20 == 0:
		var k := (frames - 30) / 20
		if k > 0:
			var prev: Array = SHOTS[k - 1]
			root.get_viewport().get_texture().get_image().save_png(shots_dir.path_join(prev[0]))
		if k >= SHOTS.size():
			quit(exit_code)
			return false
		var shot: Array = SHOTS[k]
		var target := Vector3(-25, 0.6 + SIZE * 0.5, 9)
		var cam: Camera3D = level._camera
		cam.global_position = target + (shot[1] as Vector3).normalized() * float(shot[2])
		cam.look_at(target, Vector3.UP)
	return false
