extends SceneTree
# Unit test for boxes and hulls: folds a tray from an 8 x 8 sheet (two sides
# up, then the two ends, whose corners tuck into gussets), and checks with the
# voxel hull that it holds water while a trough (ends open) and a flat sheet
# don't, and that it swamps when the rim goes under.
# Run:   godot --headless -s tests/tray_hull.gd      (exit code 0 = pass)

const T := PaperModel.THICKNESS * 0.5
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		ok = false


func facet_at(fs: Array, p: Vector3) -> int:
	var best := -1
	for i in fs.size():
		var f: PaperModel.Facet = fs[i]
		var q: Vector3 = f.xf.affine_inverse() * p
		if absf(q.z) > 0.01:
			continue
		var q2 := Vector2(q.x, q.y)
		var inside := Geometry2D.is_point_in_polygon(q2, f.pts)
		for k in f.pts.size():
			if Geometry2D.get_closest_point_to_segment(q2, f.pts[k], f.pts[(k + 1) % f.pts.size()]).distance_to(q2) < 0.01:
				inside = true
		if inside and (best < 0 or f.layer > fs[best].layer):
			best = i
	return best


func fold(fs: Array, g: Vector3, t: Vector3) -> Dictionary:
	var gi := facet_at(fs, g)
	if gi < 0:
		return {"ok": false, "reason": "no paper at %s" % g}
	return PaperModel.plan_fold(fs, gi, g, PaperModel.snap_target(fs, gi, g, t), Vector3.UP)


func dry(fs: Array, pose: Transform3D) -> float:
	var h := Hull.build(fs, PaperModel.stack_offsets(fs))
	return h.dry(pose, 0.0).volume


func _initialize() -> void:
	var fs := PaperModel.make_sheet(Vector2(8, 8))
	var low := Transform3D(Basis(), Vector3(0, -0.5, 0)) # floor half a metre under the waterline
	check(dry(fs, low) < 0.01, "a flat sheet holds no water (%.2f m3)" % dry(fs, low))

	var r := fold(fs, Vector3(0, T, -4), Vector3(0, 1.5, -2.5))
	check(r.ok, "one side up (%s)" % r.reason)
	fs = r.facets
	r = fold(fs, Vector3(0, T, 4), Vector3(0, 1.5, 2.5))
	check(r.ok, "the other side up: a trough (%s)" % r.reason)
	fs = r.facets
	check(dry(fs, low) < 0.01, "a trough, open at the ends, holds no water (%.2f m3)" % dry(fs, low))
	var trough := fs

	r = fold(fs, Vector3(4, T, 0), Vector3(2.5, 1.5, 0))
	check(r.ok, "one end up, its corners tucked into gussets (%s)" % r.reason)
	if not r.ok:
		quit(1)
		return
	fs = r.facets
	check(fs.size() == 8, "the end and two gusset ears per corner make 8 facets (%d)" % fs.size())
	r = fold(fs, Vector3(-4, T, 0), Vector3(-2.5, 1.5, 0))
	check(r.ok, "the other end up: a tray (%s)" % r.reason)
	if not r.ok:
		quit(1)
		return
	fs = r.facets
	check(fs.size() == 13, "13 facets: floor, 4 sides, 8 gusset triangles (%d)" % fs.size())
	var upright := 0
	var ears := 0
	for f in fs:
		var c: Vector3 = f.at(PaperGeometry.centroid(f.pts))
		if absf(f.normal().y) < 0.02:
			upright += 1
			if absf(c.x) > 2.55 or absf(c.z) > 2.55:
				ears += 1
	check(upright == 12 and ears == 8, "4 upright sides and 8 upright ear triangles outside the corners (%d upright, %d ears)" % [upright, ears])
	var top := 0.0
	for f in fs:
		for q in f.pts:
			top = maxf(top, f.at(q).y)
	check(absf(top - 1.5) < 0.05, "its rim is 1.5 m up (%.2f)" % top)

	var v := dry(fs, low)
	check(v > 6.0 and v < 16.0, "the tray holds water out: %.1f m3 dry under the waterline (5 x 5 x 0.5 = 12.5, less the voxels the paper fills)" % v)
	var deep := Transform3D(Basis(), Vector3(0, -1.0, 0))
	check(dry(fs, deep) > v * 1.5, "deeper, more of it is under the waterline (%.1f m3)" % dry(fs, deep))
	var swamped := Transform3D(Basis(), Vector3(0, -1.7, 0))
	check(dry(fs, swamped) < 0.01, "with the rim under, it's full of water (%.2f m3)" % dry(fs, swamped))
	var tipped := Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(40.0)), Vector3(0, -0.6, 0))
	check(dry(fs, tipped) < v * 0.7, "tipped 40 degrees, water spills in over the low rim (%.1f m3)" % dry(fs, tipped))
	check(dry(trough, deep) < 0.01, "(and the trough is still no boat: %.2f m3)" % dry(trough, deep))
	quit(0 if ok else 1)
