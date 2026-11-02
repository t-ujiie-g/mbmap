///|
fn tilted() -> @core.Transform {
  @core.Transform::new(
    {
      center: { lng: 138.73, lat: 35.36, },
      zoom: 12.0,
      bearing: 0.0,
      pitch: 60.0,
    },
    800.0,
    600.0,
  )
}

///|
/// Flat ground at `base` meters, with a `wall` meters high ridge across the
/// view between latitudes `south` and `north`.
fn ridge(
  base : Double,
  wall : Double,
  south : Double,
  north : Double,
) -> @core.Terrain {
  let (y0, y1) = (
    @core.LngLat::{ lng: 0.0, lat: north, }.to_mercator().y,
    @core.LngLat::{ lng: 0.0, lat: south, }.to_mercator().y,
  )
  {
    height: (_, y) => Some(if y >= y0 && y <= y1 { wall } else { base }),
    lowest: base,
    highest: wall,
  }
}

///|
test "a raised point is projected higher on a tilted screen" {
  let v = tilted()
  let (_, y0) = v.project(v.camera.center)
  let (_, y1) = v.project(v.camera.center, elevation=1000.0)
  assert_true(y1 < y0 - 10.0)
}

///|
test "terrain hides a point behind a ridge but not the ground it stands on" {
  let v = tilted()
  let far = { ..v.camera.center, lat: v.camera.center.lat + 0.02, }
  let near = { ..v.camera.center, lat: v.camera.center.lat - 0.02, }
  let flat = ridge(0.0, 0.0, 0.0, 0.0)
  assert_false(v.occluded(far, 0.0, flat))
  assert_false(v.occluded(near, 0.0, flat))
  let wall = ridge(
    0.0,
    3000.0,
    v.camera.center.lat,
    v.camera.center.lat + 0.005,
  )
  assert_true(v.occluded(far, 0.0, wall))
  assert_false(v.occluded(near, 0.0, wall))
  // On top of the ridge itself the point is not hidden.
  let top = { ..v.camera.center, lat: v.camera.center.lat + 0.0025, }
  assert_false(v.occluded(top, 3000.0, wall))
}

///|
test "a point behind the camera counts as hidden, and no terrain hides nothing" {
  let v = tilted()
  let behind = { ..v.camera.center, lat: v.camera.center.lat - 1.0, }
  let none : @core.Terrain = {
    height: (_, _) => None,
    lowest: 0.0,
    highest: 0.0,
  }
  assert_true(v.occluded(behind, 0.0, none))
  let far = { ..v.camera.center, lat: v.camera.center.lat + 0.02, }
  assert_false(v.occluded(far, 0.0, none))
}

///|
test "unproject_on finds the terrain under a screen point, or the center's plane" {
  let v = tilted().with_elevation(500.0)
  let flat = ridge(500.0, 500.0, 0.0, 0.0)
  let (x, y) = v.project(v.camera.center, elevation=500.0)
  let p = v.unproject_on(x, y, flat)
  assert_true(within(p.lng, v.camera.center.lng, 1.0e-9))
  assert_true(within(p.lat, v.camera.center.lat, 1.0e-9))
  let none : @core.Terrain = {
    height: (_, _) => None,
    lowest: 0.0,
    highest: 0.0,
  }
  let q = v.unproject_on(200.0, 450.0, none)
  let (qx, qy) = v.project(q, elevation=500.0)
  assert_true(within(qx, 200.0, 1.0e-6) && within(qy, 450.0, 1.0e-6))
}
