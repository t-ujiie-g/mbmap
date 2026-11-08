///|
/// Appends a quad per point of `coords` inside `[0, extent)`, as MapLibre keeps
/// them, in the `LINE_VERTEX_STRIDE` layout with extrusions ±`EXTRUDE_SCALE`;
/// the shader sizes it and cuts the circle out.
pub fn add_points(
  coords : ArrayView[Int32],
  out : LineBuffers,
  extent~ : Int32 = @core.TILE_EXTENT,
  subdivided~ : Bool = false,
) -> Unit {
  let s = EXTRUDE_SCALE
  for i in 0..<(coords.length() / 2) {
    let x = coords[i * 2]
    let y = coords[i * 2 + 1]
    if x < 0 || x >= extent || y < 0 || y >= extent {
      continue
    }
    let base = out.num_vertices()
    if subdivided {
      grid(out, x, y, base)
      continue
    }
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

///|
/// A point's quad as 3 x 3 quads, as MapLibre's circle bucket cuts it on the
/// globe (`CIRCLE_GRANULARITY`, extrudes 0, 2, 5 and 7 of 7).
fn grid(out : LineBuffers, x : Int32, y : Int32, base : Int32) -> Unit {
  let steps : FixedArray[Int32] = [0, 2, 5, 7]
  let e = (k : Int32) => {
    (EXTRUDE_SCALE.to_double() * (k.to_double() / 7.0 * 2.0 - 1.0))
    .round()
    .to_int()
  }
  for row in 0..<4 {
    for col in 0..<4 {
      corner(out.vertices, x, y, e(steps[col]), e(steps[row]))
    }
  }
  for row in 0..<3 {
    for col in 0..<3 {
      let lower = base + row * 4 + col
      let upper = base + (row + 1) * 4 + col
      out.indices.push(lower)
      out.indices.push(upper + 1)
      out.indices.push(lower + 1)
      out.indices.push(lower)
      out.indices.push(upper)
      out.indices.push(upper + 1)
    }
  }
}
