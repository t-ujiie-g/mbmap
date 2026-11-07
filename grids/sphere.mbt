// Helpers of @turf/helpers and @turf/distance 7.4.0 (MIT License,
// Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// The trigonometry these functions use (`@core.Trig`): a wasm build passes
/// the host's `Math` to match Turf bit for bit; `@math` can differ in the last
/// bit.
pub using @core {type Trig}

///|
const PI : Double = 3.141592653589793

///|
/// Turf's mean earth radius in meters.
const EARTH_RADIUS : Double = 6371008.8

///|
/// Turf's factor for kilometers (`earthRadius / 1e3`).
let km_factor : Double = EARTH_RADIUS / 1000.0

///|
/// Turf's factor for degrees (`360 / (2 * Math.PI)`).
let degree_factor : Double = 360.0 / (2.0 * PI)

///|
/// Turf's `degreesToRadians`, which first takes the degrees modulo 360.
fn radians(degrees : Double) -> Double {
  degrees % 360.0 * PI / 180.0
}

///|
/// `@turf/distance` in kilometers (haversine), from (`lng1`, `lat1`).
fn distance(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  let d_lat = radians(lat2 - lat1)
  let d_lng = radians(lng2 - lng1)
  let r_lat1 = radians(lat1)
  let r_lat2 = radians(lat2)
  let s_lat = (trig.sin)(d_lat / 2.0)
  let s_lng = (trig.sin)(d_lng / 2.0)
  let a = s_lat * s_lat +
    s_lng * s_lng * (trig.cos)(r_lat1) * (trig.cos)(r_lat2)
  2.0 * (trig.atan2)(a.sqrt(), (1.0 - a).sqrt()) * km_factor
}
