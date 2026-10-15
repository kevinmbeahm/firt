class_name PaperModel
extends RefCounted
## Rigid-origami model of one sheet of paper (pure logic, no nodes).
##
## The sheet is a set of flat convex facets. Each facet keeps its polygon in
## *paper space* (the unfolded sheet, metres) plus a rigid transform `xf` that
## places paper-space (x, y, 0) on its mid-surface in sheet-local 3D. Paper
## space never changes, so two facets sharing an edge there are physically
## joined by a hinge.
##
## A fold is a rotation about a crease axis by any angle (not just 180 deg),
## applied only to the paper on the grabbed side that is *connected* to the
## grabbed facet. Separate layers that happen to lie under the crease stay put,
## which is what lets you fold one wing of a paper plane, and a fold that would
## need to tear the paper is refused.

const THICKNESS := 0.03 ## rendered/collision thickness of one layer
const LAYER_GAP := 0.035 ## spacing between stacked coplanar layers
const EPS := 0.002
const TEAR_TOL := 0.03
const MIN_DRAG := 0.3
const MIN_ANGLE := deg_to_rad(4.0)
const VERTEX_SNAP := 0.6
const EDGE_SNAP := 0.35
const CREASE_SNAP := 0.15
const FLAT_SNAP := deg_to_rad(12.0)
const RIGHT_SNAP := deg_to_rad(6.0)


class Facet:
	var pts: PackedVector2Array ## convex polygon in paper space
	var xf: Transform3D ## paper (x, y, 0) -> sheet-local mid-surface
	var layer: int ## stacking order among coplanar overlapping facets

	func _init(p: PackedVector2Array, x: Transform3D, l: int) -> void:
		pts = p
		xf = x
		layer = l

	func clone() -> Facet:
		return Facet.new(pts.duplicate(), xf, layer)

	## Paper-front normal (the cream side faces this way).
	func normal() -> Vector3:
		return xf.basis.z.normalized()

	func at(p: Vector2) -> Vector3:
		return xf * Vector3(p.x, p.y, 0.0)


static func make_sheet(size: Vector2) -> Array:
	var h := size * 0.5
	var rect := PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)
	])
	# Paper x -> +X, paper y -> -Z, so the front normal (x cross y) is +Y.
	var basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	return [Facet.new(rect, Transform3D(basis, Vector3(0, THICKNESS * 0.5, 0)), 0)]


static func clone_all(src: Array) -> Array:
	var out: Array = []
	for f in src:
		out.append((f as Facet).clone())
	return out


## A fixed orientation per plane, so stacking order means the same thing for
## every facet in it regardless of which side of the paper faces up.
static func canonical(n: Vector3) -> Vector3:
	if absf(n.y) > 1e-3:
		return n if n.y > 0.0 else -n
	if absf(n.x) > 1e-3:
		return n if n.x > 0.0 else -n
	return n if n.z >= 0.0 else -n


static func _coplanar(a: Facet, b: Facet) -> bool:
	var na := a.normal()
	return absf(absf(na.dot(b.normal())) - 1.0) < 1e-4 and absf(na.dot(b.xf.origin - a.xf.origin)) < EPS


# --- Fold planning -----------------------------------------------------------

## Moves the in-plane part of a target onto nearby corners or creases of the
## grabbed facet's plane, so corner-to-corner and corner-to-crease folds are easy.
static func snap_target(src: Array, gi: int, g: Vector3, t: Vector3) -> Vector3:
	var gf: Facet = src[gi]
	var n := gf.normal()
	var h := n.dot(t - g)
	if absf(h) > 0.4:
		return t
	var tp := t - n * h
	var best := tp
	var best_d := VERTEX_SNAP
	var found := false
	for item in src:
		var f: Facet = item
		if not _coplanar(f, gf):
			continue
		for p in f.pts:
			var v := f.at(p)
			var d := v.distance_to(tp)
			if d < best_d and v.distance_to(g) > MIN_DRAG:
				best = v
				best_d = d
				found = true
	if not found:
		best_d = EDGE_SNAP
		for item in src:
			var f: Facet = item
			if not _coplanar(f, gf):
				continue
			var c := f.pts.size()
			for i in c:
				var a := f.at(f.pts[i])
				var b := f.at(f.pts[(i + 1) % c])
				var q := Geometry3D.get_closest_point_to_segment(tp, a, b)
				var d := q.distance_to(tp)
				if d < best_d and q.distance_to(g) > MIN_DRAG:
					best = q
					best_d = d
	return best + n * h


## Plans folding facet `gi` so its point `g` (sheet-local, on the facet) moves to
## `t`. The crease is where the paper must bend for g to land exactly on t: the
## line where the grabbed facet's plane meets the perpendicular bisector of g-t.
## Returns {ok, reason, facets, axis_a, axis_d, plane_n}.
static func plan_fold(src: Array, gi: int, g: Vector3, t: Vector3, up: Vector3) -> Dictionary:
	var res := {"ok": false, "reason": "", "facets": [], "axis_a": g, "axis_d": Vector3.ZERO, "plane_n": Vector3.UP}
	var gf: Facet = src[gi]
	var n := gf.normal()
	res.plane_n = n
	var dv := t - g
	if dv.length() < MIN_DRAG:
		res.reason = "drag further"
		return res
	var u := dv.normalized()
	var axis := n.cross(u)
	if axis.length() < 0.05:
		res.reason = "pull sideways, not straight out"
		return res
	axis = axis.normalized()
	var w := (u - n * n.dot(u)).normalized()
	var a := g + w * (u.dot((g + t) * 0.5 - g) / u.dot(w))
	# Re-folding along an existing crease (opening a wing, unfolding) should use
	# that exact crease rather than shaving off slivers next to it.
	var crease = _existing_crease(src, gf, a, axis)
	if crease != null:
		a = crease[0]
		axis = crease[1]
	res.axis_a = a
	res.axis_d = axis
	var cut_n := n.cross(axis).normalized() # in the grabbed plane, across the crease
	var g_side := cut_n.dot(g - a)
	if absf(g_side) < EPS:
		res.reason = "drag further"
		return res
	var moving_sign := signf(g_side)

	var foot := a + axis * axis.dot(g - a)
	var vg := g - foot
	var vt := t - foot
	var theta := atan2(axis.dot(vg.cross(vt)), vg.dot(vt))
	theta = _snap_angle(theta, axis, vg, up)
	if absf(theta) < MIN_ANGLE:
		res.reason = "lift or drag to fold"
		return res

	# Split every facet whose plane contains the crease; others go whole.
	var pieces: Array = [] # {f: Facet, side: float, src: int}
	for i in src.size():
		var f: Facet = src[i]
		var nf := f.normal()
		var a2 := Vector2(f.xf.basis.x.dot(cut_n), f.xf.basis.y.dot(cut_n))
		var b := cut_n.dot(f.xf.origin - a)
		var holds_axis := absf(nf.dot(axis)) < 1e-3 and absf(nf.dot(a - f.xf.origin)) < EPS
		if holds_axis and a2.length() > 1e-4:
			var o2 := -b * a2 / a2.length_squared()
			for s in [1.0, -1.0]:
				var part := PaperGeometry.clip_half_plane(f.pts, o2, a2, s > 0.0)
				if part.size() >= 3:
					pieces.append({"f": Facet.new(part, f.xf, f.layer), "side": s, "src": i})
		else:
			var c := f.at(PaperGeometry.centroid(f.pts))
			pieces.append({"f": f.clone(), "side": signf(cut_n.dot(c - a)), "src": i})

	# Grow the moving set from the grabbed piece through paper-space hinges.
	var start := -1
	for i in pieces.size():
		if pieces[i].src == gi and pieces[i].side == moving_sign:
			start = i
	if start < 0:
		res.reason = "drag further"
		return res
	var moving := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for j in pieces.size():
			if moving.has(j) or pieces[j].side != moving_sign:
				continue
			var seg := shared_edge(pieces[cur].f.pts, pieces[j].f.pts)
			if seg.is_empty():
				continue
			# A hinge lying on the crease is what we rotate about: a flap already
			# folded back over it stays behind rather than coming along.
			var cf: Facet = pieces[cur].f
			if _line_dist(cf.at(seg[0]), a, axis) < TEAR_TOL and _line_dist(cf.at(seg[1]), a, axis) < TEAR_TOL:
				continue
			moving[j] = true
			queue.append(j)
	if moving.size() == pieces.size():
		res.reason = "the crease misses the paper"
		return res

	# Every hinge between moving and resting paper must lie on the crease.
	for i in moving:
		var mf: Facet = pieces[i].f
		for j in pieces.size():
			if moving.has(j):
				continue
			var seg := shared_edge(mf.pts, pieces[j].f.pts)
			for p in seg:
				var off := mf.at(p) - a
				if (off - axis * off.dot(axis)).length() > TEAR_TOL:
					res.reason = "would tear the paper"
					return res

	# Rotate the moving paper and give it a stacking order.
	var rot := Basis(axis, theta)
	var spin := Transform3D(rot, a - rot * a)
	var top := -1000000
	var bottom := 1000000
	var mtop := -1000000
	var mbottom := 1000000
	for i in pieces.size():
		var l: int = pieces[i].f.layer
		top = maxi(top, l)
		bottom = mini(bottom, l)
		if moving.has(i):
			mtop = maxi(mtop, l)
			mbottom = mini(mbottom, l)
	var cn := canonical(n)
	var lands_above := cn.dot(Basis(axis, theta * 0.5) * vg) >= 0.0
	var reversed := (rot * cn).dot(canonical(rot * cn)) < 0.0
	var out: Array = []
	for i in pieces.size():
		var f: Facet = pieces[i].f
		if moving.has(i):
			var rank := (mtop - f.layer) if reversed else (f.layer - mbottom)
			var l := (top + 1 + rank) if lands_above else (bottom - 1 - (mtop - mbottom) + rank)
			out.append(Facet.new(f.pts, spin * f.xf, l))
		else:
			out.append(f)
	out.sort_custom(func(x: Facet, y: Facet) -> bool: return x.layer < y.layer)
	for i in out.size():
		(out[i] as Facet).layer = i
		(out[i] as Facet).xf = (out[i] as Facet).xf.orthonormalized()
	res.ok = true
	res.facets = out
	return res


## An edge in the grabbed plane lying almost on the proposed crease, as
## [point, direction], or null.
static func _existing_crease(src: Array, gf: Facet, a: Vector3, axis: Vector3):
	var best = null
	var best_d := CREASE_SNAP
	for item in src:
		var f: Facet = item
		if not _coplanar(f, gf):
			continue
		var c := f.pts.size()
		for i in c:
			var p := f.at(f.pts[i])
			var q := f.at(f.pts[(i + 1) % c])
			var e := q - p
			if e.length() < 0.05:
				continue
			e = e.normalized()
			if absf(e.dot(axis)) < cos(deg_to_rad(3.0)):
				continue
			var d := maxf(_line_dist(p, a, axis), _line_dist(q, a, axis))
			if d < best_d:
				best_d = d
				best = [p, e if e.dot(axis) > 0.0 else -e]
	return best


static func _line_dist(p: Vector3, a: Vector3, d: Vector3) -> float:
	var off := p - a
	return (off - d * off.dot(d)).length()


static func _snap_angle(theta: float, axis: Vector3, vg: Vector3, up: Vector3) -> float:
	if absf(absf(theta) - PI) < FLAT_SNAP:
		if absf(absf(theta) - PI) < deg_to_rad(0.5):
			# Dead flat target: go over the top rather than through the floor.
			var over := (Basis(axis, PI * 0.5) * vg).dot(up)
			return PI if over >= 0.0 else -PI
		return PI * signf(theta)
	if absf(absf(theta) - PI * 0.5) < RIGHT_SNAP:
		return PI * 0.5 * signf(theta)
	return theta


## The segment two convex paper-space polygons share, or empty.
static func shared_edge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	for i in a.size():
		var p0 := a[i]
		var p1 := a[(i + 1) % a.size()]
		var length := p0.distance_to(p1)
		if length < 1e-4:
			continue
		var dir := (p1 - p0) / length
		var nrm := Vector2(-dir.y, dir.x)
		for j in b.size():
			var q0 := b[j]
			var q1 := b[(j + 1) % b.size()]
			if absf((q0 - p0).dot(nrm)) > 1e-3 or absf((q1 - p0).dot(nrm)) > 1e-3:
				continue
			var t0 := (q0 - p0).dot(dir)
			var t1 := (q1 - p0).dot(dir)
			var lo := maxf(0.0, minf(t0, t1))
			var hi := minf(length, maxf(t0, t1))
			if hi - lo > 1e-3:
				return PackedVector2Array([p0 + dir * lo, p0 + dir * hi])
	return PackedVector2Array()


# --- Stacking & handles ------------------------------------------------------

## Per-facet offsets that lift overlapping coplanar layers apart by LAYER_GAP,
## in stacking order, so thin paper never z-fights or interpenetrates.
static func stack_offsets(list: Array) -> Array:
	var offsets: Array = []
	offsets.resize(list.size())
	var elev: Array = []
	elev.resize(list.size())
	var order := range(list.size())
	order.sort_custom(func(i: int, j: int) -> bool: return list[i].layer < list[j].layer)
	var projected := {}
	for idx in order.size():
		var i: int = order[idx]
		var f: Facet = list[i]
		var cn := canonical(f.normal())
		var e := 0
		for jdx in idx:
			var j: int = order[jdx]
			var other: Facet = list[j]
			if not _coplanar(f, other):
				continue
			if PaperGeometry.overlap_area(_project(f, cn, projected, i), _project(other, cn, projected, j)) > 0.01:
				e = maxi(e, elev[j] + 1)
		elev[i] = e
		offsets[i] = cn * (e * LAYER_GAP)
	return offsets


static func _project(f: Facet, cn: Vector3, cache: Dictionary, key: int) -> PackedVector2Array:
	var k := "%d:%s" % [key, cn]
	if cache.has(k):
		return cache[k]
	var u := cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := cn.cross(u)
	var out := PackedVector2Array()
	for p in f.pts:
		var q := f.at(p)
		out.append(Vector2(q.dot(u), q.dot(v)))
	cache[k] = out
	return out


## Grabbable corners and edge midpoints, one per spot (the layer nearest `up`
## wins). Returns Array of {local: Vector3 (mid-surface), shown: Vector3, facet: int}.
static func handles(list: Array, offsets: Array, up: Vector3) -> Array:
	var out: Array = []
	for i in list.size():
		var f: Facet = list[i]
		var c := f.pts.size()
		for k in c:
			for p in [f.pts[k], (f.pts[k] + f.pts[(k + 1) % c]) * 0.5]:
				var local := f.at(p)
				var shown: Vector3 = local + offsets[i]
				var merged := false
				for h in out:
					if (h.shown as Vector3).distance_to(shown) < 0.25:
						merged = true
						if shown.dot(up) > (h.shown as Vector3).dot(up):
							h.local = local
							h.shown = shown
							h.facet = i
						break
				if not merged:
					out.append({"local": local, "shown": shown, "facet": i})
	return out
