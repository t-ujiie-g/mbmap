///|
test "texture_placement maps a tile and its child into the terrain texture" {
  let at : @render_webgl2.Placement = {
    matrix: @core.Mat4::identity(),
    raster_matrix: @core.Mat4::identity(),
    units_per_pixel: 1.0,
    center_depth: 1.0,
    clip: [0.0, 0.0, 4096.0, 4096.0],
    latitudes: (0.0, 0.0),
    pattern: { x: 0.0, y: 0.0, units: 1.0, },
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

///|
extern "js" fn f32_buffer(
  values : FixedArray[Double],
) -> @render_webgl2.JsBuffer =
  #|(v) => Float32Array.from(v)

///|
test "height_at interpolates between pixel centers like the terrain shader" {
  // 2 x 2 pixels: 0 and 100 m on the top row, 200 and 300 m below.
  let d : DemTile = {
    edges: [],
    heights: f32_buffer([0.0, 100.0, 200.0, 300.0]),
    size: 2,
    lowest: 0.0,
    highest: 300.0,
  }
  // Pixel centers sit at 1/4 and 3/4; the tile's middle is their average.
  assert_eq(d.height_at(0.25, 0.25), 0.0)
  assert_eq(d.height_at(0.75, 0.75), 300.0)
  assert_eq(d.height_at(0.5, 0.5), 150.0)
  assert_eq(d.height_at(0.5, 0.25), 50.0)
  // Beyond the outer centers the edge pixels repeat.
  assert_eq(d.height_at(0.0, 0.0), 0.0)
  assert_eq(d.height_at(1.0, 1.0), 300.0)
}

///|
test "height_at reads a neighbor's pixels past the outer centers" {
  let own : DemTile = {
    edges: [],
    heights: f32_buffer([0.0, 100.0, 200.0, 300.0]),
    size: 2,
    lowest: 0.0,
    highest: 300.0,
  }
  let right : DemTile = {
    edges: [],
    heights: f32_buffer([500.0, 0.0, 700.0, 0.0]),
    size: 2,
    lowest: 0.0,
    highest: 700.0,
  }
  let neighbor = (dx : Int32, dy : Int32) => {
    if dx == 1 && dy == 0 {
      Some(right)
    } else {
      None
    }
  }
  // Halfway between this tile's last center and the right tile's first.
  assert_eq(own.height_at(1.0, 0.25, neighbor~), 300.0)
  assert_eq(own.height_at(1.0, 0.75, neighbor~), 500.0)
  // No neighbor below: the edge row repeats.
  assert_eq(own.height_at(0.75, 1.0, neighbor~), 300.0)
}
