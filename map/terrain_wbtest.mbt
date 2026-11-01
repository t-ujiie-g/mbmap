///|
test "texture_placement maps a tile and its child into the terrain texture" {
  let at : @render_webgl2.Placement = {
    matrix: @core.Mat4::identity(),
    units_per_pixel: 1.0,
    center_depth: 1.0,
    clip: [0.0, 0.0, 4096.0, 4096.0],
    latitudes: (0.0, 0.0),
  }
  let into = @core.TileId::new(10, 4, 6).unwrap()
  let e = @core.TILE_EXTENT.to_double()
  let own = texture_placement({ id: into, at, meshes: [], }, into, 1024)
  assert_eq(own.matrix.apply(0.0, 0.0, 0.0, 1.0), (-1.0, 1.0, 0.0, 1.0))
  assert_eq(own.matrix.apply(e, e, 0.0, 1.0), (1.0, -1.0, 0.0, 1.0))
  assert_eq(own.units_per_pixel, 4.0)
  // The child's bottom-right quarter: x 1, y 1 at z 11.
  let kid = @core.TileId::new(11, 9, 13).unwrap()
  let k = texture_placement({ id: kid, at, meshes: [], }, into, 1024)
  assert_eq(k.matrix.apply(0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0))
  assert_eq(k.matrix.apply(e, e, 0.0, 1.0), (1.0, -1.0, 0.0, 1.0))
  assert_eq(k.units_per_pixel, 8.0)
  assert_true(overlap(kid, into) && overlap(into, kid))
  assert_true(!overlap(@core.TileId::new(11, 7, 13).unwrap(), into))
}
