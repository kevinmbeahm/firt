class_name PaperGeometry
extends RefCounted
## Pure 2D polygon helpers used by the paper folding code (units: metres).

const MIN_AREA := 0.02 ## square metres
const MERGE_DIST := 0.001


## Clips a convex polygon against the half plane (p - origin) . normal >= 0
## (or <= 0 when keep_positive is false). Returns an empty array when the
## result is degenerate.
static func clip_half_plane(poly: PackedVector2Array, origin: Vector2, normal: Vector2, keep_positive: bool,
		min_area: float = MIN_AREA) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	if count < 3:
		return out
	var sgn := 1.0 if keep_positive else -1.0
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := (a - origin).dot(normal) * sgn
		var db := (b - origin).dot(normal) * sgn
		if da >= 0.0:
			out.append(a)
		if (da > 0.0 and db < 0.0) or (da < 0.0 and db > 0.0):
			out.append(a + (b - a) * (da / (da - db)))
	return _clean(out, min_area)


static func signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Total area where two convex polygons overlap.
static func overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var total := 0.0
	for poly in Geometry2D.intersect_polygons(a, b):
		total += absf(signed_area(poly))
	return total


static func centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(max(poly.size(), 1))


## Removes repeated points and polygons too small to matter.
static func _clean(poly: PackedVector2Array, min_area: float = MIN_AREA) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > MERGE_DIST:
			out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= MERGE_DIST:
		out.remove_at(out.size() - 1)
	# Drop corners that sit on a straight edge (left over from earlier cuts):
	# they'd make one paper edge look like several.
	var i := 0
	while out.size() > 3 and i < out.size():
		var prev := out[(i - 1 + out.size()) % out.size()]
		var next := out[(i + 1) % out.size()]
		var span := next - prev
		if span.length() > 1e-6 and absf(span.normalized().cross(out[i] - prev)) < 1e-4:
			out.remove_at(i)
		else:
			i += 1
	if out.size() < 3 or absf(signed_area(out)) < min_area:
		return PackedVector2Array()
	return out


## The polygon with duplicate and collinear corners removed (keeps it however
## small it is).
static func tidy(poly: PackedVector2Array) -> PackedVector2Array:
	var out := _clean(poly, 0.0)
	return out if out.size() >= 3 else poly


## The polygon pulled in toward its centroid by `d` (convex polygons only).
static func inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var c := centroid(poly)
	var out := PackedVector2Array()
	for p in poly:
		var to_c := c - p
		out.append(p + to_c.normalized() * minf(d, to_c.length() * 0.5))
	return out
