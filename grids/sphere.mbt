// Helpers of @turf/helpers and @turf/distance 7.4.0 (MIT License,
// Copyright (c) 2017 TurfJS). See NOTICE.

///|
using @core {type Trig}

///|
/// Turf's factor for kilometers (`earthRadius / 1e3`).
let km_factor : Double = @core.EARTH_RADIUS / 1000.0

///|
/// Turf's factor for degrees (`360 / (2 * Math.PI)`).
let degree_factor : Double = 360.0 / (2.0 * @core.PI)

///|
/// `@turf/distance` in kilometers (haversine), from (`lng1`, `lat1`).
fn distance(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  @core.haversine(trig, lng1, lat1, lng2, lat2) * km_factor
}
