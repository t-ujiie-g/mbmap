///|
let subdivider : @tess.Subdivider = @tess.Subdivider::new()

///|
fn ints(a : FixedArray[Double]) -> Array[Int32] {
  Array::makei(a.length(), i => a[i].to_int())
}

///|
fn joined_ints(a : ArrayView[Int32]) -> String {
  a.iter().map(v => v.to_string()).join(",")
}

///|
/// `Subdivider::subdivide_polygon` of one polygon's x, y pairs and ring ends, in
/// the tile `z`/`x`/`y` (none when `z` < 0): "fail", or the vertices, the
/// triangles and each ring's lines (joined by ";"), separated by "|".
#export_name("subdivide_polygon")
pub fn subdivide_polygon(
  coords : FixedArray[Double],
  ring_ends : FixedArray[Double],
  granularity : Int32,
  z : Int32,
  x : Int32,
  y : Int32,
  outline : Bool,
) -> String {
  let s = subdivider
  let canonical = if z < 0 { None } else { @core.TileId::new(z, x, y) }
  let ok = s.subdivide_polygon(
    ints(coords)[:],
    ints(ring_ends)[:],
    granularity,
    canonical?,
    outline~,
  )
  if !ok {
    return "fail"
  }
  let rings = []
  let mut start = 0
  for end in s.line_ends {
    rings.push(joined_ints(s.lines[start:end]))
    start = end
  }
  "\{joined_ints(s.vertices[:])}|\{joined_ints(s.triangles[:])}|\{rings.join(";")}"
}

///|
/// `@tess.subdivide_vertex_line` of the x, y pairs in `points`, comma separated.
#export_name("subdivide_vertex_line")
pub fn subdivide_vertex_line(
  points : FixedArray[Double],
  granularity : Int32,
  is_ring : Bool,
) -> String {
  let out = []
  @tess.subdivide_vertex_line(ints(points)[:], granularity, out, is_ring~)
  joined_ints(out[:])
}

///|
/// `@tess.granularity_for_zoom`, `fill_granularity` and `line_granularity` at
/// zoom `z`, comma separated.
#export_name("subdivision_granularity")
pub fn subdivision_granularity(base : Int32, min : Int32, z : Int32) -> String {
  "\{@tess.granularity_for_zoom(base, min, z)},\{@tess.fill_granularity(z)},\{@tess.line_granularity(z)}"
}
