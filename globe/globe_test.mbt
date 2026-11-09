// Expected values come from MapLibre GL JS 6.16.0 (`npm run globe:golden` compares the rest).

///|
fn near(a : Double, b : Double, tol~ : Double = 0.0000001) -> Bool {
  (a - b).abs() <= tol
}

///|
fn tokyo_globe() -> @globe.Globe {
  @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 3.0,
      bearing: 30.0,
      pitch: 40.0,
    },
    800.0,
    600.0,
  )
}

///|
test "projection transition: globe blends into mercator from zoom 11 to 12" {
  assert_eq(@globe.Projection::Globe.transition(3.0), 1.0)
  assert_eq(@globe.Projection::Globe.transition(11.25), 0.75)
  assert_eq(@globe.Projection::Globe.transition(12.0), 0.0)
  assert_eq(@globe.Projection::Mercator.transition(3.0), 0.0)
  assert_eq(@globe.Projection::VerticalPerspective.transition(18.0), 1.0)
}

///|
test "project, unproject and occlusion on the globe" {
  let g = tokyo_globe()
  let (x, y) = g.project({ lng: 150.0, lat: 20.0, })
  assert_true(near(x, 632.1985251946106, tol=0.000001))
  assert_true(near(y, 419.1668597335715, tol=0.000001))
  assert_false(g.occluded({ lng: 150.0, lat: 20.0, }))
  assert_true(g.occluded({ lng: -40.0, lat: -20.0, }))
  let p = g.unproject(100.0, 500.0)
  assert_true(near(p.lng, 110.86188503545611) && near(p.lat, 30.80693838917165))
  let sky = g.unproject(400.0, 0.0)
  assert_true(near(sky.lng, -175.71879027143603))
  assert_true(near(sky.lat, 63.51492593125141))
  assert_true(g.on_surface(400.0, 300.0))
  assert_false(g.on_surface(400.0, 0.0))
}

///|
test "globe bounds" {
  let b = tokyo_globe().bounds()
  assert_true(
    near(b.west, 70.81000452346939) && near(b.south, 4.125045284711867),
  )
  assert_true(
    near(b.east, 193.54136932417782) && near(b.north, 74.00980025487922),
  )
}

///|
test "a pole in view widens the bounds to every longitude" {
  let g = @globe.Globe::new(
    { center: { lng: 0.0, lat: 80.0, }, zoom: 1.0, bearing: 0.0, pitch: 0.0, },
    800.0,
    600.0,
  )
  let b = g.bounds()
  assert_eq((b.west, b.east, b.north), (-180.0, 180.0, 90.0))
}

///|
test "set_location_at_point, fit and inertia on the globe" {
  let g = tokyo_globe()
  let fit = g.camera_for_bounds(
    { west: 139.5, south: 35.5, east: 140.0, north: 35.8, },
    padding=@core.Padding::uniform(10.0),
  )
  guard fit is Some(f) else { fail("no fit") }
  assert_true(
    near(f.center.lng, 139.75) && near(f.center.lat, 35.65014083232522),
  )
  assert_true(near(f.zoom, 10.098197457190654))
  let (center, offset) = g.pan_inertia((40.0, -10.0))
  assert_true(near(center.lng, 136.28302631482035))
  assert_true(near(center.lat, 36.49075981302811))
  assert_eq(offset, (0.0, 0.0))
  g.set_location_at_point({ lng: 140.0, lat: 36.0, }, 300.0, 200.0)
  let c = g.camera()
  assert_true(near(c.center.lng, 141.1519641275213))
  assert_true(near(c.center.lat, 21.082589975396957))
  assert_true(near(c.zoom, 3.20000614711063))
}

///|
test "padding wider than the view fits nothing" {
  let fit = tokyo_globe().camera_for_bounds(
    { west: 139.5, south: 35.5, east: 140.0, north: 35.8, },
    padding=@core.Padding::uniform(500.0),
  )
  assert_true(fit is None)
}

///|
test "copy leaves the original alone" {
  let g = tokyo_globe()
  let h = g.copy()
  h.set_zoom(5.0)
  assert_eq(g.camera().zoom, 3.0)
  assert_eq(h.camera().zoom, 5.0)
}

///|
test "at zoom 12 the globe camera is the mercator one" {
  let g = @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 13.0,
      bearing: 0.0,
      pitch: 30.0,
    },
    800.0,
    600.0,
  )
  assert_false(g.is_globe())
  let t = g.mercator()
  let p : @core.LngLat = { lng: 139.77, lat: 35.68, }
  assert_eq(g.project(p), t.project(p))
  assert_eq(g.unproject(100.0, 500.0), t.unproject(100.0, 500.0))
  assert_eq(g.bounds(), t.bounds())
  assert_false(g.occluded(p))
  g.set_zoom(10.0)
  assert_false(g.is_globe())
  g.update_transition()
  assert_true(g.is_globe())
}

///|
test "ease_to ends at the target" {
  let g = tokyo_globe()
  let e = g.ease_to(
    @core.CameraTarget::new(
      center={ lng: 2.35, lat: 48.85, },
      zoom=5.0,
      bearing=0.0,
      pitch=0.0,
    ),
  )
  let mid = e.at(0.5)
  assert_true(mid.center.lng < 139.0 && mid.center.lng > 2.35)
  let end = e.at(1.0)
  assert_true(near(end.center.lng, 2.35) && near(end.center.lat, 48.85))
  assert_true(near(end.zoom, 5.0) && end.pitch == 0.0)
  assert_eq(e.transform().camera(), end)
  assert_eq(g.camera().zoom, 3.0)
}

///|
test "fly_to passes from mercator to the globe and back" {
  let g = @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 14.0,
      bearing: 0.0,
      pitch: 0.0,
    },
    800.0,
    600.0,
  )
  guard g.fly_to(
      @core.CameraTarget::new(center={ lng: -74.0, lat: 40.7, }, zoom=14.0),
    )
    is Some(f) else {
    fail("no flight")
  }
  assert_true(f.duration > 1000.0)
  assert_false(f.transform().is_globe())
  let _ = f.at(0.5)
  assert_true(f.transform().is_globe())
  let end = f.at(1.0)
  assert_true(near(end.center.lng, -74.0) && near(end.center.lat, 40.7))
  assert_false(f.transform().is_globe())
}

///|
test "fly_to the same camera is too short to fly" {
  assert_true(tokyo_globe().fly_to(@core.CameraTarget::new(zoom=3.0)) is None)
}

///|
test "gestures: zoom about a point, drag and turn" {
  let g = tokyo_globe()
  g.apply_controls(400.0, 300.0, zoom=1.0)
  assert_true(near(g.camera().zoom, 4.0))
  let before = g.camera().center
  g.apply_controls(500.0, 350.0, pan=(30.0, 10.0))
  assert_true(g.camera().center.lng < before.lng)
  g.apply_controls(400.0, 300.0, bearing=10.0, pitch=5.0)
  assert_true(near(g.camera().bearing, 40.0) && near(g.camera().pitch, 45.0))
  let m = @globe.Globe::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 14.0,
      bearing: 0.0,
      pitch: 0.0,
    },
    800.0,
    600.0,
  )
  m.apply_controls(600.0, 300.0, zoom=1.0)
  let t = m.mercator()
  assert_true(
    near(
      t.project({ lng: 139.7671, lat: 35.6812, }).0,
      200.0 + 200.0,
      tol=200.0,
    ),
  )
  let (_, offset) = m.pan_inertia((40.0, 0.0))
  assert_eq(offset, (40.0, 0.0))
}

///|
test "tile meshes: granularity by zoom, grid, borders and poles" {
  assert_eq([0, 1, 2, 5].map(@globe.tile_granularity), [128, 64, 32, 32])
  let (v, i) = @globe.tile_mesh(2)
  assert_eq(v.length(), 9 * 2)
  assert_eq(i.length(), 4 * 6)
  assert_eq((v[2], v[3], v[16], v[17]), (4096, 0, 8192, 8192))
  assert_eq((i[0], i[1], i[2], i[3], i[4], i[5]), (0, 3, 1, 1, 3, 4))
  let (p, _) = @globe.tile_mesh(1, north=true, south=true)
  assert_eq((p[1], p[p.length() - 1]), (@core.NORTH_POLE_Y, @core.SOUTH_POLE_Y))
  let (b, bi) = @globe.tile_mesh(1, borders=true)
  assert_eq((b[0], b[1], bi.length()), (-64, -64, 9 * 6))
}

///|
test "set_camera takes a camera as it is" {
  let g = tokyo_globe()
  g.set_camera({
    center: { lng: 0.0, lat: 89.9, },
    zoom: -5.0,
    bearing: 10.0,
    pitch: 0.0,
  })
  assert_true(near(g.camera().center.lat, 89.9) && g.camera().zoom == -5.0)
}

///|
test "the sun turns with the globe only when the light is on the map" {
  let g = tokyo_globe()
  let v : @globe.Vec3 = { x: 0.0, y: 0.0, z: 1.0, }
  assert_eq(g.sun(v, map=false), { x: -0.0, y: -0.0, z: -1.0, })
  assert_true(g.sun(v, map=true) != g.sun(v, map=false))
}

///|
test "light_direction takes up at the center to the center's surface normal" {
  let g = tokyo_globe()
  let up = g.light_direction({ x: 0.0, y: 0.0, z: 1.0, })
  let n = @globe.surface_vector(g.camera().center)
  assert_true(near(up.x, n.x) && near(up.y, n.y) && near(up.z, n.z))
  let east = g.light_direction({ x: 1.0, y: 0.0, z: 0.0, })
  assert_true(near(east.y, 0.0))
}
