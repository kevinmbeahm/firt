extends SceneTree
# Unit test for the rigid-origami model: folds a paper plane step by step and
# checks layer-selective folding, partial angles, crease reuse and tear refusal.
# Run:   godot --headless -s tests/fold_model.gd      (exit code 0 = pass)

const T := PaperModel.THICKNESS * 0.5
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


## Facet lying under sheet-local point p: the top layer, or the bottom one.
func facet_at(fs: Array, p: Vector3, lowest := false) -> int:
	var best := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		var q: Vector3 = f.xf.affine_inverse() * p
		if absf(q.z) > 0.01:
			continue
		var q2 := Vector2(q.x, q.y)
		var inside := Geometry2D.is_point_in_polygon(q2, f.pts)
		for k in f.pts.size():
			var a := f.pts[k]
			var b := f.pts[(k + 1) % f.pts.size()]
			if Geometry2D.get_closest_point_to_segment(q2, a, b).distance_to(q2) < 0.01:
				inside = true
		if inside and (best < 0 or (f.layer < fs[best].layer if lowest else f.layer > fs[best].layer)):
			best = i
	return best


func fold(fs: Array, g: Vector3, t: Vector3, lowest := false, mode := PaperModel.FOLD_NORMAL) -> Dictionary:
	var gi := facet_at(fs, g, lowest)
	return PaperModel.plan_fold(fs, gi, g, PaperModel.snap_target(fs, gi, g, t), Vector3.UP, mode)


func reverse_fold_tests() -> void:
	# A 2 x 8 strip folded in half lengthwise: two layers joined along a spine at x=0.
	var strip := PaperModel.make_sheet(Vector2(2, 8))
	var r := fold(strip, Vector3(-1, T, 4), Vector3(1, T, 4))
	check(r.ok and r.facets.size() == 2, "strip folded in half (spine along x=0)")
	strip = r.facets
	# Grab the spine's tip and carry it out sideways: crease from (0,-2) to (1,-3).
	var g := Vector3(0, T, -4)
	var t := Vector3(2, T, -2)
	var plain := fold(strip, g, t)
	var inside := fold(strip, g, t, false, PaperModel.FOLD_INSIDE_REVERSE)
	var outside := fold(strip, g, t, false, PaperModel.FOLD_OUTSIDE_REVERSE)
	check(plain.ok and inside.ok and outside.ok, "plain, inside-reverse and outside-reverse folds all plan (%s / %s)" % [inside.reason, outside.reason])
	if not (inside.ok and outside.ok):
		return
	check(inside.facets.size() == 4 and outside.facets.size() == 4, "the crease splits both layers")
	for f in inside.facets:
		if absf(f.normal().y) < 0.99:
			check(false, "reverse-folded paper lies flat")
			return
	# The tip pieces are the ones that moved out past x=1 (they point sideways now).
	var moved_in: Array = []
	var moved_out: Array = []
	for f in inside.facets:
		if f.at(PaperGeometry.centroid(f.pts)).x > 0.8:
			moved_in.append(f.layer)
	for f in outside.facets:
		if f.at(PaperGeometry.centroid(f.pts)).x > 0.8:
			moved_out.append(f.layer)
	moved_in.sort()
	moved_out.sort()
	check(moved_in == [1, 2], "inside reverse: the tip tucks between the two layers (tip layers %s of 0..3)" % [moved_in])
	check(moved_out == [0, 3], "outside reverse: the tip wraps around the outside (tip layers %s of 0..3)" % [moved_out])
	var single := fold(PaperModel.make_sheet(Vector2(4, 4)), Vector3(2, T, 2), Vector3(0, T, 0), false, PaperModel.FOLD_INSIDE_REVERSE)
	check(not single.ok, "reverse fold on a single layer is refused (%s)" % single.reason)


func moved_normals(fs: Array, axis: Vector3) -> int:
	var count := 0
	for f in fs:
		if absf((f as PaperModel.Facet).normal().dot(axis)) > 0.99:
			count += 1
	return count


func _init() -> void:
	# 6 x 8.5 sheet; paper (x, y) sits at sheet-local (x, T, -y).
	var fs := PaperModel.make_sheet(Vector2(6, 8.5))
	var r := fold(fs, Vector3(-3, T, -4.25), Vector3(0, T, -1.25))
	check(r.ok and r.facets.size() == 2, "corner folds to the centre line")
	fs = r.facets
	r = fold(fs, Vector3(3, T, -4.25), Vector3(0, T, -1.25))
	check(r.ok and r.facets.size() == 3, "other corner folds to the centre line")
	fs = r.facets
	r = fold(fs, Vector3(-3, T, 4.25), Vector3(3, T, 4.25))
	check(r.ok and r.facets.size() == 4, "fold in half carries the attached flap along")
	fs = r.facets
	var layer_normals: Array = []
	for f in fs:
		layer_normals.append(signf(f.normal().y))
	check(layer_normals == [1.0, -1.0, 1.0, -1.0], "stacking order matches real paper (got %s)" % [layer_normals])

	r = fold(fs, Vector3(3, T, 4.25), Vector3(-1, T, 4.25))
	check(r.ok, "fold the top wing over")
	var before := fs.size()
	fs = r.facets
	check(fs.size() == 2 * before, "wing crease splits every layer but only the top half moves")
	r = fold(fs, Vector3(3, T, 4.25), Vector3(-1, -0.03, 4.25))
	check(r.ok, "fold the bottom wing under")
	fs = r.facets

	r = fold(fs, Vector3(-1, T, 4.25), Vector3(1, 2.0, 4.25))
	check(r.ok and r.facets.size() == fs.size(), "open the top wing to 90 deg along its existing crease (no slivers)")
	fs = r.facets
	check(moved_normals(fs, Vector3.RIGHT) == 2, "only the top wing's two layers stand up")
	r = fold(fs, Vector3(-1, T, 4.25), Vector3(1, -2.0, 4.25), true)
	check(r.ok, "open the bottom wing to -90 deg")
	fs = r.facets
	check(moved_normals(fs, Vector3.RIGHT) == 4, "both wings are now perpendicular to the keel: a paper plane")

	r = fold(fs, Vector3(0, T, 4.25), Vector3(0, T, -4.25))
	check(not r.ok and r.reason == "would tear the paper", "folding the keel across the wings' hinge is refused (%s)" % r.reason)

	var ramp := PaperModel.plan_fold(PaperModel.make_sheet(Vector2(18, 12)), 0,
		Vector3(9, T, 0), Vector3(8.4, 2.63, 0), Vector3.UP)
	var tilt := rad_to_deg((ramp.facets[1] as PaperModel.Facet).normal().angle_to(Vector3.UP))
	check(ramp.ok and absf(tilt - 25.7) < 1.0, "raised hands give a partial fold (ramp at %.1f deg)" % tilt)
	reverse_fold_tests()
	unfold_tests()
	quit(0 if ok else 1)


## Unfolding: carrying a folded flap back only roughly should swing it about its
## existing crease, not cut a new one.
func unfold_tests() -> void:
	var fs := PaperModel.make_sheet(Vector2(18, 12))
	var r := fold(fs, Vector3(9, T, 0), Vector3(3, T, 0))
	check(r.ok and r.facets.size() == 2, "fold a strip over (crease at x=6)")
	fs = r.facets
	var g := Vector3(3, T, 0)
	for t in [Vector3(9, T, 0), Vector3(8.6, T, 0.5), Vector3(8, T, 1)]:
		r = fold(fs, g, t)
		var flat: bool = r.ok and r.facets.size() == 2
		for f in r.get("facets", []):
			flat = flat and f.normal().y > 0.999
		check(flat, "carrying the flap back to %s unfolds it along the old crease (%d facets)" % [t, r.facets.size()])
	r = fold(fs, g, Vector3(6, T + 3, 0))
	check(r.ok and r.facets.size() == 2 and absf(r.facets[1].normal().y) < 0.01,
		"lifting the flap opens it to stand upright on its crease")
	r = fold(fs, g, Vector3(4, T, 0))
	check(r.ok and r.facets.size() > 2, "a new fold on the flap itself still makes a new crease")
