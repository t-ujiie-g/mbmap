///|
test "js_round as Math.round" {
  assert_eq(@core.js_round(2.5), 3.0)
  assert_eq(@core.js_round(-2.5), -2.0)
  assert_eq(1.0 / @core.js_round(-0.4), @double.neg_infinity)
  assert_eq(1.0 / @core.js_round(-0.5), @double.neg_infinity)
  assert_eq(@core.js_round(0.49999999999999994), 0.0)
  assert_eq(@core.js_round(1.5), 2.0)
  assert_eq(@core.js_round(-1.5), -1.0)
  assert_eq(@core.js_round(4503599627370495.5), 4503599627370496.0)
  assert_eq(@core.js_round(4503599627370497.0), 4503599627370497.0)
  assert_eq(@core.js_round(-1.0e300), -1.0e300)
  assert_eq(@core.js_round(@double.infinity), @double.infinity)
  assert_true(@core.js_round(@double.not_a_number).is_nan())
}

///|
test "js_min and js_max as Math.min and Math.max, NaN and signed zeros included" {
  assert_eq(@core.js_min(1.0, 2.0), 1.0)
  assert_eq(@core.js_max(1.0, 2.0), 2.0)
  assert_true(@core.js_min(@double.not_a_number, 2.0).is_nan())
  assert_true(@core.js_max(1.0, @double.not_a_number).is_nan())
  assert_eq(1.0 / @core.js_min(0.0, -0.0), @double.neg_infinity)
  assert_eq(1.0 / @core.js_min(-0.0, 0.0), @double.neg_infinity)
  assert_eq(1.0 / @core.js_max(0.0, -0.0), @double.infinity)
  assert_eq(1.0 / @core.js_max(-0.0, 0.0), @double.infinity)
}

///|
test "turf_radians takes the degrees modulo 360" {
  assert_eq(@core.turf_radians(180.0), @core.PI)
  assert_eq(@core.turf_radians(540.0), @core.PI)
  assert_eq(@core.turf_radians(-90.0), -@core.PI / 2.0)
}

///|
test "haversine gives the central angle as @turf/distance computes it" {
  let trig = @core.Trig::moonbit()
  assert_eq(@core.haversine(trig, 0.0, 0.0, 0.0, 0.0), 0.0)
  let quarter = @core.haversine(trig, 0.0, 0.0, 90.0, 0.0)
  assert_true((quarter - @core.PI / 2.0).abs() < 1.0e-15)
  let km = @core.haversine(trig, 139.7, 35.7, 135.5, 34.7) *
    @core.EARTH_RADIUS /
    1000.0
  assert_true((km - 396.0).abs() < 2.0)
}

///|
test "turf_ring_area of a closed ring, reversed with its sign" {
  let trig = @core.Trig::moonbit()
  let ring = [9.0, 9.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0]
  let a = @core.turf_ring_area(trig, ring, 1, 6)
  assert_true((a.abs() - 12363718145.18).abs() < 1.0)
  let back = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
  assert_eq(@core.turf_ring_area(trig, back, 0, 5), -a)
  assert_eq(@core.turf_ring_area(trig, ring, 1, 4), 0.0)
}
