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

## Fold kinds. A reverse fold works on a folded edge (layers joined at a spine):
## both sides of the tip swing about the same crease in opposite directions,
## tucking it between the layers (inside) or wrapping it round them (outside).
enum { FOLD_NORMAL, FOLD_INSIDE_REVERSE, FOLD_OUTSIDE_REVERSE }
const FOLD_NAMES := ["fold", "inside reverse fold", "outside reverse fold"]


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
## Reverse folds are always flat, so they only use t's in-plane position.
## Returns {ok, reason, facets, axis_a, axis_d, plane_n, theta, moved, swept}:
## `moved` lists the facets (in `facets`) that rotated, and `swept` says they got
## there by turning `theta` about the crease (normal folds), so the caller can
## test that path against the world.
## `theta_override` (normal folds only) keeps the crease but uses that angle
## instead of the one the hands ask for, e.g. to stop a flap against the ground.
static func plan_fold(src: Array, gi: int, g: Vector3, t: Vector3, up: Vector3, mode: int = FOLD_NORMAL,
		theta_override: float = NAN) -> Dictionary:
	var res := {"ok": false, "reason": "", "facets": [], "axis_a": g, "axis_d": Vector3.ZERO,
		"plane_n": Vector3.UP, "theta": 0.0, "moved": [], "swept": mode == FOLD_NORMAL}
	var gf: Facet = src[gi]
	var n := gf.normal()
	res.plane_n = n
	if mode != FOLD_NORMAL:
		t -= n * n.dot(t - g)
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
	# A flap folded at an existing crease swings about that crease when the
	# hands roughly follow it (unfolding, opening a wing part-way), instead of
	# needing the corner carried back to the exact spot.
	var hinge = _hinge_axis(src, gi, g, t) if mode == FOLD_NORMAL else null
	# Otherwise, a new crease that lands almost on an existing one reuses it
	# rather than shaving off slivers next to it.
	var crease = hinge if hinge != null else _existing_crease(src, gf, a, axis)
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
	if mode != FOLD_NORMAL:
		theta = PI
	elif is_nan(theta_override):
		theta = _snap_angle(theta, axis, vg, up)
	else:
		theta = theta_override
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

	# Paper-space hinges between pieces: [neighbour, shared segment].
	var adj: Array = []
	adj.resize(pieces.size())
	for i in pieces.size():
		adj[i] = []
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var seg := shared_edge(pieces[i].f.pts, pieces[j].f.pts)
			if not seg.is_empty():
				adj[i].append([j, seg])
				adj[j].append([i, seg])

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
		var cf: Facet = pieces[cur].f
		for link in adj[cur]:
			var j: int = link[0]
			if moving.has(j) or pieces[j].side != moving_sign:
				continue
			# A hinge lying on the crease is what we rotate about: a flap already
			# folded back over it stays behind rather than coming along.
			var seg: PackedVector2Array = link[1]
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
		for link in adj[i]:
			if moving.has(link[0]):
				continue
			for p in link[1]:
				if _line_dist(mf.at(p), a, axis) > TEAR_TOL:
					res.reason = "would tear the paper"
					return res

	if mode != FOLD_NORMAL:
		return _finish_reverse(res, pieces, moving, a, axis, vg, canonical(n), mode == FOLD_INSIDE_REVERSE)

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
	var moved: Array = []
	var placed := {} # piece index -> facet in `out`
	for i in pieces.size():
		var f: Facet = pieces[i].f
		if moving.has(i):
			var rank := (mtop - f.layer) if reversed else (f.layer - mbottom)
			var l := (top + 1 + rank) if lands_above else (bottom - 1 - (mtop - mbottom) + rank)
			var nf := Facet.new(f.pts, (spin * f.xf).orthonormalized(), l)
			out.append(nf)
			moved.append(nf)
			placed[i] = nf
		else:
			out.append(f)
			placed[i] = f
	# Paper can't end up passing through other paper (hinged neighbours touch
	# along their shared edge, which is fine).
	for i in moving:
		var hinged := {}
		for link in adj[i]:
			hinged[link[0]] = true
		for j in pieces.size():
			if moving.has(j) or hinged.has(j):
				continue
			var m: Facet = placed[i]
			var st: Facet = placed[j]
			if not _coplanar(m, st) and (_crosses(m, st) or _crosses(st, m)):
				res.reason = "would pass through other paper"
				return res
	out.sort_custom(func(x: Facet, y: Facet) -> bool: return x.layer < y.layer)
	for i in out.size():
		(out[i] as Facet).layer = i
	res.ok = true
	res.facets = out
	res.moved = moved
	res.theta = theta
	return res


## True when non-coplanar facets `a` and `b` cut through each other: the line
## where `a` crosses b's plane runs through the inside of `b`.
static func _crosses(a: Facet, b: Facet) -> bool:
	var nb := b.normal()
	var ob := b.xf.origin
	var hits: Array = []
	var c := a.pts.size()
	for i in c:
		var p := a.at(a.pts[i])
		var q := a.at(a.pts[(i + 1) % c])
		var dp := nb.dot(p - ob)
		var dq := nb.dot(q - ob)
		if absf(dp) < 1e-4:
			hits.append(p)
		elif dp * dq < 0.0 and absf(dq) >= 1e-4:
			hits.append(p + (q - p) * (dp / (dp - dq)))
	if hits.size() < 2:
		return false
	# The two hits furthest apart bound a's slice through b's plane.
	var p0: Vector3 = hits[0]
	var p1: Vector3 = hits[1]
	for h in hits:
		if (h as Vector3).distance_to(p0) > p1.distance_to(p0):
			p1 = h
	var inv := b.xf.affine_inverse()
	var s0: Vector3 = inv * p0
	var s1: Vector3 = inv * p1
	return _segment_inside(Vector2(s0.x, s0.y), Vector2(s1.x, s1.y), PaperGeometry.inset(b.pts, 0.01)) > 0.02


## Length of the part of segment p-q inside a convex polygon (Cyrus-Beck).
static func _segment_inside(p: Vector2, q: Vector2, poly: PackedVector2Array) -> float:
	var cen := PaperGeometry.centroid(poly)
	var t0 := 0.0
	var t1 := 1.0
	var d := q - p
	for i in poly.size():
		var e0 := poly[i]
		var e1 := poly[(i + 1) % poly.size()]
		var n := Vector2(-(e1 - e0).y, (e1 - e0).x)
		if n.dot(cen - e0) < 0.0:
			n = -n
		var num := n.dot(p - e0)
		var den := n.dot(d)
		if absf(den) < 1e-9:
			if num < 0.0:
				return 0.0
			continue
		var t := -num / den
		if den > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 >= t1:
			return 0.0
	return (t1 - t0) * d.length()


## The folded hinge of the grabbed facet that best carries g toward t, as
## [point, direction], or null if no hinge comes close. Only creases that are
## actually folded (the neighbour isn't lying flat beside us) count.
static func _hinge_axis(src: Array, gi: int, g: Vector3, t: Vector3):
	var gf: Facet = src[gi]
	var n := gf.normal()
	var c := gf.pts.size()
	var best = null
	var best_score := INF
	for i in c:
		var e0 := gf.pts[i]
		var e1 := gf.pts[(i + 1) % c]
		# How folded is this edge? Folded flat (the flap lies back on its
		# neighbour) is the classic unfold, so the hands may be sloppier there.
		var dihedral := 1.0
		for j in src.size():
			if j == gi:
				continue
			var other: Facet = src[j]
			if not shared_edge(PackedVector2Array([e0, e1]), other.pts).is_empty():
				dihedral = minf(dihedral, other.normal().dot(n))
		if dihedral > 0.999:
			continue # a flat, unfolded crease: nothing to swing about
		var tolerance := 0.5 if dihedral < -0.999 else 0.25
		var p := gf.at(e0)
		var d := (gf.at(e1) - p).normalized()
		var foot := p + d * d.dot(g - p)
		var vg := g - foot
		if vg.length() < 0.1:
			continue # we're holding the hinge itself
		var vt := t - foot
		vt -= d * d.dot(vt)
		var theta := atan2(d.dot(vg.cross(vt)), vg.dot(vt))
		var swung := foot + Basis(d, theta) * vg
		# The swing must account for most of where the hands went (a short pull
		# along the flap is a new fold, not a hinge turn)...
		if swung.distance_to(g) < 0.5 * t.distance_to(g):
			continue
		# ...and land close to them, relative to the flap's size.
		var score := swung.distance_to(t) / vg.length()
		if score < tolerance and score < best_score:
			best_score = score
			best = [p, d]
	return best


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


## Reverse folds: split the moving paper into its two sides (pieces joined only
## through 180-degree folds such as the spine), then swing the upper side and
## the lower side about the crease in opposite directions.
static func _finish_reverse(res: Dictionary, pieces: Array, moving: Dictionary, a: Vector3,
		axis: Vector3, vg: Vector3, cn: Vector3, inside: bool) -> Dictionary:
	# Components of the moving paper that don't cross a flat-folded hinge.
	var comp := {}
	var comps: Array = []
	for i in moving:
		if comp.has(i):
			continue
		var members: Array = [i]
		comp[i] = comps.size()
		var queue: Array = [i]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			var cf: Facet = pieces[cur].f
			for j in moving:
				if comp.has(j):
					continue
				var jf: Facet = pieces[j].f
				if cf.normal().dot(jf.normal()) < -0.99:
					continue
				if not shared_edge(cf.pts, jf.pts).is_empty():
					comp[j] = comps.size()
					members.append(j)
					queue.append(j)
		comps.append(members)
	if comps.size() < 2:
		res.reason = "reverse folds need a folded edge (two joined layers)"
		return res

	# Upper side = components stacked above the middle of the moving paper.
	var means: Array = []
	for members in comps:
		var total := 0.0
		for i in members:
			total += pieces[i].f.layer
		means.append(total / members.size())
	var mid: float = (means.min() + means.max()) * 0.5
	var upper := {}
	var lower := {}
	for c in comps.size():
		for i in comps[c]:
			if means[c] > mid:
				upper[i] = true
			else:
				lower[i] = true
	if upper.is_empty() or lower.is_empty():
		res.reason = "reverse folds need a folded edge (two joined layers)"
		return res

	var top := -1000000
	var bottom := 1000000
	for p in pieces:
		top = maxi(top, p.f.layer)
		bottom = mini(bottom, p.f.layer)
	var umin := 1000000
	var umax := -1000000
	var lmin := 1000000
	var lmax := -1000000
	for i in upper:
		umin = mini(umin, pieces[i].f.layer)
		umax = maxi(umax, pieces[i].f.layer)
	for i in lower:
		lmin = mini(lmin, pieces[i].f.layer)
		lmax = maxi(lmax, pieces[i].f.layer)

	# Inside: upper side swings down and lower side up, both landing between
	# the layers. Outside: upper over the top, lower round the bottom.
	var spin_up := _flat_spin(a, axis, vg, cn, 1.0)
	var spin_down := _flat_spin(a, axis, vg, cn, -1.0)
	var keyed: Array = []
	var moved: Array = []
	for i in pieces.size():
		var f: Facet = pieces[i].f
		var key := float(f.layer)
		var xf := f.xf
		if upper.has(i):
			xf = (spin_down if inside else spin_up) * f.xf
			if inside:
				key = umin - 0.05 - 0.4 * (f.layer - umin) / (umax - umin + 1.0)
			else:
				key = top + 0.05 + 0.4 * (umax - f.layer) / (umax - umin + 1.0)
		elif lower.has(i):
			xf = (spin_up if inside else spin_down) * f.xf
			if inside:
				key = lmax + 0.05 + 0.4 * (lmax - f.layer) / (lmax - lmin + 1.0)
			else:
				key = bottom - 0.05 - 0.4 * (f.layer - lmin) / (lmax - lmin + 1.0)
		var nf := Facet.new(f.pts, xf, 0)
		keyed.append([key, nf])
		if moving.has(i):
			moved.append(nf)
	keyed.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array = []
	for i in keyed.size():
		var f: Facet = keyed[i][1]
		f.layer = i
		f.xf = f.xf.orthonormalized()
		out.append(f)
	res.ok = true
	res.facets = out
	res.moved = moved
	res.theta = PI
	return res


## A half turn about the crease that passes through the `side` (+1 = the
## canonical-normal side) of the paper on its way over.
static func _flat_spin(a: Vector3, axis: Vector3, vg: Vector3, cn: Vector3, side: float) -> Transform3D:
	var s := 1.0 if cn.dot(Basis(axis, PI * 0.5) * vg) * side > 0.0 else -1.0
	var rot := Basis(axis, s * PI)
	return Transform3D(rot, a - rot * a)


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
	var count := list.size()
	var offsets: Array = []
	offsets.resize(count)
	var elev: Array = []
	elev.resize(count)
	var order := range(count)
	order.sort_custom(func(i: int, j: int) -> bool: return list[i].layer < list[j].layer)
	# Each facet projected into its plane's 2D frame, plus a bounding box for
	# cheap rejection before the exact polygon overlap.
	var flat: Array = []
	var boxes: Array = []
	var normals: Array = []
	for i in count:
		var f: Facet = list[i]
		var cn := canonical(f.normal())
		var u := cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := cn.cross(u)
		var poly := PackedVector2Array()
		var box := Rect2()
		for k in f.pts.size():
			var q := f.at(f.pts[k])
			var p2 := Vector2(q.dot(u), q.dot(v))
			poly.append(p2)
			box = Rect2(p2, Vector2.ZERO) if k == 0 else box.expand(p2)
		flat.append(poly)
		boxes.append(box)
		normals.append(cn)
	for idx in count:
		var i: int = order[idx]
		var f: Facet = list[i]
		var e := 0
		for jdx in idx:
			var j: int = order[jdx]
			if elev[j] + 1 <= e or not _coplanar(f, list[j]):
				continue
			if not (boxes[i] as Rect2).grow(-0.01).intersects(boxes[j]):
				continue
			if PaperGeometry.overlap_area(flat[i], flat[j]) > 0.01:
				e = elev[j] + 1
		elev[i] = e
		offsets[i] = normals[i] * (e * LAYER_GAP)
	return offsets


## Grabbable corners and edge midpoints, one per spot (the layer nearest `up`
## wins). Points buried under a layer stacked above them (as seen from `up`)
## can't be grabbed: you'd have to pull them out through the paper on top.
## Returns Array of {local: Vector3 (mid-surface), shown: Vector3, facet: int}.
static func handles(list: Array, offsets: Array, up: Vector3) -> Array:
	var inverse: Array = []
	var inner: Array = []
	for f in list:
		inverse.append((f as Facet).xf.affine_inverse())
		inner.append(PaperGeometry.inset((f as Facet).pts, 0.05))
	var out: Array = []
	for i in list.size():
		var f: Facet = list[i]
		var c := f.pts.size()
		for k in c:
			for p in [f.pts[k], (f.pts[k] + f.pts[(k + 1) % c]) * 0.5]:
				var local := f.at(p)
				var shown: Vector3 = local + offsets[i]
				if _buried(list, offsets, inverse, inner, i, local, up):
					continue
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


static func _buried(list: Array, offsets: Array, inverse: Array, inner: Array, i: int, point: Vector3, up: Vector3) -> bool:
	var f: Facet = list[i]
	for j in list.size():
		if j == i or (offsets[j] - offsets[i]).dot(up) <= 1e-4:
			continue # not stacked above us
		if not _coplanar(f, list[j]):
			continue
		var q: Vector3 = inverse[j] * point
		if Geometry2D.is_point_in_polygon(Vector2(q.x, q.y), inner[j]):
			return true
	return false
