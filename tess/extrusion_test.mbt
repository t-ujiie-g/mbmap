///|
test "a square building gets four walls facing out and a roof" {
  // Clockwise in tile coordinates (y down), as MVT outer rings are.
  let coords = [100, 100, 200, 100, 200, 200, 100, 200]
  let out = @tess.ExtrusionBuffers::new()
  let heights : FixedArray[Double] = [0.0, 0.0, 30.0, 31.0]
  @tess.ExtrusionTessellator::new().add_polygons(
    coords[:],
    [4][:],
    heights,
    out,
  )
  let s = @tess.EXTRUSION_VERTEX_STRIDE
  // 4 walls of 4 vertices and 2 triangles, then the roof's 4 and 2.
  assert_eq((out.num_vertices(), out.indices.length()), (20, 30))
  assert_eq(out.heights.length(), 20 * @tess.EXTRUSION_HEIGHTS)
  assert_eq(out.heights[3], 31.0)
  let v = (i : Int32, k : Int32) => out.vertices[i * s + k]
  // The first wall runs from (200, 100) back to (100, 100), the north side,
  // bottom then top edge. MapLibre's normal is the edge direction turned by
  // +90° in tile coordinates: +y, into a clockwise ring.
  assert_eq(
    (v(0, 0), v(0, 1), v(0, 2), v(0, 3), v(0, 4)),
    (200, 100, 0, 16384, 0),
  )
  assert_eq(v(1, 2), 1)
  assert_eq((v(2, 0), v(2, 1)), (100, 100))
  // The last wall closes the ring, from (100, 100) back to (100, 200): +x.
  assert_eq((v(12, 0), v(12, 1), v(12, 2), v(12, 3)), (100, 100, 16384, 0))
  // Distances along the walls: each wall starts where the last ended.
  assert_eq((v(0, 5), v(2, 5), v(4, 5), v(14, 5)), (0, 100, 100, 400))
  // Roof vertices point up and sit on the top edge, at distance 0; every
  // vertex knows the centroid.
  assert_eq(
    (v(16, 2), v(16, 4), v(16, 5), v(16, 6), v(16, 7)),
    (1, 16384, 0, 150, 150),
  )
  // Each wall's triangles: 0 2 1 and 1 2 3.
  assert_eq(out.indices[:6].to_owned(), [0, 2, 1, 1, 2, 3])
}

///|
test "walls along the tile's cut lines and rings off the tile are skipped" {
  // A building cut at x = -64 (outside the tile): its west wall is the
  // neighbor's. A second ring lies wholly beyond the right edge.
  let coords = [
    -64, 100, 50, 100, 50, 200, -64, 200, 9000, 0, 9100, 0, 9100, 50,
  ]
  let out = @tess.ExtrusionBuffers::new()
  @tess.ExtrusionTessellator::new().add_polygons(
    coords[:],
    [4, 7][:],
    [0.0, 0.0, 10.0, 10.0],
    out,
  )
  // 3 walls of the first ring (4 vertices, 6 indices each); roofs are
  // triangulated for both polygons (4 + 3 vertices, 2 + 1 triangles).
  assert_eq((out.num_vertices(), out.indices.length()), (3 * 4 + 7, 3 * 6 + 9))
}

///|
test "closed rings add no zero-length wall and count their first point once" {
  let coords = [100, 100, 200, 100, 200, 200, 100, 200, 100, 100]
  let out = @tess.ExtrusionBuffers::new()
  @tess.ExtrusionTessellator::new().add_polygons(
    coords[:],
    [5][:],
    [0.0, 0.0, 10.0, 10.0],
    out,
  )
  assert_eq(out.indices.length(), 4 * 6 + 2 * 3)
  assert_eq((out.vertices[6], out.vertices[7]), (150, 150))
}

///|
test "wall distances are rounded in 8192 units whatever the source extent" {
  // A 1-by-3 triangle in a 512-unit tile: edges of 1, 3 and sqrt(10) units.
  let out = @tess.ExtrusionBuffers::new()
  @tess.ExtrusionTessellator::new().add_polygons(
    [100, 100, 101, 100, 101, 103][:],
    [3][:],
    [0.0, 0.0, 10.0, 10.0],
    out,
    extent=512,
  )
  let s = @tess.EXTRUSION_VERTEX_STRIDE
  // 16 units per source unit: 16, 64, then round(64 + 16 * sqrt(10)) = 115.
  assert_eq(
    (out.vertices[2 * s + 5], out.vertices[6 * s + 5], out.vertices[10 * s + 5]),
    (16, 64, 115),
  )
}
