///|
fn square(x : Int32, y : Int32, size : Int32, clockwise : Bool) -> Array[Int32] {
  if clockwise {
    [x, y, x + size, y, x + size, y + size, x, y + size, x, y]
  } else {
    [x, y, x, y + size, x + size, y + size, x + size, y, x, y]
  }
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
test "outline lists each ring's edges, closing an open ring" {
  let out = @tess.FillBuffers::new()
  let fill = @tess.FillTessellator::new()
  // A closed square with a closed hole: 4 + 4 edges.
  let coords = square(0, 0, 100, true) + square(25, 25, 50, false)
  fill.add_polygons(coords[:], [5, 10][:], out)
  assert_eq(out.outline, [0, 1, 1, 2, 2, 3, 3, 4, 5, 6, 6, 7, 7, 8, 8, 9])
  // An open triangle after it: its closing edge is added.
  fill.add_polygons([0, 0, 10, 0, 0, 10][:], [3][:], out)
  assert_eq(out.outline[16:].to_owned(), [10, 11, 11, 12, 12, 10])
  out.clear()
  assert_eq(out.outline.length(), 0)
}

///|
test "add_polygons subdivides on the globe as subdivide_polygon does" {
  let fill = @tess.FillTessellator::new()
  let out = @tess.FillBuffers::new()
  let tri = [1000, 1000, 3000, 7000, 7000, 2000, 1000, 1000]
  fill.add_polygons(tri[:], [4][:], out)
  let flat = out.indices.length()
  out.clear()
  let s = @tess.Subdivider::new()
  let tile = @core.TileId::new(5, 3, 7).unwrap()
  fill.add_polygons(tri[:], [4][:], out, subdivide=(s, 2, tile))
  assert_true(out.indices.length() > flat)
  assert_eq(out.vertices, s.vertices)
  assert_eq(out.indices, s.triangles)
  assert_eq(out.outline, s.lines)
}
