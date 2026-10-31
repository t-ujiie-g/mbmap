///|
fn square(x : Int32, y : Int32, size : Int32, clockwise : Bool) -> Array[Int32] {
  if clockwise {
    [x, y, x + size, y, x + size, y + size, x, y + size, x, y]
  } else {
    [x, y, x, y + size, x + size, y + size, x + size, y, x, y]
  }
}

///|
test "ring_area is positive for clockwise rings in y-down tile space" {
  let cw = square(0, 0, 10, true)
  assert_eq(@tess.ring_area(cw[:], 0, 5), 200.0)
  let ccw = square(0, 0, 10, false)
  assert_eq(@tess.ring_area(ccw[:], 0, 5), -200.0)
}

///|
test "rings group into polygons with holes and zero-area rings are dropped" {
  // Outer (cw), hole (ccw), a sliver with no area, then a second outer (cw).
  let coords = []
  let ring_ends = []
  for
    ring in [
      square(0, 0, 100, true),
      square(10, 10, 20, false),
      [50, 50, 60, 60, 50, 50],
      square(200, 0, 50, true),
    ] {
    for v in ring {
      coords.push(v)
    }
    ring_ends.push(coords.length() / 2)
  }
  let out = @tess.FillBuffers::new()
  @tess.FillTessellator::new().add_polygons(coords[:], ring_ends[:], out)
  // The sliver's 3 points are not emitted; the two polygons keep their 15.
  assert_eq(out.num_vertices(), 15)
  let mut area = 0.0
  for t = 0; t < out.indices.length(); t = t + 3 {
    let v = out.vertices
    let (a, b, c) = (
      out.indices[t] * 2,
      out.indices[t + 1] * 2,
      out.indices[t + 2] * 2,
    )
    area += ((v[b] - v[a]).to_double() * (v[c + 1] - v[a + 1]).to_double() -
      (v[c] - v[a]).to_double() * (v[b + 1] - v[a + 1]).to_double()).abs() /
      2.0
  }
  assert_eq(area, 100.0 * 100.0 - 20.0 * 20.0 + 50.0 * 50.0)
}

///|
test "indices of later features are offset past earlier vertices" {
  let fill = @tess.FillTessellator::new()
  let out = @tess.FillBuffers::new()
  let a = square(0, 0, 10, true)
  fill.add_polygons(a[:], [5][:], out)
  fill.add_polygons(a[:], [5][:], out)
  assert_eq(out.num_vertices(), 10)
  assert_eq(out.indices.length(), 12)
  for i in 6..<12 {
    assert_true(out.indices[i] >= 5 && out.indices[i] < 10)
  }
  out.clear()
  assert_eq((out.num_vertices(), out.indices.length()), (0, 0))
}

///|
test "only the largest holes are kept beyond MAX_POLYGON_RINGS" {
  let coords = square(0, 0, 100000, true)
  let ring_ends = [5]
  // Holes of growing size; the smallest ones must be dropped.
  let holes = @tess.MAX_POLYGON_RINGS + 9
  for h in 0..<holes {
    let x = h % 100 * 900 + 10
    let y = h / 100 * 900 + 10
    for v in square(x, y, 10 + h % 7, false) {
      coords.push(v)
    }
    ring_ends.push(coords.length() / 2)
  }
  let out = @tess.FillBuffers::new()
  @tess.FillTessellator::new().add_polygons(coords[:], ring_ends[:], out)
  assert_eq(out.num_vertices(), @tess.MAX_POLYGON_RINGS * 5)
}
