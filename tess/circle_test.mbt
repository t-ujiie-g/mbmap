///|
test "add_points makes one quad per point inside the tile" {
  let out = @tess.LineBuffers::new()
  // The second point is on the far edge, the third outside: both skipped.
  let e = @core.TILE_EXTENT
  @tess.add_points([10, 20, e, 5, -1, 7, e - 1, 0][:], out)
  assert_eq(out.num_vertices(), 8)
  assert_eq(out.indices, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
  let s = @tess.EXTRUDE_SCALE
  assert_eq(out.vertices[0:6].to_owned(), [10, 20, -s, -s, 0, 0])
  assert_eq(out.vertices[12:18].to_owned(), [10, 20, s, s, 0, 0])
  assert_eq(out.vertices[24:26].to_owned(), [e - 1, 0])
  @tess.add_points([100, 100][:], out, extent=64)
  assert_eq(out.num_vertices(), 8)
}
