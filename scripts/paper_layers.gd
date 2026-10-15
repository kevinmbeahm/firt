class_name PaperLayers
extends RefCounted
## Layer ordering for flat-folded paper.
##
## Where paper lies flat in one plane, overlapping facets need a stacking order,
## and not every order is physically possible. These are the standard rules
## (as in computational origami, e.g. Demaine & O'Rourke):
##   * taco-tortilla:     paper that spans a fold line can't sit between the two
##                        facets folded together at that line;
##   * tortilla-tortilla: paper that spans a flat seam (two facets lying side by
##                        side) must be on the same side of both;
##   * taco-taco:         two folds along the same line nest, never interleave;
##   * transitivity:      it all has to form one consistent stack.
## Every pair of overlapping facets gets a boolean "a is below b". The first
## three rules are parity equalities between those booleans, so they're solved
## with a union-find; the rest is a search that propagates transitivity (a < b
## and b < c force a < c) as it goes, so contradictions show up early.

const OVERLAP_EPS := 0.01 ## square metres
const SPAN_INSET := 0.02 ## metres

## Why the last solve() failed (for debugging): "", a contradiction, "budget"
## or "no stack".
static var last_failure := ""


## Finds a stacking. `known` fixes some pairs ("i,j" with i < j -> i below j),
## `prefer` biases free choices the same way, `old_layers` breaks ties.
## Returns a layer rank per facet, or [] if no physical stacking exists.
static func solve(list: Array, known: Dictionary, prefer: Dictionary, old_layers: Array) -> Array:
	var info := _analyse(list)
	last_failure = ""
	var uf := _UnionFind.new(info.vars.size() + 1) # node 0 = the constant "false"
	for key in known:
		if info.vars.has(key) and not uf.link(info.vars[key] + 1, 0, 1 if known[key] else 0):
			last_failure = "contradiction (known)"
			return []
	for eq in info.equalities:
		if not uf.link(eq[0] + 1, eq[1] + 1, eq[2]):
			last_failure = "contradiction (fold/seam rule)"
			return []

	# Every variable belongs to a class whose single boolean decides it.
	var n := list.size()
	var nv: int = info.pairs.size()
	var zero: int = uf.find(0)
	var cls: Array = []
	var par: Array = []
	cls.resize(nv)
	par.resize(nv)
	var members := {}
	for v in nv:
		cls[v] = uf.find(v + 1)
		par[v] = uf.parity(v + 1)
		if not members.has(cls[v]):
			members[cls[v]] = []
		members[cls[v]].append(v)
	var nbr: Array = []
	nbr.resize(n)
	for i in n:
		nbr[i] = []
	for v in nv:
		var pair: Array = info.pairs[v]
		nbr[pair[0]].append(pair[1])
		nbr[pair[1]].append(pair[0])
	var st := {"info": info, "cls": cls, "par": par, "members": members, "nbr": nbr,
		"value": {zero: false}, "trail": [], "nodes": 0, "prefer": prefer}
	# Classes tied to the constant are decided already; propagate from them.
	if not _propagate(st, [zero]):
		last_failure = "contradiction (stacking order)"
		return []
	var free: Array = []
	for c in members:
		if not st.value.has(c):
			free.append(c)
	var order := _dfs(st, free, list, old_layers)
	if order.is_empty():
		last_failure = ("budget (%d free choices)" if st.nodes >= MAX_NODES else "no stack (%d free choices)") % free.size()
	return order


const MAX_NODES := 20000


## Is facet a below facet b according to what's decided? null if undecided.
static func _below(st: Dictionary, a: int, b: int):
	var key := "%d,%d" % ([a, b] if a < b else [b, a])
	if not st.info.vars.has(key):
		return null
	var v: int = st.info.vars[key]
	var c: int = st.cls[v]
	if not st.value.has(c):
		return null
	var low_first: bool = (st.value[c] as bool) != (st.par[v] == 1) # pair[0] below pair[1]
	return low_first if a < b else not low_first


## Requires facet a below facet b; decides its class if needed. False on conflict.
static func _force(st: Dictionary, a: int, b: int, queue: Array) -> bool:
	var key := "%d,%d" % ([a, b] if a < b else [b, a])
	if not st.info.vars.has(key):
		return true
	var v: int = st.info.vars[key]
	var c: int = st.cls[v]
	var want_low_first: bool = a < b
	var val: bool = want_low_first != (st.par[v] == 1)
	if st.value.has(c):
		return st.value[c] == val
	st.value[c] = val
	st.trail.append(c)
	queue.append(c)
	return true


## Spreads the consequences of newly decided classes: if a < b and b < c (and
## a, c overlap) then a < c. False on a contradiction.
static func _propagate(st: Dictionary, queue: Array) -> bool:
	while not queue.is_empty():
		var c: int = queue.pop_back()
		for v in st.members.get(c, []):
			var pair: Array = st.info.pairs[v]
			var below = _below(st, pair[0], pair[1])
			var lo: int = pair[0] if below else pair[1]
			var hi: int = pair[1] if below else pair[0]
			for k in st.nbr[hi]:
				if k != lo and _below(st, hi, k) == true and not _force(st, lo, k, queue):
					return false
			for k in st.nbr[lo]:
				if k != hi and _below(st, k, lo) == true and not _force(st, k, hi, queue):
					return false
	return _taco_taco_ok(st)


static func _taco_taco_ok(st: Dictionary) -> bool:
	for quad in st.info.taco_taco:
		var bits := 0
		for l in quad:
			var v: int = l[0]
			var c: int = st.cls[v]
			if not st.value.has(c):
				bits = -1
				break
			bits ^= int((st.value[c] as bool) != (st.par[v] == 1)) ^ l[1]
		if bits == 1:
			return false
	return true


static func _dfs(st: Dictionary, free: Array, list: Array, old_layers: Array) -> Array:
	st.nodes += 1
	if st.nodes >= MAX_NODES:
		return []
	var pick := -1
	for c in free:
		if not st.value.has(c):
			pick = c
			break
	if pick < 0:
		return _order(st, list, old_layers)
	# Preferred value first.
	var vote := 0
	for v in st.members[pick]:
		var pair: Array = st.info.pairs[v]
		var key := "%d,%d" % pair
		if st.prefer.has(key):
			vote += (1 if st.prefer[key] else -1) * (1 if st.par[v] == 0 else -1)
	for val in ([true, false] if vote >= 0 else [false, true]):
		var mark: int = st.trail.size()
		st.value[pick] = val
		st.trail.append(pick)
		if _propagate(st, [pick]):
			var got := _dfs(st, free, list, old_layers)
			if not got.is_empty():
				return got
		while st.trail.size() > mark:
			st.value.erase(st.trail.pop_back())
		if st.nodes >= MAX_NODES:
			return []
	return []


static func _order(st: Dictionary, list: Array, old_layers: Array) -> Array:
	var n := list.size()
	var above: Array = []
	var indeg: Array = []
	above.resize(n)
	indeg.resize(n)
	for i in n:
		above[i] = []
		indeg[i] = 0
	for v in st.info.pairs.size():
		var pair: Array = st.info.pairs[v]
		var below: bool = _below(st, pair[0], pair[1])
		var lo: int = pair[0] if below else pair[1]
		var hi: int = pair[1] if below else pair[0]
		above[lo].append(hi)
		indeg[hi] += 1
	var ready: Array = []
	for i in n:
		if indeg[i] == 0:
			ready.append(i)
	var rank: Array = []
	rank.resize(n)
	var next := 0
	while not ready.is_empty():
		ready.sort_custom(func(a: int, b: int) -> bool: return old_layers[a] < old_layers[b])
		var cur: int = ready.pop_front()
		rank[cur] = next
		next += 1
		for h in above[cur]:
			indeg[h] -= 1
			if indeg[h] == 0:
				ready.append(h)
	if next < n:
		return []
	return rank


## Problems with the current stacking of `list` (empty if it's physical).
static func check(list: Array) -> Array:
	var info := _analyse(list)
	var problems: Array = []
	var value := func(v: int) -> bool:
		var pair: Array = info.pairs[v]
		return list[pair[0]].layer < list[pair[1]].layer
	for eq in info.equalities:
		if (int(value.call(eq[0])) ^ int(value.call(eq[1]))) != eq[2]:
			var pa: Array = info.pairs[eq[0]]
			var pb: Array = info.pairs[eq[1]]
			problems.append("layers %s/%s cut through a fold or seam" % [pa, pb])
	for tt in info.taco_taco:
		var bits := 0
		for lit in tt:
			bits ^= int(value.call(lit[0])) ^ lit[1]
		if bits != 0:
			problems.append("two folds on one line interleave")
	return problems


# --- Internals -----------------------------------------------------------------

## Overlapping pairs (the variables) and the parity constraints between them.
static func _analyse(list: Array) -> Dictionary:
	var n := list.size()
	var plane: Array = []
	var poly: Array = []
	var inner: Array = []
	var rect: Array = []
	var frames: Array = []
	for f in list:
		var cn := PaperModel.canonical((f as PaperModel.Facet).normal())
		var u := cn.cross(Vector3.UP if absf(cn.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := cn.cross(u)
		var p := PackedVector2Array()
		for q in f.pts:
			var w: Vector3 = f.at(q)
			p.append(Vector2(w.dot(u), w.dot(v)))
		poly.append(p)
		inner.append(PaperGeometry.inset(p, SPAN_INSET))
		var r := Rect2(p[0], Vector2.ZERO)
		for q in p:
			r = r.expand(q)
		rect.append(r)
		frames.append([u, v])
		plane.append("%s|%d" % [cn.snapped(Vector3(0.001, 0.001, 0.001)), roundi(cn.dot(f.xf.origin) * 1000.0)])

	var vars := {}
	var pairs: Array = []
	for i in n:
		for j in range(i + 1, n):
			if plane[i] != plane[j] or not (rect[i] as Rect2).grow(-0.005).intersects(rect[j]):
				continue
			if PaperGeometry.overlap_area(poly[i], poly[j]) > OVERLAP_EPS:
				vars["%d,%d" % [i, j]] = pairs.size()
				pairs.append([i, j])

	# Literal for "a below b": [variable, negated?]
	var lit := func(a: int, b: int):
		if a < b:
			return [vars.get("%d,%d" % [a, b], -1), 0]
		return [vars.get("%d,%d" % [b, a], -1), 1]

	var equalities: Array = [] # [var, var, parity]: var1 xor var2 == parity
	var folds: Array = [] # [a, b, p0, p1] in plane coords, for taco-taco
	for a in n:
		for b in range(a + 1, n):
			if plane[a] != plane[b]:
				continue
			var seg := PaperModel.shared_edge(list[a].pts, list[b].pts)
			if seg.is_empty():
				continue
			var fa: PaperModel.Facet = list[a]
			var w0: Vector3 = fa.at(seg[0])
			var w1: Vector3 = fa.at(seg[1])
			var uv: Array = frames[a]
			var p0 := Vector2(w0.dot(uv[0]), w0.dot(uv[1]))
			var p1 := Vector2(w1.dot(uv[0]), w1.dot(uv[1]))
			var folded := fa.normal().dot(list[b].normal()) < -0.99
			if folded:
				folds.append([a, b, p0, p1])
			# Paper k spanning this fold/seam stays on one side of both a and b.
			for k in n:
				if k == a or k == b or plane[k] != plane[a]:
					continue
				if not _spans(inner[k], p0, p1):
					continue
				var la: Array = lit.call(k, a)
				var lb: Array = lit.call(k, b)
				if la[0] < 0 or lb[0] < 0:
					continue
				equalities.append([la[0], lb[0], la[1] ^ lb[1]])

	# Folds along overlapping stretches of one line must nest.
	var taco_taco: Array = []
	for x in folds.size():
		for y in range(x + 1, folds.size()):
			var f1: Array = folds[x]
			var f2: Array = folds[y]
			if not _collinear_overlap(f1[2], f1[3], f2[2], f2[3]):
				continue
			var quad := []
			for pair in [[f1[0], f2[0]], [f1[1], f2[0]], [f1[0], f2[1]], [f1[1], f2[1]]]:
				var l: Array = lit.call(pair[0], pair[1])
				if l[0] < 0:
					quad = []
					break
				quad.append(l)
			if quad.size() == 4:
				taco_taco.append(quad)
	return {"vars": vars, "pairs": pairs, "equalities": equalities, "taco_taco": taco_taco}


static func _spans(poly: PackedVector2Array, p0: Vector2, p1: Vector2) -> bool:
	for t in [0.2, 0.4, 0.5, 0.6, 0.8]:
		if Geometry2D.is_point_in_polygon(p0.lerp(p1, t), poly):
			return true
	return false


static func _collinear_overlap(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var d := (a1 - a0).normalized()
	var nrm := Vector2(-d.y, d.x)
	if absf((b0 - a0).dot(nrm)) > 1e-3 or absf((b1 - a0).dot(nrm)) > 1e-3:
		return false
	var s0 := (b0 - a0).dot(d)
	var s1 := (b1 - a0).dot(d)
	return minf(a0.distance_to(a1), maxf(s0, s1)) - maxf(0.0, minf(s0, s1)) > 0.02


class _UnionFind:
	var parent: Array = []
	var par: Array = [] # parity to parent

	func _init(n: int) -> void:
		parent.resize(n)
		par.resize(n)
		for i in n:
			parent[i] = i
			par[i] = 0

	func find(x: int) -> int:
		while parent[x] != x:
			x = parent[x]
		return x

	## Parity of x relative to its root.
	func parity(x: int) -> int:
		var p := 0
		while parent[x] != x:
			p ^= par[x]
			x = parent[x]
		return p

	## Requires value(x) xor value(y) == p; false on contradiction.
	func link(x: int, y: int, p: int) -> bool:
		var rx := find(x)
		var ry := find(y)
		var px := parity(x)
		var py := parity(y)
		if rx == ry:
			return (px ^ py) == p
		parent[rx] = ry
		par[rx] = px ^ py ^ p
		return true
