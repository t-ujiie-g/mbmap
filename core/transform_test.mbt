///|
fn tokyo() -> @core.Camera {
  {
    center: { lng: 139.7671, lat: 35.6812, },
    zoom: 14.0,
    bearing: 0.0,
    pitch: 0.0,
  }
}

///|
fn close(a : Double, b : Double) -> Bool {
  (a - b).abs() < 1.0e-6
}

///|
/// Cameras every view test runs with: flat, rotated, pitched, both.
fn views() -> Array[@core.Camera] {
  [
    tokyo(),
    { ..tokyo(), bearing: 30.0, },
    { ..tokyo(), pitch: 45.0, },
    { ..tokyo(), bearing: -120.0, pitch: 60.0, },
  ]
}

///|
test "the screen center is the camera center and screen points round-trip" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let m = t.screen_to_mercator(400.0, 300.0)
    let c = tokyo().center.to_mercator()
    assert_true(close(m.x, c.x) && close(m.y, c.y))
    let (x, y) = t.mercator_to_screen(t.screen_to_mercator(123.0, 456.0))
    assert_true(close(x, 123.0) && close(y, 456.0))
  }
  assert_eq(
    @core.Transform::new(tokyo(), 1.0, 1.0).world_size(),
    512.0 * 16384.0,
  )
}

///|
test "a flat view maps one world pixel to one CSS pixel" {
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let c = tokyo().center.to_mercator()
  let ws = t.world_size()
  let (x, y) = t.mercator_to_screen({ x: c.x + 100.0 / ws, y: c.y - 50.0 / ws, })
  assert_true(close(x, 500.0) && close(y, 250.0))
}

///|
test "bearing turns the map: at 90° east points up" {
  let t = @core.Transform::new({ ..tokyo(), bearing: 90.0, }, 800.0, 600.0)
  let c = tokyo().center.to_mercator()
  let ws = t.world_size()
  let (x, y) = t.mercator_to_screen({ x: c.x + 100.0 / ws, y: c.y, })
  assert_true(close(x, 400.0) && close(y, 200.0))
}

///|
test "pitch shrinks what lies ahead and enlarges what is near" {
  let t = @core.Transform::new({ ..tokyo(), pitch: 60.0, }, 800.0, 600.0)
  let c = tokyo().center.to_mercator()
  let ws = t.world_size()
  let (_, north) = t.mercator_to_screen({ x: c.x, y: c.y - 100.0 / ws, })
  let (_, south) = t.mercator_to_screen({ x: c.x, y: c.y + 100.0 / ws, })
  // 100 px ahead (north) appear closer to the center than 100 px behind.
  assert_true(300.0 - north > 0.0 && 300.0 - north < south - 300.0)
}

///|
test "panning keeps the map point under the pointer" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let grabbed = t.screen_to_mercator(100.0, 400.0)
    let moved = t.with_camera(t.panned(100.0, 400.0, 130.0, 380.0))
    let (x, y) = moved.mercator_to_screen(grabbed)
    assert_true((x - 130.0).abs() < 1.0e-3 && (y - 380.0).abs() < 1.0e-3)
  }
}

///|
test "zooming around a point keeps that point fixed" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let anchor = t.screen_to_mercator(700.0, 450.0)
    let zoomed = t.with_camera(t.zoomed_around(700.0, 450.0, 15.5))
    assert_eq(zoomed.camera.zoom, 15.5)
    assert_eq(
      (zoomed.camera.bearing, zoomed.camera.pitch),
      (camera.bearing, camera.pitch),
    )
    let (x, y) = zoomed.mercator_to_screen(anchor)
    assert_true((x - 700.0).abs() < 1.0e-3 && (y - 450.0).abs() < 1.0e-3)
  }
}

///|
test "zoom, latitude and pitch are clamped, longitude and bearing wrap" {
  let t = @core.Transform::new(
    {
      center: { lng: 190.0, lat: 89.0, },
      zoom: 30.0,
      bearing: 270.0,
      pitch: 80.0,
    },
    100.0,
    100.0,
    min_zoom=2.0,
    max_zoom=20.0,
  )
  assert_eq(t.camera.zoom, 20.0)
  assert_eq(t.camera.center.lat, @core.MAX_LATITUDE)
  assert_true(close(t.camera.center.lng, -170.0))
  assert_eq((t.camera.bearing, t.camera.pitch), (-90.0, @core.MAX_PITCH))
  let low = t.with_camera({
    ..t.camera,
    zoom: -3.0,
    pitch: -5.0,
    bearing: -180.0,
  })
  assert_eq(
    (low.camera.zoom, low.camera.pitch, low.camera.bearing),
    (2.0, 0.0, -180.0),
  )
}

///|
test "tile_zoom floors the camera zoom into the source range" {
  let t = @core.Transform::new({ ..tokyo(), zoom: 14.7, }, 800.0, 600.0)
  assert_eq(t.tile_zoom(0, 22), 14)
  assert_eq(t.tile_zoom(0, 12), 12)
  assert_eq(t.tile_zoom(15, 18), 15)
  // 256-pixel tiles are one zoom deeper, 128-pixel ones two.
  assert_eq(t.tile_zoom(0, 22, tile_size=256), 15)
  assert_eq(t.tile_zoom(0, 22, tile_size=128), 16)
  assert_eq(t.tile_zoom(0, 14, tile_size=256), 14)
  assert_eq(
    (@core.zoom_shift(512), @core.zoom_shift(256), @core.zoom_shift(128)),
    (0, 1, 2),
  )
}

///|
test "a flat view is covered by tiles of one zoom, nearest first" {
  // At zoom 14 a tile is 512 CSS px: an 800 x 600 view sees 2-3 tiles a side.
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  let tiles = t.covering_tiles(0, 14)
  let center = @core.tile_containing(tokyo().center.to_mercator(), 14).unwrap()
  assert_eq(tiles[0], center)
  for tile in tiles {
    assert_eq(tile.z, 14)
    let b = tile.mercator_bounds()
    let (x0, y0) = t.mercator_to_screen({ x: b.min_x, y: b.min_y, })
    let (x1, y1) = t.mercator_to_screen({ x: b.max_x, y: b.max_y, })
    assert_true(x1 > 0.0 && x0 < 800.0 && y1 > 0.0 && y0 < 600.0)
  }
  assert_true(tiles.length() >= 4 && tiles.length() <= 9)
}

///|
/// Mercator points spread over the screen (a 9 x 9 grid).
fn screen_samples(t : @core.Transform) -> Array[@core.MercatorCoord] {
  let out = []
  for i in 0..<=8 {
    for j in 0..<=8 {
      out.push(
        t.screen_to_mercator(
          t.width * i.to_double() / 8.0,
          t.height * j.to_double() / 8.0,
        ),
      )
    }
  }
  out
}

///|
test "covering tiles of any view cover the whole screen exactly once" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let tiles = t.covering_tiles(4, 14)
    for m in screen_samples(t) {
      let n = tiles
        .filter(tile => {
          let b = tile.mercator_bounds()
          m.x >= b.min_x && m.x < b.max_x && m.y >= b.min_y && m.y < b.max_y
        })
        .length()
      // Points on the far right or bottom edge may fall just past the last tile.
      assert_true(n == 1 || (n == 0 && (m.x >= 1.0 || m.y >= 1.0)))
    }
  }
}

///|
test "a pitched view uses lower zooms in the distance" {
  // At 60° the top edge of an 800 x 600 view lies 1.5-3 camera distances
  // away, which is one zoom level down (LOD_DISTANCE).
  let t = @core.Transform::new({ ..tokyo(), pitch: 60.0, }, 800.0, 600.0)
  let tiles = t.covering_tiles(4, 14)
  let at = (z : Int32) => tiles.filter(tile => tile.z == z).length()
  assert_eq((at(14), at(13), tiles.length()), (9, 3, 12))
  assert_eq(tiles[0].z, 14)
  // The source's minimum zoom is a floor, whatever the distance.
  assert_true(t.covering_tiles(14, 14).iter().all(tile => tile.z == 14))
}

///|
test "tile_matrix maps the tile's corners to their screen positions" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let tile = @core.TileId::new(14, 14552, 6451).unwrap()
    let m = t.tile_matrix(tile, 4096)
    let b = tile.mercator_bounds()
    for corner in [(0, 0, b.min_x, b.min_y), (4096, 4096, b.max_x, b.max_y)] {
      let (u, v, mx, my) = corner
      let (sx, sy) = t.mercator_to_screen({ x: mx, y: my, })
      let (x, y, _, w) = m.apply(u.to_double(), v.to_double(), 0.0, 1.0)
      assert_true((x / w - (sx / 400.0 - 1.0)).abs() < 1.0e-6)
      assert_true((y / w - (1.0 - sy / 300.0)).abs() < 1.0e-6)
    }
  }
  let t = @core.Transform::new(tokyo(), 800.0, 600.0)
  assert_eq(t.tile_scale(@core.TileId::new(14, 0, 0).unwrap(), 4096), 0.125)
  // The center's clip w is the camera distance, whatever the pitch.
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let c = tokyo().center.to_mercator()
    let tile = @core.tile_containing(c, 14).unwrap()
    let b = tile.mercator_bounds()
    let u = (c.x - b.min_x) / (b.max_x - b.min_x) * 4096.0
    let v = (c.y - b.min_y) / (b.max_y - b.min_y) * 4096.0
    let (_, _, _, w) = t.tile_matrix(tile, 4096).apply(u, v, 0.0, 1.0)
    assert_true((w - t.center_depth()).abs() < 1.0e-6)
  }
}

///|
test "cameras with NaN or infinite values are ignored" {
  let t = @core.Transform::new(tokyo(), 100.0, 100.0)
  let nan = 0.0 / 0.0
  let inf = 1.0 / 0.0
  let cameras : Array[@core.Camera] = [
    { ..tokyo(), center: { lng: nan, lat: 0.0, }, },
    { ..tokyo(), center: { lng: 0.0, lat: -inf, }, },
    { ..tokyo(), zoom: nan, },
    { ..tokyo(), bearing: inf, },
    { ..tokyo(), pitch: nan, },
  ]
  for bad in cameras {
    assert_eq(t.with_camera(bad).camera, tokyo())
    assert_eq(@core.Transform::new(bad, 100.0, 100.0).camera, {
      center: { lng: 0.0, lat: 0.0, },
      zoom: 0.0,
      bearing: 0.0,
      pitch: 0.0,
    })
  }
}

///|
test "keeping turns and tilts the map around a screen point" {
  for camera in views() {
    let t = @core.Transform::new(camera, 800.0, 600.0)
    let anchor = t.screen_to_mercator(200.0, 400.0)
    let next = t.with_camera(
      t.keeping(200.0, 400.0, {
        ..camera,
        bearing: camera.bearing + 40.0,
        pitch: 30.0,
      }),
    )
    assert_eq(next.camera.pitch, 30.0)
    let (x, y) = next.mercator_to_screen(anchor)
    assert_true((x - 200.0).abs() < 1.0e-3 && (y - 400.0).abs() < 1.0e-3)
  }
}

///|
test "with_elevation keeps the lifted center at the middle of the screen" {
  let t = @core.Transform::new(
    { ..tokyo(), pitch: 50.0, bearing: 20.0, },
    800.0,
    600.0,
  )
  let lifted = t.with_elevation(1000.0)
  assert_eq((t.elevation, lifted.elevation), (0.0, 1000.0))
  // The center tile and the center's position in its units.
  let z = 14
  let c = t.camera.center.to_mercator()
  let n = (1 << z).to_double()
  let id = @core.TileId::new(z, (c.x * n).to_int(), (c.y * n).to_int()).unwrap()
  let ux = (c.x * n - id.x.to_double()) * 4096.0
  let uy = (c.y * n - id.y.to_double()) * 4096.0
  let screen = (tr : @core.Transform, h : Double) => {
    let (x, y, _, w) = tr.tile_matrix(id, 4096).apply(ux, uy, h, 1.0)
    (x / w, y / w)
  }
  let near = (a : (Double, Double)) => a.0.abs() < 1.0e-9 && a.1.abs() < 1.0e-9
  assert_true(near(screen(t, 0.0)))
  assert_true(near(screen(lifted, 1000.0 * lifted.pixels_per_meter())))
  // Ground at height 0 now sits below the middle (it is lower than the center).
  assert_true(screen(lifted, 0.0).1 < -0.01)
  // Moving the camera keeps the elevation; NaN is ignored.
  assert_eq(lifted.with_camera({ ..tokyo(), zoom: 13.0, }).elevation, 1000.0)
  assert_eq(lifted.with_elevation(@double.not_a_number).elevation, 1000.0)
}
