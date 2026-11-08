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
test "sphere helpers match MapLibre's globe_utils" {
  let t = @globe.tile_vector(1000.0, 7000.0, 3, 3, 5)
  assert_true(near(t.x, -0.2812408057393648))
  assert_true(near(t.y, -0.896973573531245))
  assert_true(near(t.z, 0.34108945684916897))
  let p = @globe.surface_point({ x: 0.3, y: 0.4, z: (1.0 - 0.25).sqrt(), })
  assert_true(near(p.lng, 19.10660535086913))
  assert_true(near(p.lat, 23.578178478201835))
  let v = @globe.surface_vector(p)
  assert_true(near(v.x, 0.3) && near(v.y, 0.4))
  assert_true(near(@globe.planet_scale(60.0), 0.5))
  assert_true(near(@globe.globe_radius(4096.0, 35.0), 795.8213025888726))
  assert_true(near(@globe.zoom_adjustment(0.0, 60.0), -1.0))
  assert_true(
    near(@globe.atmosphere_blend(3000.0, 20000.0), 0.9929544242465707),
  )
}

///|
test "a pole's surface point has longitude 0" {
  assert_eq(@globe.surface_point({ x: 0.0, y: 1.0, z: 0.0, }).lng, 0.0)
}

///|
test "globe camera state, matrices and transition" {
  let g = tokyo_globe()
  let c = g.camera()
  assert_true(near(c.center.lng, 139.7671) && c.zoom == 3.0)
  assert_true(near(c.bearing, 30.0) && near(c.pitch, 40.0))
  assert_true(g.is_globe())
  assert_eq(g.transition(), 1.0)
  assert_true(near(g.world_size(), 4096.0))
  let cam = g.camera_position()
  assert_true(near(cam.x, 1.485672373298805))
  assert_true(near(cam.y, 0.577269476266834))
  assert_true(near(cam.z, -1.198001732946235))
  let (a, b, cc, d) = g.clipping_plane_of()
  assert_true(near(a, 0.7451056393492476) && near(b, 0.2895165515096346))
  assert_true(near(cc, -0.6008308852014168) && near(d, -0.5015275593331562))
  let m = g.globe_matrix().m
  assert_true(near(m[0], -853.7230429436682, tol=0.000001))
  assert_true(near(m[14], 1514.4005303486674, tol=0.000001))
  let (_, near_z, far_z) = g.projection()
  assert_true(near_z == 0.5 && near(far_z, 2505.118173916742, tol=0.000001))
  assert_true(near(g.camera_altitude(), 6332198.9927503215, tol=0.01))
  let r = g.ray_direction(100.0, 200.0)
  assert_true(near(r.x, -0.6813411315514837) && near(r.z, 0.6953637264376326))
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
test "setters constrain: pitch to the limits, bearing wrapped, zoom per latitude" {
  let g = tokyo_globe()
  g.set_pitch(120.0)
  assert_true(near(g.camera().pitch, 85.0))
  g.set_bearing(190.0)
  assert_true(near(g.camera().bearing, -170.0))
  g.set_center({ lng: 10.0, lat: 60.0, })
  assert_true(near(g.camera().center.lat, 60.0))
  g.set_zoom(-3.0)
  assert_true(near(g.camera().zoom, @globe.zoom_adjustment(0.0, 60.0)))
  g.resize(400.0, 300.0)
  assert_true(near(g.project(g.camera().center).0, 200.0))
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
test "jump_to keeps the globe's size when only the center moves" {
  let g = tokyo_globe()
  g.jump_to(center={ lng: 0.0, lat: 60.0, })
  assert_true(
    near(g.camera().zoom, 3.0 + @globe.zoom_adjustment(35.6812, 60.0)),
  )
  g.jump_to(zoom=4.0, bearing=10.0, pitch=0.0)
  assert_eq((g.camera().zoom, g.camera().pitch), (4.0, 0.0))
  assert_true(near(g.camera().bearing, 10.0))
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
