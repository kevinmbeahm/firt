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
const TEAR_TOL := 0.005
const MIN_DRAG := 0.3
const MIN_ANGLE := deg_to_rad(4.0)
const VERTEX_SNAP := 0.6
const EDGE_SNAP := 0.35
const CREASE_SNAP := 0.15
const MEMORY_SNAP := 0.25 ## a new crease this close to a remembered or printed one folds along it...
const MEMORY_SNAP_SHARE := 0.2 ## ...or this share of the flap's size, if that's more
const SLIVER_AREA := 0.001 ## square metres: a crease shaving off less than this from a facet just misses it
const VERTEX_AXIS_SNAP := 0.12 ## a crease passing this close to a paper corner goes through it
const FLAT_SNAP := deg_to_rad(12.0)
const RIGHT_SNAP := deg_to_rad(10.0)

## Fold kinds. A reverse fold works on a folded edge (layers joined at a spine):
## both sides of the tip swing about the same crease in opposite directions,
## tucking it between the layers (inside) or wrapping it round them (outside).
## A collapse refolds several existing creases at once (squash folds, petal
## folds, collapsing a precreased square into a base, rabbit ears...).
enum { FOLD_NORMAL, FOLD_INSIDE_REVERSE, FOLD_OUTSIDE_REVERSE, FOLD_COLLAPSE }
const FOLD_NAMES := ["fold", "inside reverse fold", "outside reverse fold", "collapse (squash / petal)"]


class Facet:
	var pts: PackedVector2Array ## convex polygon in paper space
	var xf: Transform3D ## paper (x, y, 0) -> sheet-local mid-surface
	var layer: int ## stacking order among coplanar overlapping facets
	## Crease memory for this facet's edges: paper line key -> +1 valley / -1
	## mountain (as seen from the paper's front), from the last time it folded.
	var creases: Dictionary

	func _init(p: PackedVector2Array, x: Transform3D, l: int, c: Dictionary = {}) -> void:
		pts = p
		xf = x
		layer = l
		creases = c

	func clone() -> Facet:
		return Facet.new(pts.duplicate(), xf, layer, creases.duplicate())

	## Paper-front normal (the cream side faces this way).
	func normal() -> Vector3:
		return xf.basis.z.normalized()

	func at(p: Vector2) -> Vector3:
		return xf * Vector3(p.x, p.y, 0.0)


## A flat sheet. `printed` crease lines ({a, b, mv}) start out in its crease
## memory, as if folded that way before.
static func make_sheet(size: Vector2, printed: Array = []) -> Array:
	var h := size * 0.5
	var rect := PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)
	])
	var memory := {}
	for c in printed:
		memory[line_key(PackedVector2Array([c.a, c.b]))] = int(c.get("mv", 1))
	# Paper x -> +X, paper y -> -Z, so the front normal (x cross y) is +Y.
	var basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	return [Facet.new(rect, Transform3D(basis, Vector3(0, THICKNESS * 0.5, 0)), 0, memory)]


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
	if mode == FOLD_COLLAPSE:
		return plan_collapse(src, gi, g, t, up)
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
	if crease == null:
		crease = _remembered_crease(src, gf, a, axis, g)
	if crease == null:
		crease = _through_vertices(src, gf, a, axis)
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
			var kept := false
			for s in [1.0, -1.0]:
				var part := PaperGeometry.clip_half_plane(f.pts, o2, a2, s > 0.0, SLIVER_AREA)
				if part.size() >= 3:
					pieces.append({"f": Facet.new(part, f.xf, f.layer, f.creases.duplicate()), "side": s, "src": i})
					kept = true
			if not kept:
				# A facet too small to cut into pieces worth keeping stays whole
				# (paper never just disappears), on the side most of it is on.
				var side := 1.0 if (PaperGeometry.centroid(f.pts) - o2).dot(a2) >= 0.0 else -1.0
				pieces.append({"f": Facet.new(PaperGeometry.tidy(f.pts), f.xf, f.layer, f.creases.duplicate()), "side": side, "src": i})
		else:
			var c := f.at(PaperGeometry.centroid(f.pts))
			pieces.append({"f": f.clone(), "side": signf(cut_n.dot(c - a)), "src": i})

	# Paper-space hinges between pieces: [neighbour, shared segment].
	var adj := _adjacency(pieces)

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
	_enclose_trapped(pieces, adj, moving, moving_sign, a, axis)
	if moving.size() == pieces.size():
		res.reason = "the crease misses the paper"
		return res

	# Every hinge between moving and resting paper must lie on the crease,
	# except where the flap meets paper standing up at a corner: lifting the
	# end of a tray up between its standing sides tucks each corner into a
	# gusset (an ear folded on the corner's diagonal), as with a real box.
	var gussets := {} # piece index -> where it goes (paper -> sheet-local)
	var tears := _tears(pieces, adj, moving, a, axis)
	if not tears.is_empty():
		if mode != FOLD_NORMAL or not _gusset(pieces, tears, moving, a, axis, theta, gussets):
			res.reason = "would tear the paper"
			return res
		adj = _adjacency(pieces)
		res.swept = false # (gussets don't just swing about the crease: check where it ends up)

	if mode != FOLD_NORMAL:
		return _finish_reverse(res, pieces, adj, moving, a, axis, vg, canonical(n), mode == FOLD_INSIDE_REVERSE)

	# The flap has to lift off whatever it lies against: paper that stays put and
	# lies on top of it (on the side it swings toward) holds it down.
	var cn := canonical(n)
	var lands_above := cn.dot(Basis(axis, theta * 0.5) * vg) >= 0.0
	for i in moving:
		var mf: Facet = pieces[i].f
		for j in pieces.size():
			if moving.has(j):
				continue
			var sf: Facet = pieces[j].f
			if (sf.layer > mf.layer) != lands_above or not _coplanar(mf, sf) or not _overlaps(mf, sf):
				continue
			res.reason = "other paper is lying on it"
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
	var reversed := (rot * cn).dot(canonical(rot * cn)) < 0.0
	var out: Array = []
	var moved: Array = []
	var placed := {} # piece index -> facet in `out`
	for i in pieces.size():
		var f: Facet = pieces[i].f
		if gussets.has(i):
			var gf2 := Facet.new(f.pts, (gussets[i] as Transform3D).orthonormalized(), f.layer, f.creases.duplicate())
			out.append(gf2)
			moved.append(gf2)
			placed[i] = gf2
		elif moving.has(i):
			var rank := (mtop - f.layer) if reversed else (f.layer - mbottom)
			var l := (top + 1 + rank) if lands_above else (bottom - 1 - (mtop - mbottom) + rank)
			var nf := Facet.new(f.pts, (spin * f.xf).orthonormalized(), l, f.creases.duplicate())
			out.append(nf)
			moved.append(nf)
			placed[i] = nf
		else:
			out.append(f)
			placed[i] = f
	# Paper can't end up passing through other paper (hinged neighbours touch
	# along their shared edge, which is fine).
	for i in moving.keys() + gussets.keys():
		var hinged := {}
		for link in adj[i]:
			hinged[link[0]] = true
		for j in pieces.size():
			if moving.has(j) or gussets.has(j) or hinged.has(j):
				continue
			var m: Facet = placed[i]
			var st: Facet = placed[j]
			if not _coplanar(m, st) and (_crosses(m, st) or _crosses(st, m)):
				res.reason = "would pass through other paper"
				return res
	# A flat fold has to stack physically with everything it lands on: let the
	# layer solver place it (paper that moved together keeps its order, the flap
	# goes over or under as the hands took it).
	if absf(absf(theta) - PI) < 1e-3:
		var known := {}
		var prefer := {}
		var simple: Array = []
		for f in out:
			simple.append(f.layer)
		for i in out.size():
			for j in range(i + 1, out.size()):
				if not _coplanar(out[i], out[j]):
					continue
				var key := "%d,%d" % [i, j]
				prefer[key] = simple[i] < simple[j]
				if moving.has(i) == moving.has(j):
					var before: bool = pieces[i].f.layer < pieces[j].f.layer
					known[key] = before != (moving.has(i) and reversed)
		for i in moving:
			for link in adj[i]:
				var j: int = link[0]
				if moving.has(j):
					continue
				var lo := mini(i, j)
				var hi := maxi(i, j)
				known["%d,%d" % [lo, hi]] = (lo == j) == lands_above # flap over: stationary below
		var ranks := PaperLayers.solve(out, known, prefer, simple)
		if ranks.is_empty():
			res.reason = "other paper is in the way"
			return res
		for i in out.size():
			out[i].layer = ranks[i]
	out.sort_custom(func(x: Facet, y: Facet) -> bool: return x.layer < y.layer)
	for i in out.size():
		(out[i] as Facet).layer = i
	res.ok = true
	res.facets = out
	res.moved = moved
	res.theta = theta
	res.above = lands_above
	return res


static func _adjacency(pieces: Array) -> Array:
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
	return adj


## Hinges between moving and resting paper that don't lie on the crease:
## [[moving piece, resting piece, shared segment], ...].
static func _tears(pieces: Array, adj: Array, moving: Dictionary, a: Vector3, axis: Vector3) -> Array:
	var out := []
	for i in moving:
		var mf: Facet = pieces[i].f
		for link in adj[i]:
			if moving.has(link[0]):
				continue
			for p in link[1]:
				if _line_dist(mf.at(p), a, axis) > TEAR_TOL:
					out.append([i, link[0], link[1]])
					break
	return out


## Tries to turn each tear into a gusset: the moving flap (an end of a tray)
## is hinged to resting paper standing at an angle (a side), along an edge
## running out from the crease. The crease line carries on into the side
## (paper space is one flat sheet), and the corner of the side between that
## line and the hinge folds on its diagonal: one triangle stays hinged to the
## side, the other to the flap, and they fold together like the ear of a box
## corner, outside the box. Splits the side into pieces (appended to
## `pieces`) and fills `out` with where each triangle goes. False if any tear
## isn't a corner like that.
static func _gusset(pieces: Array, tears: Array, moving: Dictionary, a: Vector3, axis: Vector3, theta: float, out: Dictionary) -> bool:
	var seen := {}
	for t in tears:
		if seen.has(t[1]):
			return false # (one corner per resting piece)
		seen[t[1]] = true
	var rot := Basis(axis, theta)
	for t in tears:
		var mf: Facet = pieces[t[0]].f
		var j: int = t[1]
		var sf: Facet = pieces[j].f
		var seg: PackedVector2Array = t[2]
		if _coplanar(mf, sf) or absf(mf.normal().dot(sf.normal())) > 0.98:
			return false
		var on0 := _line_dist(sf.at(seg[0]), a, axis) < TEAR_TOL
		var on1 := _line_dist(sf.at(seg[1]), a, axis) < TEAR_TOL
		if on0 == on1:
			return false
		var vp: Vector2 = seg[0] if on0 else seg[1]
		var e2: Vector2 = ((seg[1] if on0 else seg[0]) - vp).normalized()
		# The crease's direction in paper space, pointing into the side.
		var e4 := Vector2(mf.xf.basis.x.dot(axis), mf.xf.basis.y.dot(axis)).normalized()
		if not Geometry2D.is_point_in_polygon(vp + e4 * 0.05 + e2 * 0.01, sf.pts):
			e4 = -e4
			if not Geometry2D.is_point_in_polygon(vp + e4 * 0.05 + e2 * 0.01, sf.pts):
				return false
		if e4.dot(e2) < -0.9:
			return false
		var c5 := (e4 + e2).normalized()
		var n4 := Vector2(-e4.y, e4.x)
		var n5 := Vector2(-c5.y, c5.x)
		var s2 := n4.dot(e2) > 0.0
		var main := PaperGeometry.clip_half_plane(sf.pts, vp, n4, not s2, SLIVER_AREA)
		var corner := PaperGeometry.clip_half_plane(sf.pts, vp, n4, s2, SLIVER_AREA)
		var s5 := n5.dot(e2) > 0.0
		var t2 := PaperGeometry.clip_half_plane(corner, vp, n5, s5, SLIVER_AREA)
		var t1 := PaperGeometry.clip_half_plane(corner, vp, n5, not s5, SLIVER_AREA)
		if t1.size() < 3 or t2.size() < 3:
			return false
		# Where the triangles go: the diagonal ends up at its angles to the
		# side's crease (fixed) and to the flap's hinge (turned with the flap).
		var v3 := sf.at(vp)
		var sb := sf.xf.basis
		var w4 := (sb * Vector3(e4.x, e4.y, 0.0)).normalized()
		var w2 := (sb * Vector3(e2.x, e2.y, 0.0)).normalized()
		var w5 := (sb * Vector3(c5.x, c5.y, 0.0)).normalized()
		var b := (rot * w2).normalized()
		var n_in := sf.normal()
		if n_in.dot(mf.at(PaperGeometry.centroid(mf.pts)) - v3) < 0.0:
			n_in = -n_in
		var alpha1 := e4.angle_to(c5)
		var alpha2 := c5.angle_to(e2)
		var v: Vector3
		var cr := w4.cross(b)
		var c := w4.dot(b)
		if cr.length() < 1e-3:
			v = (w4 * cos(absf(alpha1)) - n_in * sin(absf(alpha1))).normalized()
		else:
			var k1 := cos(alpha1)
			var k2 := cos(alpha2)
			var x := (k1 - c * k2) / (1.0 - c * c)
			var y := (k2 - c * k1) / (1.0 - c * c)
			var p := w4 * x + b * y
			var z := sqrt(maxf((1.0 - p.length_squared()) / cr.length_squared(), 0.0))
			v = p + cr * z
			if v.dot(n_in) > 1e-4:
				v = p - cr * z
			v = v.normalized()
		var p0 := w5 - w4 * w5.dot(w4)
		var p1 := v - w4 * v.dot(w4)
		var phi := p0.signed_angle_to(p1, w4) if p0.length() > 1e-4 and p1.length() > 1e-4 else 0.0
		var r1 := Basis(w4, phi)
		var q := _frame(b, v) * _frame(w2, w5).inverse()
		var entries := []
		if main.size() >= 3:
			entries.append([main, null])
		entries.append([t1, Transform3D(r1, v3 - r1 * v3) * sf.xf])
		entries.append([t2, Transform3D(q, v3 - q * v3) * sf.xf])
		for k in entries.size():
			var e = {"f": Facet.new(entries[k][0], sf.xf, sf.layer, sf.creases.duplicate()), "side": pieces[j].side, "src": pieces[j].src}
			var idx := j if k == 0 else pieces.size()
			if k == 0:
				pieces[j] = e
			else:
				pieces.append(e)
			if entries[k][1] != null:
				out[idx] = entries[k][1]
	return true


static func _frame(u: Vector3, w: Vector3) -> Basis:
	var x := u.normalized()
	var y := (w - x * x.dot(w)).normalized()
	return Basis(x, y, x.cross(y))


## Paper caught inside a folding flap has to fold with it: a stationary layer
## lying between two moving layers that are folded together (a "taco") on the
## moving side is pulled in, along with what's attached to it.
static func _enclose_trapped(pieces: Array, adj: Array, moving: Dictionary, moving_sign: float, a: Vector3, axis: Vector3) -> void:
	var changed := true
	while changed:
		changed = false
		for i in moving.keys():
			var fi: Facet = pieces[i].f
			for link in adj[i]:
				var j: int = link[0]
				if j < i or not moving.has(j):
					continue
				var fj: Facet = pieces[j].f
				if fi.normal().dot(fj.normal()) > -0.99 or not _coplanar(fi, fj):
					continue # not a flat-folded pair
				var lo := mini(fi.layer, fj.layer)
				var hi := maxi(fi.layer, fj.layer)
				for k in pieces.size():
					if moving.has(k) or pieces[k].side != moving_sign:
						continue
					var fk: Facet = pieces[k].f
					if fk.layer <= lo or fk.layer >= hi or not _coplanar(fk, fi) or not _in_pocket(fk, fi, fj):
						continue
					moving[k] = true
					changed = true
					var queue: Array = [k]
					while not queue.is_empty():
						var cur: int = queue.pop_back()
						var cf: Facet = pieces[cur].f
						for l2 in adj[cur]:
							var m: int = l2[0]
							if moving.has(m) or pieces[m].side != moving_sign:
								continue
							var seg: PackedVector2Array = l2[1]
							if _line_dist(cf.at(seg[0]), a, axis) < TEAR_TOL and _line_dist(cf.at(seg[1]), a, axis) < TEAR_TOL:
								continue
							moving[m] = true
							queue.append(m)


## Whether two coplanar facets overlap (by more than a sliver).
static func _overlaps(a: Facet, b: Facet) -> bool:
	var cn := canonical(a.normal())
	var u := cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := cn.cross(u)
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for p in a.pts:
		var w := a.at(p)
		pa.append(Vector2(w.dot(u), w.dot(v)))
	for p in b.pts:
		var w := b.at(p)
		pb.append(Vector2(w.dot(u), w.dot(v)))
	return PaperGeometry.overlap_area(pa, pb) > 0.01


## Whether coplanar facet `k` reaches into the pocket between the folded pair
## `a`, `b` (where they overlap each other), rather than just overlapping one
## of them somewhere else.
static func _in_pocket(k: Facet, a: Facet, b: Facet) -> bool:
	var cn := canonical(a.normal())
	var u := cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := cn.cross(u)
	var flat := func(f: Facet) -> PackedVector2Array:
		var poly := PackedVector2Array()
		for p in f.pts:
			var w := f.at(p)
			poly.append(Vector2(w.dot(u), w.dot(v)))
		return poly
	var pk: PackedVector2Array = flat.call(k)
	for pocket in Geometry2D.intersect_polygons(flat.call(a), flat.call(b)):
		if PaperGeometry.overlap_area(pk, pocket) > 0.01:
			return true
	return false


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
		var across := 0.0 # paper area on the other side of this edge
		for j in src.size():
			if j == gi:
				continue
			var other: Facet = src[j]
			if not shared_edge(PackedVector2Array([e0, e1]), other.pts).is_empty():
				dihedral = minf(dihedral, other.normal().dot(n))
				across += absf(PaperGeometry.signed_area(other.pts))
		if dihedral > 0.999:
			continue # a flat, unfolded crease: nothing to swing about
		if absf(PaperGeometry.signed_area(gf.pts)) > 1.5 * across:
			continue # holding the big piece a flap is folded off: that's a new fold, not swinging it
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


## A remembered crease line (one folded before, or printed on the paper) that
## runs close to the new crease, on paper lying in the grabbed facet's plane:
## fold along it instead. The bigger the flap (the further the grabbed point g
## is from the line), the coarser the aim it forgives: you can't hold the tip
## of a 4 m flap 4 m up. Returns [point, direction] or null.
static func _remembered_crease(src: Array, gf: Facet, a: Vector3, axis: Vector3, g: Vector3):
	var best = null
	var best_d := INF
	for item in src:
		var f: Facet = item
		if not _coplanar(f, gf):
			continue
		for key in f.creases:
			var parts: PackedStringArray = (key as String).split(":")
			if parts.size() != 3:
				continue
			var d := Vector2(float(parts[0]), float(parts[1])).normalized()
			var p0 := Vector2(-d.y, d.x) * float(parts[2]) / 1000.0 # paper-space point on the line
			# Where the line crosses this facet's paper (folded paper puts the
			# same paper line in different places).
			var seg := PaperGeometry.clip_segment(p0 - d * 1000.0, p0 + d * 1000.0, f.pts)
			if seg.is_empty() or seg[0].distance_to(seg[1]) < 0.05:
				continue
			var p := f.at(seg[0])
			var e := (f.at(seg[1]) - p).normalized()
			if absf(e.dot(axis)) < cos(deg_to_rad(5.0)):
				continue
			var dist := maxf(_line_dist(a - axis * 2.0, p, e), _line_dist(a + axis * 2.0, p, e))
			if dist < maxf(MEMORY_SNAP, MEMORY_SNAP_SHARE * _line_dist(g, p, e)) and dist < best_d:
				best_d = dist
				best = [p + e * e.dot(a - p), e if e.dot(axis) > 0.0 else -e]
	return best


## A crease that nearly passes through existing corners of the grabbed plane is
## moved to pass exactly through them (through two if it can, keeping roughly
## the same direction), so folds meet at clean points instead of leaving slivers.
static func _through_vertices(src: Array, gf: Facet, a: Vector3, axis: Vector3):
	var near: Array = []
	for item in src:
		var f: Facet = item
		if not _coplanar(f, gf):
			continue
		for p in f.pts:
			var v := f.at(p)
			if _line_dist(v, a, axis) < VERTEX_AXIS_SNAP:
				var dup := false
				for q in near:
					if (q as Vector3).distance_to(v) < 1e-3:
						dup = true
				if not dup:
					near.append(v)
	if near.is_empty():
		return null
	var best_pair = null
	var best_err := INF
	for i in near.size():
		for j in range(i + 1, near.size()):
			var d: Vector3 = near[j] - near[i]
			if d.length() < 0.3:
				continue
			d = d.normalized()
			if absf(d.dot(axis)) < cos(deg_to_rad(6.0)):
				continue
			var err := _line_dist(near[i], a, axis) + _line_dist(near[j], a, axis)
			if err < best_err:
				best_err = err
				best_pair = [near[i], d if d.dot(axis) > 0.0 else -d]
	if best_pair != null:
		return best_pair
	var closest: Vector3 = near[0]
	for v in near:
		if _line_dist(v, a, axis) < _line_dist(closest, a, axis):
			closest = v
	return [closest, axis]


static func _line_dist(p: Vector3, a: Vector3, d: Vector3) -> float:
	var off := p - a
	return (off - d * off.dot(d)).length()


## Reverse folds: split the moving paper into its two sides (pieces joined only
## through 180-degree folds such as the spine), then swing the upper side and
## the lower side about the crease in opposite directions.
static func _finish_reverse(res: Dictionary, pieces: Array, adj: Array, moving: Dictionary, a: Vector3,
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

	# Upper side = the components making up the top half of the moving layers
	# (by stacking rank: layer numbers have gaps where other paper lies).
	var means: Array = []
	for members in comps:
		var total := 0.0
		for i in members:
			total += pieces[i].f.layer
		means.append(total / members.size())
	var by_rank: Array = range(comps.size())
	by_rank.sort_custom(func(x: int, y: int) -> bool: return means[x] < means[y])
	var upper := {}
	var lower := {}
	for r in by_rank.size():
		for i in comps[by_rank[r]]:
			if r >= by_rank.size() / 2:
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
		var nf := Facet.new(f.pts, xf, 0, f.creases.duplicate())
		keyed.append([key, nf])
		if moving.has(i):
			moved.append(nf)

	# Let the layer solver stack it physically. Paper that didn't move keeps its
	# order. Across the new crease, each tip piece ends up on the side of its
	# unmoved neighbour that it swung through (inside the flap for an inside
	# reverse fold, outside for an outside one). The fold rules work out how
	# the tips stack among themselves.
	var out: Array = []
	var guess: Array = []
	var order := range(keyed.size())
	order.sort_custom(func(x: int, y: int) -> bool: return keyed[x][0] < keyed[y][0])
	guess.resize(keyed.size())
	for r in order.size():
		guess[order[r]] = r
	for i in keyed.size():
		out.append(keyed[i][1])
	# Which half of the flap each unmoved piece belongs with: the paper joined
	# (nearest) to the upper layers or to the lower ones. The tips stay between
	# the two, as they go in between the flap's layers, rather than slipping
	# into some pocket on one side.
	var half := {}
	var frontier: Array = []
	for i in moving:
		for link in adj[i]:
			if not moving.has(link[0]) and not half.has(link[0]):
				half[link[0]] = 1 if upper.has(i) else -1
				frontier.append(link[0])
	while not frontier.is_empty():
		var next: Array = []
		for cur in frontier:
			for link in adj[cur]:
				var j: int = link[0]
				if moving.has(j) or half.has(j):
					continue
				half[j] = half[cur]
				next.append(j)
		frontier = next
	var known := {}
	var prefer := {}
	for i in out.size():
		for j in range(i + 1, out.size()):
			if not _coplanar(out[i], out[j]):
				continue
			var key := "%d,%d" % [i, j]
			prefer[key] = guess[i] < guess[j]
			if moving.has(i) != moving.has(j):
				var still: int = j if moving.has(i) else i
				if half.has(still):
					prefer[key] = (half[still] > 0) == (still == j) # tip below the upper half, above the lower
			if not moving.has(i) and not moving.has(j):
				known[key] = pieces[i].f.layer < pieces[j].f.layer
	for i in moving:
		for link in adj[i]:
			var j: int = link[0]
			if moving.has(j):
				continue
			# A tip lands on the side of its rim that it swung through.
			var tip_below: bool = upper.has(i) == inside
			var lo := mini(i, j)
			known["%d,%d" % [lo, maxi(i, j)]] = (lo == i) == tip_below
	var ranks := PaperLayers.solve(out, known, prefer, guess)
	if ranks.is_empty():
		res.reason = "other paper is in the way"
		return res
	for i in out.size():
		out[i].layer = ranks[i]
		out[i].xf = out[i].xf.orthonormalized()
	out.sort_custom(func(x: Facet, y: Facet) -> bool: return x.layer < y.layer)
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


## The segment two convex paper-space polygons share, or empty. (Convex
## polygons can only share one stretch of one line; it may span several edges.)
static func shared_edge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var found := false
	var origin := Vector2.ZERO
	var dir := Vector2.ZERO
	var lo := INF
	var hi := -INF
	for i in a.size():
		var p0 := a[i]
		var p1 := a[(i + 1) % a.size()]
		var length := p0.distance_to(p1)
		if length < 1e-4:
			continue
		var d := (p1 - p0) / length
		var nrm := Vector2(-d.y, d.x)
		for j in b.size():
			var q0 := b[j]
			var q1 := b[(j + 1) % b.size()]
			if absf((q0 - p0).dot(nrm)) > 1e-3 or absf((q1 - p0).dot(nrm)) > 1e-3:
				continue
			var t0 := (q0 - p0).dot(d)
			var t1 := (q1 - p0).dot(d)
			var s0 := maxf(0.0, minf(t0, t1))
			var s1 := minf(length, maxf(t0, t1))
			if s1 - s0 <= 1e-3:
				continue
			if not found:
				found = true
				origin = p0
				dir = d
			elif absf((p0 - origin).dot(Vector2(-dir.y, dir.x))) > 1e-3 or absf(d.cross(dir)) > 1e-3:
				continue # a different line (can't happen for convex pieces)
			var base := (p0 - origin).dot(dir) * signf(1.0)
			var sgn := signf(d.dot(dir))
			lo = minf(lo, minf(base + s0 * sgn, base + s1 * sgn))
			hi = maxf(hi, maxf(base + s0 * sgn, base + s1 * sgn))
	if not found:
		return PackedVector2Array()
	return PackedVector2Array([origin + dir * lo, origin + dir * hi])


# --- Stacking & handles ------------------------------------------------------

## Per-facet offsets that lift overlapping coplanar layers apart by LAYER_GAP,
## in stacking order, so thin paper never z-fights or interpenetrates.
## `not_base` lists facets that shouldn't be taken as the main stack (the paper
## a fold is moving).
static func stack_offsets(list: Array, not_base: Array = []) -> Array:
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
	_carry_offsets(list, offsets, flat, normals, not_base)
	return offsets


## Paper standing out of the main stack (a flap part-way through a fold, a
## spread wing) is lifted along with the layer it's hinged to, so it stays
## attached at its crease instead of swinging out of the bottom of the stack
## (and passing through the layers above it on the way).
static func _carry_offsets(list: Array, offsets: Array, flat: Array, normals: Array, not_base: Array) -> void:
	var count := list.size()
	# The main stack: the plane holding the most paper (ignoring `not_base`).
	var plane_of: Array = []
	plane_of.resize(count)
	var plane_area: Array = []
	var plane_rep: Array = []
	for i in count:
		var f: Facet = list[i]
		var k := -1
		for p in plane_rep.size():
			if _coplanar(f, list[plane_rep[p]]):
				k = p
				break
		if k < 0:
			k = plane_rep.size()
			plane_rep.append(i)
			plane_area.append(0.0)
		plane_of[i] = k
		if not not_base.has(f):
			plane_area[k] += absf(PaperGeometry.signed_area(flat[i]))
	if plane_rep.size() < 2:
		return
	var base := 0
	for p in plane_area.size():
		if plane_area[p] > plane_area[base]:
			base = p
	var carry: Array = []
	carry.resize(count)
	var queue: Array = []
	for i in count:
		if plane_of[i] == base:
			carry[i] = Vector3.ZERO
			queue.append(i)
	while not queue.is_empty():
		var s: int = queue.pop_front()
		for i in count:
			if carry[i] != null:
				continue
			if shared_edge(list[s].pts, list[i].pts).is_empty():
				continue
			# Same plane: lifted the same way. Another plane: lifted to where
			# the hinge is shown.
			carry[i] = carry[s] if plane_of[i] == plane_of[s] else carry[s] + offsets[s]
			queue.append(i)
	for i in count:
		if carry[i] != null:
			offsets[i] = offsets[i] + carry[i]


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



# --- Collapses (multi-crease folds) -------------------------------------------
#
# Paper that has been creased (folded and unfolded) can be collapsed along many
# creases at once; that is what squash folds and petal folds are. A collapse
# keeps one piece of paper still and, for a chosen set of creases, flips each one
# between lying open and folded flat. Every other hinge keeps its current angle.
# The new pose of every facet follows by walking the hinges out from the still
# piece; the choice is only valid if every hinge agrees (otherwise the paper
# would have to tear or stretch). Among the valid choices, the one that brings
# the grabbed point closest to the hands wins (more creases folded on ties).

## Relative pose of facet b in facet a's paper frame.
static func _rel(a: Facet, b: Facet) -> Transform3D:
	return a.xf.affine_inverse() * b.xf


## Half turn about a paper-space segment's line (flips the paper over it).
static func _half_turn(seg: PackedVector2Array) -> Transform3D:
	var p := Vector3(seg[0].x, seg[0].y, 0.0)
	var d := Vector3(seg[1].x - seg[0].x, seg[1].y - seg[0].y, 0.0).normalized()
	var r := Basis(d, PI)
	return Transform3D(r, p - r * p)


static func _same_pose(a: Transform3D, b: Transform3D, eps := 2e-3) -> bool:
	return a.origin.distance_to(b.origin) < eps and a.basis.x.distance_to(b.basis.x) < eps \
		and a.basis.y.distance_to(b.basis.y) < eps and a.basis.z.distance_to(b.basis.z) < eps


## Every hinge between facets: {i, j, seg (paper space), rel, state} where state is
## 0 = open flat, 1 = folded flat, 2 = anything in between.
static func hinges(src: Array) -> Array:
	var out: Array = []
	for i in src.size():
		for j in range(i + 1, src.size()):
			var seg := shared_edge(src[i].pts, src[j].pts)
			if seg.is_empty():
				continue
			var rel := _rel(src[i], src[j])
			var state := 2
			if _same_pose(rel, Transform3D.IDENTITY):
				state = 0
			elif _same_pose(rel, _half_turn(seg)):
				state = 1
			out.append({"i": i, "j": j, "seg": seg, "rel": rel, "state": state})
	return out


## All the ways the paper can collapse flat along its creases. Each crease
## line (a chain of hinges) either folds flat or opens flat; the choice must be
## flat-foldable where creases meet inside the paper (Kawasaki: alternate angles
## between folded creases sum to 180 degrees). Which way each crease folds
## (mountain or valley) is left to the layer solver, which prefers the way a
## crease was folded before but can reverse it, as in a petal fold. This is a
## constraint search over the creases, nearest the grab first, so far-away paper
## stays put. Callers should keep the result for the whole drag.
## Returns {states, root, hinges}; each state is {xfs, g, toggled, count, parent, via}.
static func collapse_states(src: Array, gi: int, g: Vector3) -> Dictionary:
	var hs := hinges(src)
	var links: Array = []
	links.resize(src.size())
	for i in src.size():
		links[i] = []
	for k in hs.size():
		links[hs[k].i].append(k)
		links[hs[k].j].append(k)

	# Every flat crease is a variable; partly folded ones stay as they are.
	var cand: Array = []
	for k in hs.size():
		if hs[k].state != 2:
			cand.append(k)
	var groups := _crease_groups(src, hs, cand)
	# Far creases first, so the search varies the near ones before touching them.
	groups.sort_custom(func(x: Array, y: Array) -> bool:
		return _group_dist(src, hs, x, g) > _group_dist(src, hs, y, g))
	var group_of := {}
	for v in groups.size():
		for k in groups[v]:
			group_of[k] = v

	# Inner paper vertices and the crease rays leaving them.
	var lo := Vector2(INF, INF)
	var hi := -lo
	for f in src:
		for p in f.pts:
			lo = lo.min(p)
			hi = hi.max(p)
	var verts := {}
	for k in hs.size():
		for e in 2:
			var v: Vector2 = hs[k].seg[e]
			var key := _pkey(v)
			if not verts.has(key):
				verts[key] = {"at": v, "rays": []}
			verts[key].rays.append(k)
	var checks: Array = [] # per depth: vertices whose rays are all decided by then
	checks.resize(groups.size() + 1)
	for d in checks.size():
		checks[d] = []
	for key in verts:
		var vx: Dictionary = verts[key]
		var v: Vector2 = vx.at
		if v.x < lo.x + 1e-3 or v.x > hi.x - 1e-3 or v.y < lo.y + 1e-3 or v.y > hi.y - 1e-3:
			continue # on the paper's edge: no constraint
		var rays: Array = []
		var deepest := -1
		var fixed := true
		for k in vx.rays:
			var h: Dictionary = hs[k]
			var far: Vector2 = h.seg[1] if (h.seg[0] as Vector2).distance_to(v) < 1e-3 else h.seg[0]
			var mv := fold_direction(src[h.i], src[h.j], h.seg) if h.state == 1 else _memory(src, h)
			rays.append({"k": k, "angle": (far - v).angle(), "mv": mv})
			if h.state == 2:
				fixed = false
			elif group_of.has(k):
				deepest = maxi(deepest, group_of[k])
		if not fixed:
			continue # something here is partly folded; leave it be
		rays.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.angle < y.angle)
		checks[deepest + 1].append(rays)

	var root := 0
	var far := -1.0
	for i in src.size():
		var d: float = src[i].at(PaperGeometry.centroid(src[i].pts)).distance_to(g)
		if d > far + 0.05 or (absf(d - far) <= 0.05 and src[i].layer < src[root].layer):
			if d > far:
				far = d
			root = i

	var gp: Vector3 = src[gi].xf.affine_inverse() * g
	var ctx := {"src": src, "hs": hs, "links": links, "groups": groups, "checks": checks,
		"root": root, "gi": gi, "gp": gp, "states": [], "nodes": 0}
	_collapse_search(ctx, 0, {})
	return {"states": ctx.states, "root": root, "hinges": hs}


const COLLAPSE_MAX_STATES := 400
const COLLAPSE_MAX_NODES := 60000


static func _collapse_search(ctx: Dictionary, depth: int, toggled: Dictionary) -> void:
	if ctx.states.size() >= COLLAPSE_MAX_STATES or ctx.nodes >= COLLAPSE_MAX_NODES:
		return
	ctx.nodes += 1
	for rays in ctx.checks[depth]:
		if not _flat_foldable_at(ctx.hs, rays, toggled):
			return
	if depth == ctx.groups.size():
		if toggled.is_empty():
			return
		var walk := _walk(ctx.src, ctx.hs, ctx.links, ctx.root, toggled)
		if walk.is_empty():
			return
		var count := 0
		var seen := {}
		for k in toggled:
			seen[_pkey(ctx.hs[k].seg[0]) + _pkey(ctx.hs[k].seg[1])] = true
		var moved_area := 0.0
		for i in ctx.src.size():
			if not _same_pose(walk.xfs[i], ctx.src[i].xf):
				moved_area += absf(PaperGeometry.signed_area(ctx.src[i].pts))
		ctx.states.append({"xfs": walk.xfs, "g": walk.xfs[ctx.gi] * ctx.gp, "toggled": toggled.duplicate(),
			"count": seen.size(), "moved_area": moved_area, "parent": walk.parent, "via": walk.via})
		return
	# Leave this crease as it is first, then try flipping it.
	_collapse_search(ctx, depth + 1, toggled)
	for k in ctx.groups[depth]:
		toggled[k] = true
	_collapse_search(ctx, depth + 1, toggled)
	for k in ctx.groups[depth]:
		toggled.erase(k)


## Kawasaki's theorem at one inner vertex.
static func _flat_foldable_at(hs: Array, rays: Array, toggled: Dictionary) -> bool:
	var angles: Array = []
	for r in rays:
		var h: Dictionary = hs[r.k]
		var folded: bool = (h.state == 1) != toggled.has(r.k)
		if folded:
			angles.append(r.angle)
	if angles.is_empty():
		return true
	if angles.size() % 2 == 1:
		return false
	var alt := 0.0
	for i in angles.size():
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()]
		var sector := fposmod(b - a, TAU)
		alt += sector if i % 2 == 0 else -sector
	return absf(alt) <= 1e-3


## Poses every facet by walking hinges out from `root`, flipping toggled ones.
## Returns {} if two routes disagree about where some paper goes (a tear).
static func _walk(src: Array, hs: Array, links: Array, root: int, toggled: Dictionary) -> Dictionary:
	var xfs: Array = []
	xfs.resize(src.size())
	var parent: Array = []
	parent.resize(src.size())
	var via: Array = []
	via.resize(src.size())
	xfs[root] = src[root].xf
	parent[root] = -1
	var queue: Array = [root]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for k in links[cur]:
			var h: Dictionary = hs[k]
			var rel: Transform3D = h.rel
			if toggled.has(k):
				rel = rel * _half_turn(h.seg)
			var other: int = h.j
			if h.i != cur:
				other = h.i
				rel = rel.affine_inverse()
			var pose: Transform3D = xfs[cur] * rel
			if xfs[other] == null:
				xfs[other] = pose
				parent[other] = cur
				via[other] = k
				queue.append(other)
			elif not _same_pose(xfs[other], pose):
				return {}
	for i in src.size():
		if xfs[i] == null:
			xfs[i] = src[i].xf # not connected (shouldn't happen for one sheet)
	return {"xfs": xfs, "parent": parent, "via": via}


static func _crease_groups(src: Array, hs: Array, cand: Array) -> Array:
	# Paper-space endpoints -> hinges touching them (all hinges, to see junctions).
	var at := {}
	for k in hs.size():
		for p in hs[k].seg:
			var key := _pkey(p)
			if not at.has(key):
				at[key] = []
			at[key].append(k)
	var group_of := {}
	var groups: Array = []
	for k in cand:
		if group_of.has(k):
			continue
		var members: Array = [k]
		group_of[k] = groups.size()
		var queue: Array = [k]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			var seg: PackedVector2Array = hs[cur].seg
			var dir := (seg[1] - seg[0]).normalized()
			for p in seg:
				var touching: Array = at[_pkey(p)]
				var straight := true
				for o in touching:
					var os: PackedVector2Array = hs[o].seg
					if absf((os[1] - os[0]).normalized().cross(dir)) > 1e-3:
						straight = false
				if not straight:
					continue # creases meet here: the line may fold on one side only
				for o in touching:
					if o != cur and not group_of.has(o) and cand.has(o) and hs[o].state == hs[cur].state:
						group_of[o] = groups.size()
						members.append(o)
						queue.append(o)
		groups.append(members)
	return groups


static func _pkey(p: Vector2) -> String:
	return "%d,%d" % [roundi(p.x * 1000.0), roundi(p.y * 1000.0)]


static func _group_dist(src: Array, hs: Array, group: Array, g: Vector3) -> float:
	var best := INF
	for k in group:
		var h: Dictionary = hs[k]
		var f: Facet = src[h.i]
		best = minf(best, Geometry3D.get_closest_point_to_segment(g, f.at(h.seg[0]), f.at(h.seg[1])).distance_to(g))
	return best


## Plans a collapse that brings g (on facet gi) toward t. `cache` (optional)
## holds collapse_states() for this paper and grab, reused during a drag.
## Several collapses can fit the hands equally well (a precreased square can
## become a square base or a waterbomb base); `choice` picks among them.
static func plan_collapse(src: Array, gi: int, g: Vector3, t: Vector3, up: Vector3,
		cache: Dictionary = {}, choice: int = 0) -> Dictionary:
	var res := {"ok": false, "reason": "", "facets": [], "axis_a": g, "axis_d": Vector3.ZERO,
		"plane_n": src[gi].normal(), "theta": PI, "moved": [], "swept": false, "choices": 0, "choice": 0}
	var found: Dictionary = cache if not cache.is_empty() else collapse_states(src, gi, g)
	if found.states.is_empty():
		res.reason = "no creases here to collapse along (crease the paper first)"
		return res
	if g.distance_to(t) < MIN_DRAG:
		res.reason = "drag further"
		return res
	# Every collapse that fits the hands about as well as the best one, the one
	# moving the least paper first (the smallest change that does it), then the
	# fewest creases; `choice` cycles through them.
	var best_d := INF
	for st in found.states:
		best_d = minf(best_d, (st.g as Vector3).distance_to(t))
	var fits: Array = []
	for st in found.states:
		if (st.g as Vector3).distance_to(t) <= best_d + 0.3:
			fits.append(st)
	fits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(a.moved_area - b.moved_area) > 0.01:
			return a.moved_area < b.moved_area
		return a.count < b.count or (a.count == b.count and (a.g as Vector3).distance_to(t) < (b.g as Vector3).distance_to(t)))
	if best_d > maxf(1.0, 0.4 * g.distance_to(t)):
		res.reason = "no collapse brings that point there"
		return res
	res.choices = fits.size()
	for attempt in fits.size():
		var pick := posmod(choice + attempt, fits.size())
		var stacked := _stack_collapse(src, gi, fits[pick], found, up)
		if stacked.is_empty():
			continue # no physical way to layer this one
		if (fits[pick].g as Vector3).distance_to(g) < MIN_DRAG:
			res.reason = "drag further"
			return res
		res.choice = pick
		var moved: Array = []
		for i in src.size():
			if not _same_pose(stacked[i].xf, src[i].xf):
				moved.append(stacked[i])
		stacked.sort_custom(func(a: Facet, b: Facet) -> bool: return a.layer < b.layer)
		res.ok = true
		res.facets = stacked
		res.moved = moved
		return res
	res.reason = "no physical way to stack that collapse"
	return res


## Poses and layers the facets for one collapse state, or [] if the paper can't
## be stacked physically that way. Paper that moves rigidly together keeps its
## relative order (reversed if it flipped over); creases that close fold the way
## they remember; the layer solver works out the rest.
static func _stack_collapse(src: Array, gi: int, state: Dictionary, found: Dictionary, up: Vector3) -> Array:
	var n := src.size()
	var cand: Array = []
	for i in n:
		cand.append(Facet.new(src[i].pts, (state.xfs[i] as Transform3D).orthonormalized(), src[i].layer, src[i].creases.duplicate()))
	var known := {}
	var prefer := {}
	var old_layers: Array = []
	var delta: Array = []
	for i in n:
		old_layers.append(src[i].layer)
		delta.append(cand[i].xf * src[i].xf.affine_inverse())
	# Rigid bodies: paper joined by creases that didn't change moved as one piece.
	var body: Array = range(n)
	var find := func(x: int) -> int:
		while body[x] != x:
			x = body[x]
		return x
	for k in found.hinges.size():
		if not state.toggled.has(k):
			var h: Dictionary = found.hinges[k]
			var ra: int = find.call(h.i)
			var rb: int = find.call(h.j)
			if ra != rb:
				body[ra] = rb
	for i in n:
		for j in range(i + 1, n):
			if not _coplanar(cand[i], cand[j]):
				continue
			var still: bool = _same_pose(delta[i], Transform3D.IDENTITY) and _same_pose(delta[j], Transform3D.IDENTITY)
			if still or find.call(i) == find.call(j):
				# Moved as one (or not at all): same order, unless it flipped over.
				var before: bool = src[i].layer < src[j].layer
				var oc := canonical(src[i].normal())
				var keep: bool = ((delta[i] as Transform3D).basis * oc).dot(canonical(cand[i].normal())) > 0.0
				known["%d,%d" % [i, j]] = before == keep

	# Where it's free to choose, stack it the way hands do it: the flap that
	# carries the grabbed point swings toward the hands, and the paper it drags
	# along tucks in underneath it (as in a petal fold, where the sides fold in
	# under the lifted flap even though their creases were made the other way).
	var hs: Array = found.hinges
	var on_path := {}
	var walker: int = gi
	while walker >= 0:
		on_path[find.call(walker)] = true # the whole rigid piece carrying it
		walker = state.parent[walker]
	for i in n:
		if on_path.has(find.call(i)):
			on_path[i] = true
	var lift_up: bool = canonical(src[gi].normal()).dot(up) >= 0.0
	for k in state.toggled:
		var h: Dictionary = hs[k]
		if h.state != 0:
			continue
		var child: int = h.j if state.parent[h.j] == h.i else h.i
		var parent: int = h.i if child == h.j else h.j
		# Paper folding off a layer that stays put comes up with the lifted flap
		# (in a square base the side flaps fold in between front and back);
		# paper folding off moving paper tucks under it.
		var parent_still := _same_pose(delta[parent], Transform3D.IDENTITY)
		var child_above: bool = lift_up if parent_still and not on_path.has(child) else on_path.has(child) == lift_up
		var a: int = mini(child, parent)
		var b: int = maxi(child, parent)
		prefer["%d,%d" % [a, b]] = (a == parent) == child_above
	var ranks := PaperLayers.solve(cand, known, prefer, old_layers)
	if ranks.is_empty():
		return []
	for i in n:
		cand[i].layer = ranks[i]
	return cand


# --- Crease memory -------------------------------------------------------------

static func line_key(seg: PackedVector2Array) -> String:
	var d := (seg[1] - seg[0]).normalized()
	if d.x < -1e-6 or (absf(d.x) <= 1e-6 and d.y < 0.0):
		d = -d
	var n := Vector2(-d.y, d.x)
	return "%d:%d:%d" % [roundi(d.x * 1000.0), roundi(d.y * 1000.0), roundi(n.dot(seg[0]) * 1000.0)]


## Valley (+1) or mountain (-1), seen from the paper's front, of the fold
## between facets a and b along their shared paper edge `seg`; 0 if open flat.
static func fold_direction(a: Facet, b: Facet, seg: PackedVector2Array) -> int:
	var rel := _rel(a, b)
	if _same_pose(rel, Transform3D.IDENTITY):
		return 0
	var na := a.normal()
	if _coplanar(a, b):
		var cn := canonical(na)
		return 1 if (b.layer - a.layer) * signf(na.dot(cn)) > 0 else -1
	var hinge := a.at((seg[0] + seg[1]) * 0.5)
	return 1 if (b.at(PaperGeometry.centroid(b.pts)) - hinge).dot(na) > 0.0 else -1


## Updates every facet's crease memory from the folds it has right now. Call
## after committing a fold; open creases keep their memory.
static func remember_creases(list: Array) -> void:
	for i in list.size():
		for j in range(i + 1, list.size()):
			var seg := shared_edge(list[i].pts, list[j].pts)
			if seg.is_empty():
				continue
			var mv := fold_direction(list[i], list[j], seg)
			if mv != 0:
				var key := line_key(seg)
				list[i].creases[key] = mv
				list[j].creases[key] = mv


## Remembered direction of the crease between hinge facets, or 0 if unknown.
static func _memory(src: Array, h: Dictionary) -> int:
	return int(src[h.i].creases.get(line_key(h.seg), 0))


# --- Validation ----------------------------------------------------------------

## Problems with a folded state, or [] if it's physically valid: every hinge
## joins its two facets along the same 3D edge (no tearing), non-coplanar paper
## doesn't pass through other paper, and no paper went missing.
static func validate(list: Array, paper_area: float) -> Array:
	var problems: Array = []
	var total := 0.0
	for f in list:
		total += absf(PaperGeometry.signed_area((f as Facet).pts))
	if absf(total - paper_area) > 1e-3 * paper_area:
		problems.append("paper area %.2f != %.2f" % [total, paper_area])
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Facet = list[i]
			var b: Facet = list[j]
			var seg := shared_edge(a.pts, b.pts)
			if not seg.is_empty():
				for p in seg:
					if a.at(p).distance_to(b.at(p)) > 0.01:
						problems.append("tear between facets %d and %d" % [i, j])
						break
			elif not _coplanar(a, b) and (_crosses(a, b) or _crosses(b, a)):
				problems.append("facets %d and %d pass through each other" % [i, j])
	return problems
