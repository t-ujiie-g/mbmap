// Spherical helpers of @turf/helpers, @turf/distance and
// @turf/nearest-point-on-line 7.4.0 (MIT License, Copyright (c) 2017 TurfJS).
// See NOTICE.

///|
using @core {type Trig}

///|
/// Turf's factor for kilometers (`earthRadius / 1e3`).
let km_factor : Double = @core.EARTH_RADIUS / 1000.0

///|
/// Turf's `radiansToDegrees`, which first takes the radians modulo 2π.
fn degrees(radians : Double) -> Double {
  radians % (2.0 * @core.PI) * 180.0 / @core.PI
}

///|
/// `@turf/distance` in kilometers (haversine).
fn distance(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  @core.haversine(trig, lng1, lat1, lng2, lat2) * km_factor
}

///|
/// A point on the unit sphere.
priv struct Vec3 {
  x : Double
  y : Double
  z : Double
}

///|
fn to_vector(trig : Trig, lng : Double, lat : Double) -> Vec3 {
  let la = @core.turf_radians(lat)
  let ln = @core.turf_radians(lng)
  {
    x: trig.cos(la) * trig.cos(ln),
    y: trig.cos(la) * trig.sin(ln),
    z: trig.sin(la),
  }
}

///|
/// `vectorToLngLat`: z clamped to [-1, 1] (a NaN stays NaN).
fn to_lng_lat(trig : Trig, v : Vec3) -> (Double, Double) {
  let z = if v.z > 1.0 { 1.0 } else if v.z < -1.0 { -1.0 } else { v.z }
  let lat = degrees(trig.asin(z))
  let lng = degrees(trig.atan2(v.y, v.x))
  (lng, lat)
}

///|
fn dot(a : Vec3, b : Vec3) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}

///|
fn cross(a : Vec3, b : Vec3) -> Vec3 {
  {
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  }
}

///|
fn is_zero(v : Vec3) -> Bool {
  v.x == 0.0 && v.y == 0.0 && v.z == 0.0
}

///|
/// Turf's `normalize`; `Math.pow(x, 2)` is `x * x` exactly.
fn normalize(v : Vec3) -> Vec3 {
  let mag = (v.x * v.x + v.y * v.y + v.z * v.z).sqrt()
  { x: v.x / mag, y: v.y / mag, z: v.z / mag, }
}

///|
/// Turf's `nearestPointOnSegment` from A to B for C: the point and whether it
/// is B.
fn nearest_on_segment(
  trig : Trig,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> (Double, Double, Bool) {
  let a = to_vector(trig, ax, ay)
  let b = to_vector(trig, bx, by)
  let c = to_vector(trig, cx, cy)
  let segment_axis = cross(a, b)
  if is_zero(segment_axis) {
    return if dot(a, b) > 0.0 { (bx, by, true) } else { (cx, cy, false) }
  }
  let target_axis = cross(segment_axis, c)
  if is_zero(target_axis) {
    return (bx, by, true)
  }
  let i1 = normalize(cross(target_axis, segment_axis))
  let i2 = { x: -i1.x, y: -i1.y, z: -i1.z, }
  let i = if dot(c, i1) > dot(c, i2) { i1 } else { i2 }
  let axis = normalize(segment_axis)
  let cmp_ai = dot(cross(a, i), axis)
  let cmp_ib = dot(cross(i, b), axis)
  if cmp_ai >= 0.0 && cmp_ib >= 0.0 {
    let (lng, lat) = to_lng_lat(trig, i)
    return (lng, lat, false)
  }
  if dot(a, c) > dot(b, c) {
    (ax, ay, false)
  } else {
    (bx, by, true)
  }
}
