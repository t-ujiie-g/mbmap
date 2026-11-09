///|
fn shadow_camera(pitch : Double) -> @core.Transform {
  @core.Transform::new(
    {
      center: { lng: 139.767, lat: 35.681, },
      zoom: 16.0,
      bearing: 30.0,
      pitch,
    },
    800.0,
    600.0,
  )
}

///|
fn inside(p : (Double, Double, Double, Double)) -> Bool {
  p.0.abs() <= 1.0 && p.1.abs() <= 1.0 && p.2.abs() <= 1.0 && p.3 == 1.0
}

///|
test "the shadow view holds the ground around the center and casts along the light" {
  let t = shadow_camera(45.0)
  let sun = (0.5, -0.3, 0.6)
  let v = t.shadow_view(sun)
  let m = v.matrix
  assert_true(inside(m.apply(0.0, 0.0, 0.0, 1.0)))
  assert_true(inside(m.apply(600.0, -600.0, 0.0, 1.0)))
  // A roof 100 m up and the ground it shades fall on the same texel, the roof nearer the light.
  let ppm = t.pixels_per_meter()
  let n = (0.5 * 0.5 + 0.3 * 0.3 + 0.6 * 0.6).sqrt()
  let k = 100.0 * ppm / (0.6 / n)
  let (gx, gy) = (10.0, 20.0)
  let roof = m.apply(gx + k * 0.5 / n, gy + k * 0.3 / n, 100.0 * ppm, 1.0)
  let ground = m.apply(gx, gy, 0.0, 1.0)
  assert_true((roof.0 - ground.0).abs() < 1.0e-9)
  assert_true((roof.1 - ground.1).abs() < 1.0e-9)
  assert_true(roof.2 < ground.2)
  assert_true(v.texel > 0.0 && v.texel < 0.01)
  // Wider when the camera tilts.
  assert_true(inside(m.apply(1500.0, 0.0, 0.0, 1.0)))
  let low = shadow_camera(0.0).shadow_view(sun).matrix.apply(
    1500.0, 0.0, 0.0, 1.0,
  )
  assert_true(!inside(low))
}

///|
test "a light straight above makes a shadow view too" {
  let m = shadow_camera(0.0).shadow_view((0.0, 0.0, 1.0)).matrix
  let p = m.apply(100.0, 50.0, 0.0, 1.0)
  assert_true(inside(p))
  assert_true(m.apply(100.0, 50.0, 10.0, 1.0).2 < p.2)
}

///|
test "the sphere's shadow view holds the center and casts along the light" {
  let t = shadow_camera(30.0)
  let v = t.shadow_sphere_view((0.0, 0.0, 1.0))
  let (lng, lat) = (139.767 * @math.PI / 180.0, 35.681 * @math.PI / 180.0)
  let s = (
    @math.sin(lng) * @math.cos(lat),
    @math.sin(lat),
    @math.cos(lng) * @math.cos(lat),
  )
  let ground = v.matrix.apply(s.0, s.1, s.2, 1.0)
  assert_true(inside(ground))
  assert_true(ground.0.abs() < 1.0e-6 && ground.1.abs() < 1.0e-6)
  let h = 1.0 + 50.0 / 6371008.8
  let roof = v.matrix.apply(s.0 * h, s.1 * h, s.2 * h, 1.0)
  assert_true(roof.2 < ground.2)
  assert_true((roof.0 - ground.0).abs() < 1.0e-6)
}

///|
test "a tile's light matrix is the shadow view of its tile units" {
  let t = shadow_camera(0.0)
  let light = t.shadow_view((0.3, 0.2, 0.9)).matrix
  let tile = @core.TileId::new(16, 58210, 25804).unwrap()
  let c = ({ lng: 139.767, lat: 35.681, } : @core.LngLat).to_mercator()
  let ws = t.world_size()
  let at = t.tile_light_matrix(light, tile, 8192).apply(4096.0, 0.0, 5.0, 1.0)
  let x = (58210.5 / 65536.0 - c.x) * ws
  let y = (25804.0 / 65536.0 - c.y) * ws
  let want = light.apply(x, y, 5.0, 1.0)
  assert_true((at.0 - want.0).abs() < 1.0e-9 && (at.1 - want.1).abs() < 1.0e-9)
  assert_true((at.2 - want.2).abs() < 1.0e-9)
}

///|
test "a ray's view puts the surface it meets at its depth times its length" {
  let v = @core.ray_view((10.0, 20.0, 30.0), (0.6, 0.0, -0.8), 100.0, 0.5)
  let at = (d : Double) => {
    v.matrix.apply(10.0 + 0.6 * d, 20.0, 30.0 - 0.8 * d, 1.0)
  }
  assert_true((at(0.0).2 + 1.0).abs() < 1.0e-9)
  assert_true((at(100.0).2 - 1.0).abs() < 1.0e-9)
  assert_true(((at(40.0).2 + 1.0) / 2.0 - 0.4).abs() < 1.0e-9)
  assert_true(at(40.0).0.abs() < 1.0e-9 && at(40.0).1.abs() < 1.0e-9)
  // Half a unit across is the box's edge.
  assert_true(
    (v.matrix.apply(10.0, 20.5, 30.0, 1.0).0.abs() - 1.0).abs() < 1.0e-9,
  )
}

///|
test "a ray meets the sea-level plane or the terrain" {
  let t = shadow_camera(60.0)
  assert_eq(
    t.ground_hit((0.0, 0.0, 100.0), (0.0, 0.6, -0.8), 1000.0, None),
    Some(125.0),
  )
  assert_eq(
    t.ground_hit((0.0, 0.0, 100.0), (0.0, 0.6, -0.8), 100.0, None),
    None,
  )
  assert_eq(
    t.ground_hit((0.0, 0.0, 100.0), (0.0, 0.0, 1.0), 1000.0, None),
    None,
  )
  // Flat terrain 10 m up.
  let ppm = t.pixels_per_meter()
  let terrain : @core.Terrain = {
    height: (_, _) => Some(10.0),
    lowest: 10.0,
    highest: 10.0,
  }
  let d = t
    .ground_hit((0.0, 0.0, 100.0), (0.0, 0.0, -1.0), 1000.0, Some(terrain))
    .unwrap()
  assert_true((d - (100.0 - 10.0 * ppm)).abs() < 0.01)
}

///|
test "the eye ray of the screen's center runs through the center" {
  let t = shadow_camera(45.0)
  let (from, dir, length) = t.eye_ray(400.0, 300.0)
  assert_true(length > 0.0)
  // Where it crosses sea level is the center (x, y 0).
  let d = -from.2 / dir.2
  assert_true(
    (from.0 + dir.0 * d).abs() < 1.0e-6 && (from.1 + dir.1 * d).abs() < 1.0e-6,
  )
}

///|
test "a spot view looks along its direction, nearer surfaces at smaller depths" {
  let v = @core.spot_view(
    (0.0, 0.0, 10.0),
    (1.0, 0.0, 0.0),
    1.0,
    1.5,
    1.0,
    100.0,
  )
  let ndc = (x : Double, y : Double, z : Double) => {
    let p = v.matrix.apply(x, y, z, 1.0)
    (p.0 / p.3, p.1 / p.3, p.2 / p.3)
  }
  let a = ndc(50.0, 0.0, 10.0)
  assert_true(a.0.abs() < 1.0e-9 && a.1.abs() < 1.0e-9)
  assert_true((ndc(1.0, 0.0, 10.0).2 + 1.0).abs() < 1.0e-9)
  assert_true((ndc(100.0, 0.0, 10.0).2 - 1.0).abs() < 1.0e-9)
  assert_true(ndc(20.0, 0.0, 10.0).2 < ndc(30.0, 0.0, 10.0).2)
  // Up on screen is up, and a point 1 unit up at 10 units is tan⁻¹(0.1) above the axis.
  assert_true(ndc(10.0, 0.0, 11.0).1 > 0.0)
  assert_true((ndc(10.0, 0.0, 11.0).1 - 0.1 / @math.tan(0.5)).abs() < 1.0e-9)
  assert_true(v.texel > 0.0)
}

///|
test "the east, north, up matrix puts the origin at zero and meters at its scale" {
  let t = shadow_camera(30.0)
  let origin = (139.768, 35.682, 5.0)
  let m = t.enu_matrix(origin)
  let ws = t.world_size()
  let c = ({ lng: 139.767, lat: 35.681, } : @core.LngLat).to_mercator()
  let o = ({ lng: 139.768, lat: 35.682, } : @core.LngLat).to_mercator()
  let (x, y) = ((o.x - c.x) * ws, (o.y - c.y) * ws)
  let ppm = t.pixels_per_meter()
  let at = m.apply(x, y, 5.0 * ppm, 1.0)
  assert_true(at.0.abs() < 1.0e-9 && at.1.abs() < 1.0e-9 && at.2.abs() < 1.0e-9)
  // One world pixel north (y down) of it is north, 10 m up is 10.
  let north = m.apply(x, y - 1.0, 15.0 * ppm, 1.0)
  assert_true(north.1 > 0.0 && north.0.abs() < 1.0e-9)
  assert_true((north.2 - 10.0).abs() < 1.0e-9)
}
