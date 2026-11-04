///|
test "mercator x and y span the world from -180° to 180° and the latitude limit" {
  assert_eq(mercator_x_from_lng(-180.0), 0.0)
  assert_eq(mercator_x_from_lng(180.0), 1.0)
  assert_true((mercator_y_from_lat(0.0) - 0.5).abs() < 1.0e-9)
  assert_true(mercator_y_from_lat(MAX_LATITUDE).abs() < 1.0e-9)
  assert_true((mercator_y_from_lat(-MAX_LATITUDE) - 1.0).abs() < 1.0e-9)
}

///|
test "normalize_bearing eases the short way round" {
  assert_eq(normalize_bearing(170.0, -170.0), -190.0)
  assert_eq(normalize_bearing(-170.0, 170.0), 190.0)
  assert_eq(normalize_bearing(30.0, 0.0), 30.0)
}

///|
test "empty bounds take the first point they include" {
  assert_eq(
    LngLatBounds::empty()
    .including({ lng: 1.0, lat: 2.0, })
    .including({ lng: -1.0, lat: 3.0, }),
    { west: -1.0, south: 2.0, east: 1.0, north: 3.0, },
  )
}
