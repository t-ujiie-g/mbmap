///|
/// Each ring's lines of `s`.
fn ring_lines(s : @tess.Subdivider) -> Array[Array[Int32]] {
  let out = []
  let mut start = 0
  for end in s.line_ends {
    out.push(s.lines[start:end].to_owned())
    start = end
  }
  out
}

///|
test "subdivide_polygon cuts a triangle across cells as MapLibre does" {
  let s = @tess.Subdivider::new()
  assert_true(s.subdivide_polygon([1000, 1000, 7000, 2000, 3000, 7000], [3], 2))
  assert_eq(s.vertices, [
    1000, 1000, 7000, 2000, 3000, 7000, 5323, 4096, 4096, 4096, 2032, 4096, 4096,
    1516, 4096, 5630,
  ])
  assert_eq(s.triangles, [
    6, 0, 5, 6, 5, 4, 6, 4, 3, 6, 3, 1, 4, 5, 2, 4, 2, 7, 4, 7, 3,
  ])
  assert_eq(ring_lines(s), [[0, 6, 6, 1, 1, 3, 3, 7, 7, 2, 2, 5, 5, 0]])
  // Reuse gives the same result.
  assert_true(s.subdivide_polygon([1000, 1000, 7000, 2000, 3000, 7000], [3], 2))
  assert_eq(s.triangles.length(), 21)
  assert_eq(s.vertices.length(), 16)
}

///|
test "subdivide_polygon below granularity 2 only turns triangles counter-clockwise" {
  let s = @tess.Subdivider::new()
  assert_true(s.subdivide_polygon([0, 0, 100, 0, 0, 100], [3], 1))
  assert_eq(s.vertices, [0, 0, 100, 0, 0, 100])
  assert_eq(s.triangles, [1, 0, 2])
  assert_eq(ring_lines(s), [[0, 1, 1, 2, 2, 0]])
  assert_true(
    s.subdivide_polygon([0, 0, 100, 0, 0, 100], [3], 1, outline=false),
  )
  assert_eq(s.lines, [])
  assert_eq(s.line_ends, [])
}

///|
test "subdivide_polygon extends the top row of tiles to the north pole" {
  let s = @tess.Subdivider::new()
  let tile = @core.TileId::new(3, 1, 0).unwrap()
  assert_true(
    s.subdivide_polygon(
      [0, 0, 8192, 0, 8192, 4000, 0, 4000],
      [4],
      1,
      canonical=tile,
    ),
  )
  assert_eq(s.vertices, [
    0, 0, 8192, 0, 8192, 4000, 0, 4000, 8192, -32768, 0, -32768,
  ])
  assert_eq(s.triangles, [2, 0, 3, 2, 1, 0, 0, 1, 4, 5, 0, 4])
  assert_eq(ring_lines(s), [[0, 1, 1, 2, 2, 3, 3, 0]])
}

///|
test "subdivide_polygon at zoom 0 drops what lies beyond the tile's x range" {
  let s = @tess.Subdivider::new()
  let tile = @core.TileId::new(0, 0, 0).unwrap()
  assert_true(
    s.subdivide_polygon(
      [-100, 0, 8192, 0, 8192, 4000, -100, 4000],
      [4],
      2,
      canonical=tile,
    ),
  )
  assert_eq(s.vertices, [
    -100, 0, 8192, 0, 8192, 4000, -100, 4000, 4096, 4000, 0, 4000, 0, 48, 4096, 2024,
    0, 0, 4096, 0, 0, -32768, -100, -32768, 4096, -32768, 8192, -32768,
  ])
  assert_eq(s.triangles, [
    6, 5, 7, 7, 5, 4, 7, 4, 2, 8, 6, 9, 9, 6, 7, 9, 7, 1, 1, 7, 2, 8, 9, 12, 10,
    8, 12, 9, 1, 13, 12, 9, 13,
  ])
  assert_eq(ring_lines(s), [[8, 9, 9, 1, 1, 2, 2, 4, 4, 5]])
}

///|
test "subdivide_polygon fails on vertices out of Int16" {
  let s = @tess.Subdivider::new()
  assert_false(s.subdivide_polygon([0, 0, 40000, 0, 0, 100], [3], 4))
  assert_false(s.subdivide_polygon([0, 0, 100, -32769, 0, 100], [3], 1))
}

///|
test "subdivide_vertex_line cuts at cell edges and closes rings" {
  let out = []
  @tess.subdivide_vertex_line([0, 0, 8, 0, 0, 8], 8192 / 4, out, is_ring=true)
  assert_eq(out, [0, 0, 4, 0, 8, 0, 4, 4, 0, 8, 0, 4, 0, 0])
  out.clear()
  @tess.subdivide_vertex_line([100, 100, 5000, 3000], 4, out)
  assert_eq(out, [100, 100, 2048, 1253, 3391, 2048, 4096, 2465, 5000, 3000])
  out.clear()
  @tess.subdivide_vertex_line([0, 0, 8, 0, 0, 8], 1, out, is_ring=true)
  assert_eq(out, [0, 0, 8, 0, 0, 8, 0, 0])
  out.clear()
  @tess.subdivide_vertex_line([5, 5], 64, out)
  assert_eq(out, [])
}

///|
test "granularity_for_zoom halves per zoom down to its minimum" {
  assert_eq([0, 1, 6, 7, 14, 32].map(@tess.fill_granularity), [
    128, 64, 2, 2, 2, 128,
  ])
  assert_eq([0, 1, 9, 10, 20].map(@tess.line_granularity), [512, 256, 1, 1, 1])
  assert_eq(@tess.granularity_for_zoom(128, 32, 3), 32)
  assert_eq(@tess.granularity_for_zoom(0, 0, 0), 1)
  assert_eq(@tess.CIRCLE_GRANULARITY, 3)
}
