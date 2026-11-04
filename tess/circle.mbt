///|
/// Appends a quad per point of `coords` inside `[0, extent)`, as MapLibre keeps
/// them, in the `LINE_VERTEX_STRIDE` layout with extrusions ±`EXTRUDE_SCALE`;
/// the shader sizes it and cuts the circle out.
pub fn add_points(
  coords : ArrayView[Int32],
  out : LineBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Unit {
  let s = EXTRUDE_SCALE
  for i in 0..<(coords.length() / 2) {
    let x = coords[i * 2]
    let y = coords[i * 2 + 1]
    if x < 0 || x >= extent || y < 0 || y >= extent {
      continue
    }
    let base = out.num_vertices()
    corner(out.vertices, x, y, -s, -s)
    corner(out.vertices, x, y, s, -s)
    corner(out.vertices, x, y, s, s)
    corner(out.vertices, x, y, -s, s)
    let i = out.indices
    i.push(base)
    i.push(base + 1)
    i.push(base + 2)
    i.push(base)
    i.push(base + 2)
    i.push(base + 3)
  }
}

///|
fn corner(
  v : Array[Int32],
  x : Int32,
  y : Int32,
  ex : Int32,
  ey : Int32,
) -> Unit {
  v.push(x)
  v.push(y)
  v.push(ex)
  v.push(ey)
  v.push(0)
  v.push(0)
}
