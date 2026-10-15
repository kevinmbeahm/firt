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


func fold(fs: Array, g: Vector3, t: Vector3, lowest := false) -> Dictionary:
	var gi := facet_at(fs, g, lowest)
	return PaperModel.plan_fold(fs, gi, g, PaperModel.snap_target(fs, gi, g, t), Vector3.UP)


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
	quit(0 if ok else 1)
