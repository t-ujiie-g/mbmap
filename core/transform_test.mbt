///|
fn tokyo() -> @core.Camera {
  { center: { lng: 139.7671, lat: 35.6812, }, zoom: 14.0, }
}

///|
fn close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-6
}

///|
test "the screen center is the camera center and round-trips" {
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let m = t.screen_to_mercator(400.0, 300.0)
  let c = tokyo().center.to_mercator()
  assert_true(close(m.x, c.x) && close(m.y, c.y))
  let (x, y) = t.mercator_to_screen(t.screen_to_mercator(123.0, 456.0))
  assert_true(close(x, 123.0) && close(y, 456.0))
  assert_eq(t.world_size(), 512.0 * 16384.0)
}

///|
test "panning moves the map under the pointer by the drag distance" {
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let before = t.screen_to_mercator(100.0, 100.0)
  let moved = t.with_camera(t.panned(30.0, -20.0))
  let (x, y) = moved.mercator_to_screen(before)
  assert_true(close(x, 130.0) && close(y, 80.0))
}

///|
test "zooming around a point keeps that point fixed" {
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let anchor = t.screen_to_mercator(700.0, 50.0)
  let zoomed = t.with_camera(t.zoomed_around(700.0, 50.0, 15.5))
  assert_eq(zoomed.camera.zoom, 15.5)
  let (x, y) = zoomed.mercator_to_screen(anchor)
  assert_true(close(x, 700.0) && close(y, 50.0))
}

///|
test "zoom and latitude are constrained, longitude wraps" {
  let t = @core.Transform::new(
    { center: { lng: 190.0, lat: 89.0, }, zoom: 30.0, },
    100.0,
    100.0,
    min_zoom=2.0,
    max_zoom=20.0,
  )
  assert_eq(t.camera.zoom, 20.0)
  assert_eq(t.camera.center.lat, @core.MAX_LATITUDE)
  assert_true(close(t.camera.center.lng, -170.0))
  assert_eq(t.with_camera({ ..t.camera, zoom: -3.0, }).camera.zoom, 2.0)
}

///|
test "tile_zoom floors the camera zoom into the source range" {
  let t = @core.Transform::new({ ..tokyo(), zoom: 14.7, }, 800.0, 600.0)
  assert_eq(t.tile_zoom(0, 22), 14)
  assert_eq(t.tile_zoom(0, 12), 12)
  assert_eq(t.tile_zoom(15, 18), 15)
}

///|
test "covering tiles span the viewport, nearest first" {
  // At zoom 14 a 512 px tile is 512 CSS px: an 800 x 600 view sees 2-3 tiles a side.
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let tiles = t.covering_tiles(14)
  let center = @core.tile_containing(tokyo().center.to_mercator(), 14).unwrap()
  assert_eq(tiles[0], center)
  for tile in tiles {
    let b = tile.mercator_bounds()
    let (x0, y0) = t.mercator_to_screen({ x: b.min_x, y: b.min_y, })
    let (x1, y1) = t.mercator_to_screen({ x: b.max_x, y: b.max_y, })
    assert_true(x1 > 0.0 && x0 < 800.0 && y1 > 0.0 && y0 < 600.0)
  }
  assert_true(tiles.length() >= 4 && tiles.length() <= 9)
}

///|
test "tile_transform maps the tile's corners to their clip positions" {
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let tile = @core.TileId::new(14, 14552, 6451).unwrap()
  let tt = t.tile_transform(tile, 4096)
  let b = tile.mercator_bounds()
  for corner in [(0, 0, b.min_x, b.min_y), (4096, 4096, b.max_x, b.max_y)] {
    let (u, v, mx, my) = corner
    let (sx, sy) = t.mercator_to_screen({ x: mx, y: my, })
    let clip_x = u.to_double() * tt.scale_x + tt.translate_x
    let clip_y = v.to_double() * tt.scale_y + tt.translate_y
    assert_true(close(clip_x, sx / 400.0 - 1.0))
    assert_true(close(clip_y, 1.0 - sy / 300.0))
  }
}

///|
test "cameras with NaN or infinite values are ignored" {
  let camera : @core.Camera = {
    center: { lng: 139.0, lat: 35.0, },
    zoom: 10.0,
  }
  let t = @core.Transform::new(camera, 100.0, 100.0)
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  let cameras : Array[@core.Camera] = [
    { center: { lng: nan, lat: 0.0, }, zoom: 1.0, },
    { center: { lng: 0.0, lat: -inf, }, zoom: 1.0, },
    { center: { lng: 0.0, lat: 0.0, }, zoom: nan, },
  ]
  for bad in cameras {
    assert_eq(t.with_camera(bad).camera, camera)
    assert_eq(@core.Transform::new(bad, 100.0, 100.0).camera, {
      center: { lng: 0.0, lat: 0.0, },
      zoom: 0.0,
    })
  }
}
