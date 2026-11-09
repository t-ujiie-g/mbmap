// Expected values come from MapLibre GL JS 6.16.0 (`npm run globe:golden` compares the rest).

///|
fn near(a : Double, b : Double, tol~ : Double = 0.0000001) -> Bool {
  (a - b).abs() <= tol
}

///|
fn tokyo_globe() -> Globe {
  Globe::new(
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
test "sphere helpers match MapLibre's globe_utils" {
  let t = tile_vector(1000.0, 7000.0, 3, 3, 5)
  assert_true(near(t.x, -0.2812408057393648))
  assert_true(near(t.y, -0.896973573531245))
  assert_true(near(t.z, 0.34108945684916897))
  let p = surface_point({ x: 0.3, y: 0.4, z: (1.0 - 0.25).sqrt(), })
  assert_true(near(p.lng, 19.10660535086913))
  assert_true(near(p.lat, 23.578178478201835))
  let v = surface_vector(p)
  assert_true(near(v.x, 0.3) && near(v.y, 0.4))
  assert_true(near(planet_scale(60.0), 0.5))
  assert_true(near(globe_radius(4096.0, 35.0), 795.8213025888726))
  assert_true(near(zoom_adjustment(0.0, 60.0), -1.0))
  assert_true(near(atmosphere_blend(3000.0, 20000.0), 0.9929544242465707))
}

///|
test "a pole's surface point has longitude 0" {
  assert_eq(surface_point({ x: 0.0, y: 1.0, z: 0.0, }).lng, 0.0)
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
  let (_, near_z, far_z) = g.projection_matrix()
  assert_true(near_z == 0.5 && near(far_z, 2505.118173916742, tol=0.000001))
  assert_true(near(g.camera_altitude(), 6332198.9927503215, tol=0.01))
  let r = g.ray_direction(100.0, 200.0)
  assert_true(near(r.x, -0.6813411315514837) && near(r.z, 0.6953637264376326))
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
  assert_true(near(g.camera().zoom, zoom_adjustment(0.0, 60.0)))
  g.resize(400.0, 300.0)
  assert_true(near(g.project(g.camera().center).0, 200.0))
}

///|
test "jump_to keeps the globe's size when only the center moves" {
  let g = tokyo_globe()
  g.jump_to(center={ lng: 0.0, lat: 60.0, })
  assert_true(near(g.camera().zoom, 3.0 + zoom_adjustment(35.6812, 60.0)))
  g.jump_to(zoom=4.0, bearing=10.0, pitch=0.0)
  assert_eq((g.camera().zoom, g.camera().pitch), (4.0, 0.0))
  assert_true(near(g.camera().bearing, 10.0))
}

///|
test "atmosphere inputs: the globe in front of the camera" {
  let (_, center, r, blend) = tokyo_globe().atmosphere()
  assert_true(near(r, globe_radius(4096.0, 35.6812)))
  assert_true(
    center.z < 0.0 &&
    (center.x * center.x + center.y * center.y + center.z * center.z).sqrt() > r,
  )
  assert_true(blend > 0.0 && blend <= 1.0)
}
