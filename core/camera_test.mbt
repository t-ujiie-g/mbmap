///|
fn within(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() < tol
}

///|
fn view(pitch : Double, bearing : Double) -> @core.Transform {
  @core.Transform::new(
    { center: { lng: 139.7671, lat: 35.6812, }, zoom: 14.0, bearing, pitch, },
    800.0,
    600.0,
  )
}

///|
test "project and unproject undo each other, and the center is the screen's middle" {
  for v in [view(0.0, 0.0), view(45.0, 30.0), view(70.0, -120.0)] {
    let (cx, cy) = v.project(v.camera.center)
    assert_true(within(cx, 400.0, 1.0e-6) && within(cy, 300.0, 1.0e-6))
    for p in [(100.0, 550.0), (700.0, 420.0), (400.0, 599.0)] {
      let ll = v.unproject(p.0, p.1)
      let (x, y) = v.project(ll)
      assert_true(within(x, p.0, 1.0e-6) && within(y, p.1, 1.0e-6))
    }
  }
}

///|
test "a point behind the camera goes to the grown viewport's edge" {
  let v = view(80.0, 0.0)
  // Far south of a camera looking north is behind it.
  let (x, y) = v.project({ lng: 139.7671, lat: 30.0, })
  assert_true(within(x, 400.0, 1.0e-6) && within(y, 300.0 + 900.0, 1.0e-6))
}

///|
test "bounds hold the corners and stop at the horizon line when tilted" {
  let flat = view(0.0, 0.0)
  let b = flat.bounds()
  let nw = flat.unproject(0.0, 0.0)
  assert_true(within(b.west, nw.lng, 1.0e-9) && within(b.north, nw.lat, 1.0e-9))
  let tilted = view(85.0, 0.0)
  let t = tilted.bounds()
  let horizon = tilted.unproject(400.0, 300.0 - tilted.horizon())
  assert_true(within(t.north, horizon.lat, 1.0e-9))
}

///|
test "at_point puts a place at a screen point" {
  let v = view(45.0, 30.0)
  let tokyo_tower : @core.LngLat = { lng: 139.7454, lat: 35.6586, }
  let c = v.with_camera(v.at_point(tokyo_tower, 200.0, 450.0))
  let (x, y) = c.project(tokyo_tower)
  assert_true(within(x, 200.0, 1.0e-6) && within(y, 450.0, 1.0e-6))
}

///|
test "camera_for_bounds fits a box with padding, and refuses padding with no room" {
  let v = view(0.0, 0.0)
  let box : @core.LngLatBounds = {
    west: 139.5,
    south: 35.5,
    east: 140.0,
    north: 35.8,
  }
  let c = v
    .camera_for_bounds(box, padding=@core.Padding::uniform(20.0))
    .unwrap()
  let fit = v.with_camera(c)
  let (x0, y0) = fit.project({ lng: 139.5, lat: 35.8, })
  let (x1, y1) = fit.project({ lng: 140.0, lat: 35.5, })
  // One pair of edges touches the padding, the other lies inside it.
  assert_true(within(x0, 20.0, 1.0e-6) || within(y0, 20.0, 1.0e-6))
  assert_true(x0 >= 20.0 - 1.0e-6 && x1 <= 780.0 + 1.0e-6)
  assert_true(y0 >= 20.0 - 1.0e-6 && y1 <= 580.0 + 1.0e-6)
  assert_eq(
    v.camera_for_bounds(box, padding=@core.Padding::uniform(500.0)),
    None,
  )
  let capped = v.camera_for_bounds(box, max_zoom=5.0).unwrap()
  assert_eq(capped.zoom, 5.0)
}

///|
test "the default easing is CSS ease and bearings ease the short way" {
  let e = @core.Bezier::ease()
  assert_eq((e.at(0.0), e.at(1.0), e.at(-1.0), e.at(2.0)), (0.0, 1.0, 0.0, 1.0))
  // CSS `ease` at half time is about 80% of the way.
  assert_true(within(e.at(0.5), 0.8024033877399112, 1.0e-6))
  let linear = @core.Bezier::new(0.0, 0.0, 1.0, 1.0)
  assert_true(within(linear.at(0.3), 0.3, 1.0e-6))
}

///|
test "ease_to starts where the camera is and ends at the target" {
  let v = view(0.0, 0.0)
  let target = @core.CameraTarget::new(
    center={ lng: 140.0, lat: 35.5, },
    zoom=12.0,
    bearing=90.0,
    pitch=30.0,
  )
  let e = v.ease_to(target)
  let a = e.at(0.0)
  assert_true(within(a.center.lng, 139.7671, 1.0e-9) && a.zoom == 14.0)
  let b = e.at(1.0)
  assert_true(
    within(b.center.lng, 140.0, 1.0e-9) && within(b.center.lat, 35.5, 1.0e-9),
  )
  assert_eq((b.zoom, b.bearing, b.pitch), (12.0, 90.0, 30.0))
  // Around a point, that point stays put.
  let around : @core.LngLat = { lng: 139.78, lat: 35.69, }
  let (x, y) = v.project(around)
  let z = v.ease_to(@core.CameraTarget::new(zoom=15.0, around~))
  let (x2, y2) = v.with_camera(z.at(0.5)).project(around)
  assert_true(within(x, x2, 1.0e-6) && within(y, y2, 1.0e-6))
}

///|
test "fly_to zooms out on the way and has a duration; a standstill does not fly" {
  let v = view(0.0, 0.0)
  let f = v
    .fly_to(
      @core.CameraTarget::new(center={ lng: 135.5, lat: 34.7, }, zoom=14.0),
    )
    .unwrap()
  assert_true(f.duration > 1000.0)
  assert_true(f.at(0.5).zoom < 10.0)
  let end = f.at(1.0)
  assert_true(within(end.center.lng, 135.5, 1.0e-9) && end.zoom == 14.0)
  assert_true(v.fly_to(@core.CameraTarget::new()) is None)
  assert_true(@core.CameraTarget::new().offset == (0.0, 0.0))
}

///|
test "with_limits moves the camera inside the new limits" {
  let v = view(60.0, 0.0)
  let limited = v.with_limits({
    ..@core.Limits::default(),
    max_zoom: 12.0,
    max_pitch: 40.0,
  })
  assert_eq((limited.camera.zoom, limited.camera.pitch), (12.0, 40.0))
  assert_eq(limited.limits.max_zoom, 12.0)
}

///|
test "max_pitch_scale_factor is 1 looking down and grows with the pitch" {
  assert_true(within(view(0.0, 0.0).max_pitch_scale_factor(), 1.0, 1.0e-9))
  let tilted = view(60.0, 0.0).max_pitch_scale_factor()
  assert_true(tilted > 1.5 && tilted < 10.0)
}

///|
test "an aligned tile matrix puts tile corners on whole pixels at whole zooms" {
  let v = @core.Transform::new(
    {
      center: { lng: 139.76713, lat: 35.68123, },
      zoom: 14.0,
      bearing: 0.0,
      pitch: 0.0,
    },
    800.0,
    600.0,
  )
  let id = @core.TileId::new(14, 14552, 6451).unwrap()
  let screen = (m : @core.Mat4) => {
    let (x, y, _, w) = m.apply(0.0, 0.0, 0.0, 1.0)
    ((x / w + 1.0) * 400.0, (1.0 - y / w) * 300.0)
  }
  let (ax, ay) = screen(v.tile_matrix(id, 4096, aligned=true))
  let (px, py) = screen(v.tile_matrix(id, 4096))
  assert_true(within(ax, ax.round(), 1.0e-6) && within(ay, ay.round(), 1.0e-6))
  assert_true((ax - px).abs() <= 0.5 && (ay - py).abs() <= 0.5)
}
