///|
/// Appends a quad per point of `coords` inside `[0, extent)`, as MapLibre keeps
/// them, in the `LINE_VERTEX_STRIDE` layout with extrusions ±`EXTRUDE_SCALE`;
/// the shader sizes it and cuts the circle out.
pub fn add_points(
  coords : ArrayView[Int32],
  out : LineBuffers,
  extent~ : Int32 = 4096,
) -> Unit {
  let s = EXTRUDE_SCALE
  for i in 0..<(coords.length() / 2) {
    let x = coords[i * 2]
    let y = coords[i * 2 + 1]
    if x < 0 || x >= extent || y < 0 || y >= extent {
      continue
    }
    let base = out.num_vertices()
    for corner in [(-s, -s), (s, -s), (s, s), (-s, s)] {
      out.vertices.push(x)
      out.vertices.push(y)
      out.vertices.push(corner.0)
      out.vertices.push(corner.1)
      out.vertices.push(0)
      out.vertices.push(0)
    }
    for k in [0, 1, 2, 0, 2, 3] {
      out.indices.push(base + k)
    }
  }
}
