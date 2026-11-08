// Helpers of @turf/helpers, @turf/distance and @turf/area 7.4.0 (MIT License,
// Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// JavaScript's `Math.PI`.
pub const PI : Double = 3.141592653589793

///|
/// Turf's mean earth radius in meters (`earthRadius`).
pub const EARTH_RADIUS : Double = 6371008.8

///|
/// Turf's `degreesToRadians`, which first takes the degrees modulo 360.
pub fn turf_radians(degrees : Double) -> Double {
  degrees % 360.0 * PI / 180.0
}

///|
/// The central angle in radians between two lng/lat points by `@turf/distance`'s
/// haversine; its distance is this times the radius.
pub fn haversine(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  let s_lat = trig.sin(turf_radians(lat2 - lat1) / 2.0)
  let s_lng = trig.sin(turf_radians(lng2 - lng1) / 2.0)
  let a = s_lat * s_lat +
    s_lng * s_lng * trig.cos(turf_radians(lat1)) * trig.cos(turf_radians(lat2))
  2.0 * trig.atan2(a.sqrt(), (1.0 - a).sqrt())
}

///|
/// @turf/area's `ringArea` (signed, square meters) of the closed ring of points
/// `start` until `end` of `coords` (x, y pairs).
pub fn turf_ring_area(
  trig : Trig,
  coords : Array[Double],
  start : Int32,
  end : Int32,
) -> Double {
  let n = end - start - 1
  if n <= 2 {
    return 0.0
  }
  let to_rad = PI / 180.0
  let mut total = 0.0
  for i in 0..<n {
    let middle = if i + 1 == n { 0 } else { i + 1 }
    let upper = if i + 2 >= n { (i + 2) % n } else { i + 2 }
    let lower_x = coords[(start + i) * 2] * to_rad
    let middle_y = coords[(start + middle) * 2 + 1] * to_rad
    let upper_x = coords[(start + upper) * 2] * to_rad
    total += (upper_x - lower_x) * trig.sin(middle_y)
  }
  total * (EARTH_RADIUS * EARTH_RADIUS / 2.0)
}

///|
/// JavaScript's `Math.round`: the nearest integer, halves toward +∞, -0 kept
/// for negative inputs that round to zero.
pub fn js_round(x : Double) -> Double {
  let f = x.floor()
  let r = if x - f >= 0.5 { f + 1.0 } else { f }
  if r == 0.0 && (x < 0.0 || 1.0 / x < 0.0) {
    -0.0
  } else {
    r
  }
}

///|
fn neg_sign(a : Double) -> Bool {
  a.reinterpret_as_int64() < 0L
}

///|
/// JavaScript's `Math.min(a, b)`: NaN if either is, -0 below +0.
pub fn js_min(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a < b {
    a
  } else if b < a {
    b
  } else if neg_sign(a) {
    a
  } else {
    b
  }
}

///|
/// JavaScript's `Math.max(a, b)`: NaN if either is, +0 above -0.
pub fn js_max(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a > b {
    a
  } else if b > a {
    b
  } else if neg_sign(a) {
    b
  } else {
    a
  }
}
