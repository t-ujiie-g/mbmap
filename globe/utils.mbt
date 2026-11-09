// MapLibre GL JS 6.16.0's src/geo/projection/globe_utils.ts and the helpers of src/util/util.ts
// it uses, BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
fn clamp(n : Double, min : Double, max : Double) -> Double {
  @cmp.minimum(max, @cmp.maximum(min, n))
}

///|
fn lerp(a : Double, b : Double, k : Double) -> Double {
  a * (1.0 - k) + b * k
}

///|
fn modulo(n : Double, m : Double) -> Double {
  (n % m + m) % m
}

///|
/// MapLibre's `wrap`: `n` in (`min`, `max`].
fn wrap(n : Double, min : Double, max : Double) -> Double {
  let d = max - min
  let w = ((n - min) % d + d) % d + min
  if w == min {
    max
  } else {
    w
  }
}

///|
fn remap_saturate(
  value : Double,
  old_min : Double,
  old_max : Double,
  new_min : Double,
  new_max : Double,
) -> Double {
  lerp(
    new_min,
    new_max,
    clamp((value - old_min) / (old_max - old_min), 0.0, 1.0),
  )
}

///|
fn degrees(radians : Double) -> Double {
  radians * 180.0 / @math.PI
}

///|
fn scale_zoom(scale : Double) -> Double {
  @math.ln(scale) / @math.ln(2.0)
}

///|
fn zoom_scale(zoom : Double) -> Double {
  @math.pow(2.0, zoom)
}

///|
/// The signed difference from `a` to `b` in degrees, the shorter way round.
fn angle_difference(a : Double, b : Double) -> Double {
  let a = modulo(a, 360.0)
  let b = modulo(b, 360.0)
  let d1 = b - a
  let d2 = if b > a { d1 - 360.0 } else { d1 + 360.0 }
  if d1.abs() < d2.abs() {
    d1
  } else {
    d2
  }
}

///|
fn radian_distance(a : Double, b : Double) -> Double {
  let a = modulo(a, @math.PI * 2.0)
  let b = modulo(b, @math.PI * 2.0)
  @cmp.minimum(
    (a - b).abs(),
    @cmp.minimum((a - b + @math.PI * 2.0).abs(), (a - b - @math.PI * 2.0).abs()),
  )
}

///|
/// The angle that turns vector 1 onto vector 2 (MapLibre's
/// `angleToRotateBetweenVectors2D`).
fn rotation_between(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Double {
  let l1 = (x1 * x1 + y1 * y1).sqrt()
  let l2 = (x2 * x2 + y2 * y2).sqrt()
  let (x1, y1, x2, y2) = (x1 / l1, y1 / l1, x2 / l2, y2 / l2)
  let angle = @math.acos(x1 * x2 + y1 * y2)
  if -y1 * x2 + x1 * y2 > 0.0 {
    angle
  } else {
    -angle
  }
}

///|
/// `lng` in (-180, 180] (MapLibre's `LngLat.wrap`).
fn wrapped(p : @core.LngLat) -> @core.LngLat {
  { lng: wrap(p.lng, -180.0, 180.0), lat: p.lat, }
}

///|
/// The point of the unit sphere at `lng`, `lat` (radians).
fn sphere_vector(lng : Double, lat : Double) -> Vec3 {
  let len = @math.cos(lat)
  { x: @math.sin(lng) * len, y: @math.sin(lat), z: @math.cos(lng) * len, }
}

///|
/// The point of the unit sphere at `p`.
pub fn surface_vector(p : @core.LngLat) -> Vec3 {
  sphere_vector(p.lng * @math.PI / 180.0, p.lat * @math.PI / 180.0)
}

///|
/// The longitude and latitude of a point of the unit sphere.
fn surface_point(v : Vec3) -> @core.LngLat {
  let lat = @math.asin(v.y) / @math.PI * 180.0
  let xz = (v.x * v.x + v.z * v.z).sqrt()
  if xz > 0.000001 {
    let acos_z = @math.acos(v.z / xz)
    let lng = (if v.x / xz > 0.0 { acos_z } else { -acos_z }) / @math.PI * 180.0
    { lng: wrap(lng, -180.0, 180.0), lat, }
  } else {
    { lng: 0.0, lat, }
  }
}

///|
/// The point of the unit sphere at `(x, y)` tile units (`extent` per edge) of
/// tile `z/tx/ty` (MapLibre's `projectTileCoordinatesToSphere`).
fn tile_vector(
  x : Double,
  y : Double,
  z : Int32,
  tx : Int32,
  ty : Int32,
  extent~ : Double = @core.TILE_EXTENT.to_double(),
) -> Vec3 {
  let scale = 1.0 / (1 << z).to_double()
  let mx = x / extent * scale + tx.to_double() * scale
  let my = y / extent * scale + ty.to_double() * scale
  sphere_vector(
    modulo(mx * @math.PI * 2.0 + @math.PI, @math.PI * 2.0),
    2.0 * @math.atan(@math.exp(@math.PI - my * @math.PI * 2.0)) - @math.PI * 0.5,
  )
}

///|
/// How much a parallel shrinks at `lat` degrees, the mercator limit beyond
/// which it stops (MapLibre's `planetScaleAtLatitude`).
pub fn planet_scale(lat : Double) -> Double {
  @math.cos(
    @cmp.minimum(lat.abs(), @core.MAX_VALID_LATITUDE) * @math.PI / 180.0,
  )
}

///|
/// The globe's radius in CSS pixels for a `world_size` mercator world centered
/// at `lat`: the globe is as large as the mercator map at the center.
fn globe_radius(world_size : Double, lat : Double) -> Double {
  world_size / (2.0 * @math.PI) / planet_scale(lat)
}

///|
/// The zoom change that keeps the globe the same size when the center moves
/// from `old_lat` to `new_lat` (MapLibre's `getZoomAdjustment`).
fn zoom_adjustment(old_lat : Double, new_lat : Double) -> Double {
  scale_zoom(planet_scale(new_lat) / planet_scale(old_lat))
}

///|
fn circumference(world_size : Double, lat : Double) -> Double {
  2.0 * @math.PI * globe_radius(world_size, lat)
}

///|
fn pixel_distance(
  world_size : Double,
  lat : Double,
  a : @core.LngLat,
  b : @core.LngLat,
) -> Double {
  let dot = clamp(surface_vector(a).dot(surface_vector(b)), -1.0, 1.0)
  @math.acos(dot) / (2.0 * @math.PI) * circumference(world_size, lat)
}

///|
fn integrate_sec(x : Double) -> Double {
  let s = @math.sin(0.5 * x)
  let c = @math.cos(0.5 * x)
  @math.ln(s + c) - @math.ln(c - s)
}

///|
/// The center a fraction `t` of the way from `start` by the given degrees, the
/// longitude paced so the move looks even on the globe (MapLibre's
/// `interpolateLngLatForGlobe`).
fn interpolate_center(
  start : @core.LngLat,
  d_lng : Double,
  d_lat : Double,
  t : Double,
) -> @core.LngLat {
  let lat = clamp(start.lat + d_lat * t, -90.0, 90.0)
  let max = @core.MAX_VALID_LATITUDE
  let start_lat = clamp(start.lat, -max, max)
  let end_lat = clamp(start.lat + d_lat, -max, max)
  if (end_lat - start_lat).abs() > 1.0 {
    let other_side = sign(end_lat) != sign(start_lat)
    let a = (if other_side { -start_lat.abs() } else { start_lat.abs() }) *
      @math.PI /
      180.0
    let b = end_lat.abs() * @math.PI / 180.0
    let v = integrate_sec(a + t * (b - a))
    let v0 = integrate_sec(a)
    let v1 = integrate_sec(b)
    { lng: start.lng + d_lng * ((v - v0) / (v1 - v0)), lat, }
  } else {
    { lng: start.lng + d_lng * t, lat, }
  }
}

///|
/// JavaScript's `Math.sign`.
fn sign(x : Double) -> Double {
  if x > 0.0 {
    1.0
  } else if x < 0.0 {
    -1.0
  } else {
    x
  }
}

///|
/// Where the ray from `origin` along unit `dir` meets the sphere of `radius`
/// about the center: the nearer and farther distances, None when it misses or
/// the sphere is behind.
fn ray_sphere(
  origin : Vec3,
  dir : Vec3,
  radius~ : Double = 1.0,
) -> (Double, Double)? {
  let od = origin.dot(dir)
  let inner = origin.sub(dir.scale(od))
  let disc = radius * radius - inner.dot(inner)
  if disc < 0.0 {
    return None
  }
  let c = origin.dot(origin) - radius * radius
  let q = -od + (if od < 0.0 { 1.0 } else { -1.0 }) * disc.sqrt()
  let t0 = c / q
  let t_max = @cmp.maximum(t0, q)
  if t_max < 0.0 {
    None
  } else {
    Some((@cmp.minimum(t0, q), t_max))
  }
}

///|
/// The share of the atmosphere drawn for a camera `altitude` pixels above a
/// globe of `radius` pixels (MapLibre's `getAtmosphereAltitudeBlend`).
pub fn atmosphere_blend(altitude : Double, radius : Double) -> Double {
  let height = radius * (100000.0 / 6371000.0)
  let x = clamp((altitude - height) / (9.0 * height), 0.0, 1.0)
  x * x * (3.0 - 2.0 * x)
}
