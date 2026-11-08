// Expected values come from MapLibre GL JS 6.16.0's GlobeTransform (800 x 600 at Tokyo, bearing 30,
// pitch 40; tile 3/7/3).

///|
fn tilted_globe(zoom : Double) -> @globe.Globe {
  @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom,
      bearing: 30.0,
      pitch: 40.0,
    },
    800.0,
    600.0,
  )
}

///|
test "project_tile gives MapLibre's projectTileCoordinates on the globe" {
  let id = @core.TileId::new(3, 7, 3).unwrap()
  let g = tilted_globe(3.0)
  let (cx, cy, cw, hidden) = g.project_tile(1000.0, 7000.0, id)
  assert_true(near(cx / cw, 0.6016579540488685, tol=1.0e-9))
  assert_true(near(cy / cw, -1.2603700875712414, tol=1.0e-9))
  assert_true(near(cw, 763.5610653668857, tol=1.0e-7))
  assert_false(hidden)
  let (cx, cy, cw, _) = g.project_tile(8000.0, 8000.0, id)
  assert_true(near(cx / cw, 1.2697008176262912, tol=1.0e-9))
  assert_true(near(cy / cw, -0.6175845453880755, tol=1.0e-9))
  assert_true(near(cw, 1088.7799118155056, tol=1.0e-7))
}

///|
test "project_tile marks points past the horizon hidden" {
  let id = @core.TileId::new(3, 7, 3).unwrap()
  let g = tilted_globe(11.5)
  let (cx, _, cw, hidden) = g.project_tile(4000.0, 500.0, id)
  assert_true(near(cx / cw, 2.552557881466046, tol=1.0e-8))
  assert_true(near(cw, 41344.6462987946, tol=1.0e-5))
  assert_true(hidden)
}

///|
test "pitched text correction and radius correction follow MapLibre" {
  let id = @core.TileId::new(3, 7, 3).unwrap()
  let g = tilted_globe(3.0)
  assert_true(near(g.radius_correction(), 0.812274955822932))
  assert_true(near(g.pitched_text_correction(7000.0, id), 0.8175849992095882))
  assert_true(near(g.pitched_text_correction(500.0, id), 1.0433460439213125))
  // Halfway into mercator the correction is halfway to 1.
  let h = tilted_globe(11.5)
  assert_true(near(h.pitched_text_correction(7000.0, id), 0.908792499604794))
  assert_true(near(h.radius_correction(), 0.812274955822932))
}

///|
test "radius correction is 1 once drawn flat" {
  assert_eq(tilted_globe(13.0).radius_correction(), 1.0)
}

///|
test "tile_wrap puts tiles across the antimeridian on the nearer world copy" {
  let g = tilted_globe(1.6)
  assert_eq(g.tile_wrap(@core.TileId::new(1, 1, 0).unwrap()), 0)
  assert_eq(g.tile_wrap(@core.TileId::new(1, 0, 1).unwrap()), 1)
  let west = @globe.Globe::new(
    { center: { lng: -150.0, lat: 0.0, }, zoom: 2.0, bearing: 0.0, pitch: 0.0, },
    800.0,
    600.0,
  )
  assert_eq(west.tile_wrap(@core.TileId::new(2, 3, 1).unwrap()), -1)
  assert_eq(west.tile_wrap(@core.TileId::new(2, 0, 1).unwrap()), 0)
}
