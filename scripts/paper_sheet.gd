class_name PaperSheet
extends Node2D
## A big sheet of paper that can be folded.
##
## The sheet is stored as a list of flat convex "facets" (polygons in sheet-local
## space). Each facet has a stacking `layer` and a `flipped` flag (showing the
## back side of the paper). Folding along a line splits every facet by that line
## and mirrors everything on the grabbed side across it, onto the top of the
## stack. Because the result is just a new list of facets, folds are permanent
## until undone, and the whole sheet can be moved by changing `position`.

const MIN_FOLD_LENGTH := 30.0
const HANDLE_MERGE_DIST := 10.0
const LAYER_PX := 22.0 ## on-screen lift per stacked layer

const FRONT_COLOR := Color(0.97, 0.95, 0.86)
const BACK_COLOR := Color(0.72, 0.84, 0.96)
const EDGE_COLOR := Color(0.25, 0.22, 0.2, 0.9)


class Facet:
	var pts: PackedVector2Array
	var layer: int
	var flipped: bool

	func _init(p: PackedVector2Array, l: int, f: bool) -> void:
		pts = p
		layer = l
		flipped = f

	func clone() -> Facet:
		return Facet.new(pts.duplicate(), layer, flipped)


var paper_size := Vector2(1000, 700)
var facets: Array = [] ## Array[Facet]
var fold_owner = null ## the player currently dragging a fold, if any

var _history: Array = [] ## snapshots (Array[Array[Facet]]) for undo
var _preview: Array = []
var _preview_active := false
var _preview_g := Vector2.ZERO
var _preview_c := Vector2.ZERO


func setup(size: Vector2) -> void:
	paper_size = size
	reset_paper()


func reset_paper() -> void:
	var h := paper_size * 0.5
	var rect := PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)
	])
	facets = [Facet.new(rect, 0, false)]
	_history.clear()
	cancel_fold()


# --- Folding ---------------------------------------------------------------

## Returns a new facet list where everything on g's side of the fold line has
## been mirrored over it, so that g lands on c. `src` is left untouched.
static func fold_facets(src: Array, g: Vector2, c: Vector2) -> Array:
	var d := c - g
	if d.length() < 0.001:
		return clone_facets(src)
	var n := d.normalized()
	var mid := (g + c) * 0.5
	var top := 0
	for item in src:
		var f: Facet = item
		top = maxi(top, f.layer)

	var out: Array = []
	var flap: Array = []
	for item in src:
		var f: Facet = item
		var keep := PaperGeometry.clip_half_plane(f.pts, mid, n, true)
		if keep.size() >= 3:
			out.append(Facet.new(keep, f.layer, f.flipped))
		var moving := PaperGeometry.clip_half_plane(f.pts, mid, n, false)
		if moving.size() >= 3:
			var mirrored := PackedVector2Array()
			for p in moving:
				var s := (p - mid).dot(n)
				mirrored.append(p - 2.0 * s * n)
			mirrored.reverse() # keep winding consistent after mirroring
			# Flipping a stack reverses its order and lays it above everything.
			flap.append(Facet.new(mirrored, top + 1 + (top - f.layer), not f.flipped))
	out.append_array(flap)
	out.sort_custom(func(a: Facet, b: Facet) -> bool: return a.layer < b.layer)
	for i in out.size():
		(out[i] as Facet).layer = i
	return out


static func clone_facets(src: Array) -> Array:
	var out: Array = []
	for item in src:
		out.append((item as Facet).clone())
	return out


func begin_fold(owner) -> bool:
	if fold_owner != null:
		return false
	fold_owner = owner
	return true


func update_preview(g: Vector2, c: Vector2) -> void:
	_preview_g = g
	_preview_c = c
	_preview_active = (c - g).length() >= MIN_FOLD_LENGTH
	_preview = fold_facets(facets, g, c) if _preview_active else []


func finish_fold(g: Vector2, c: Vector2) -> bool:
	var committed := false
	if (c - g).length() >= MIN_FOLD_LENGTH:
		_history.append(clone_facets(facets))
		facets = fold_facets(facets, g, c)
		committed = true
	cancel_fold()
	return committed


func cancel_fold() -> void:
	fold_owner = null
	_preview_active = false
	_preview = []


func undo() -> void:
	if fold_owner != null or _history.is_empty():
		return
	facets = _history.pop_back()


# --- Queries ---------------------------------------------------------------

## Number of paper layers covering a sheet-local point (0 = no paper).
func height_at(local: Vector2) -> int:
	var count := 0
	for item in facets:
		if Geometry2D.is_point_in_polygon(local, (item as Facet).pts):
			count += 1
	return count


## Grabbable points: every facet corner and edge midpoint that is not buried
## under a higher layer. Returns Array of {pos: Vector2, layer: int}.
func get_handles() -> Array:
	var handles: Array = []
	for item in facets:
		var f: Facet = item
		var n := f.pts.size()
		for i in n:
			var a := f.pts[i]
			var b := f.pts[(i + 1) % n]
			_add_handle(handles, a, f.layer)
			_add_handle(handles, (a + b) * 0.5, f.layer)
	return handles


func _add_handle(handles: Array, p: Vector2, layer: int) -> void:
	for item in facets:
		var other: Facet = item
		if other.layer > layer and Geometry2D.is_point_in_polygon(p, other.pts):
			return
	for h in handles:
		if (h.pos as Vector2).distance_to(p) < HANDLE_MERGE_DIST:
			if layer > h.layer:
				h.pos = p
				h.layer = layer
			return
	handles.append({"pos": p, "layer": layer})


## Closest grabbable point to `local` within `radius`, or null.
func nearest_handle(local: Vector2, radius: float):
	var best = null
	var best_d := radius
	var best_layer := -1
	for h in get_handles():
		var d := (h.pos as Vector2).distance_to(local)
		if d < best_d - 0.5 or (absf(d - best_d) <= 0.5 and h.layer > best_layer):
			best = h.pos
			best_d = d
			best_layer = h.layer
	return best


# --- Drawing ---------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var list := _preview if _preview_active else facets
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: Facet, b: Facet) -> bool: return a.layer < b.layer)
	var total := maxi(sorted.size() - 1, 1)

	for item in sorted:
		var f: Facet = item
		# How many facets lie underneath decides how far this one is lifted.
		var below := 0
		var cen := PaperGeometry.centroid(f.pts)
		for other_item in sorted:
			var other: Facet = other_item
			if other.layer < f.layer and Geometry2D.is_point_in_polygon(cen, other.pts):
				below += 1
		var lift := Vector2(0, -(below + 1) * LAYER_PX)

		var side := _shifted(f.pts, lift + Vector2(0, LAYER_PX * 0.8))
		draw_colored_polygon(side, Color(0.35, 0.33, 0.3, 0.9))
		var top := _shifted(f.pts, lift)
		var base := BACK_COLOR if f.flipped else FRONT_COLOR
		var t := float(f.layer) / float(total)
		draw_colored_polygon(top, base.darkened(0.18 * (1.0 - t)))
		var outline := top.duplicate()
		outline.append(top[0])
		draw_polyline(outline, EDGE_COLOR, 2.0)

	if _preview_active:
		var dir := (_preview_c - _preview_g).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var mid := (_preview_g + _preview_c) * 0.5
		draw_dashed_line(mid - perp * 900.0, mid + perp * 900.0, Color(1, 0.4, 0.2, 0.9), 3.0, 14.0)
		draw_circle(_preview_g, 8.0, Color(1, 0.4, 0.2))


static func _shifted(pts: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + offset)
	return out
