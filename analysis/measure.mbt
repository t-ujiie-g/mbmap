// Measures follow @turf/area, @turf/length, @turf/distance, @turf/centroid and
// @turf/bbox 7.4.0 (MIT License, Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// Turf's mean earth radius in meters.
const EARTH_RADIUS : Double = 6371008.8

///|
/// The trigonometry measures use (`@core.Trig`): a wasm build passes the
/// host's `Math` to match Turf bit for bit; `@math` can differ in the last bit.
pub using @core {type Trig}

///|
/// Turf's `degreesToRadians`, which first takes the degrees modulo 360.
fn radians(degrees : Double) -> Double {
  degrees % 360.0 * @math.PI / 180.0
}

///|
/// Great-circle distance in meters between two lng/lat points (haversine).
pub fn distance(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  let d_lat = radians(lat2 - lat1)
  let d_lng = radians(lng2 - lng1)
  let s_lat = (trig.sin)(d_lat / 2.0)
  let s_lng = (trig.sin)(d_lng / 2.0)
  let a = s_lat * s_lat +
    s_lng * s_lng * (trig.cos)(radians(lat1)) * (trig.cos)(radians(lat2))
  2.0 * (trig.atan2)(a.sqrt(), (1.0 - a).sqrt()) * EARTH_RADIUS
}

///|
fn is_polygon(k : @geom.GeomKind) -> Bool {
  k is (Polygon | MultiPolygon)
}

///|
/// Signed spherical area of ring `r` (Turf's `ringArea`; the ring repeats its
/// first point at the end).
fn ring_area(t : @geom.Table, trig : Trig, r : Int32) -> Double {
  let (p0, p1) = t.points(r)
  let n = p1 - p0 - 1
  if n <= 2 {
    return 0.0
  }
  let c = t.coords
  let to_rad = @math.PI / 180.0
  let mut total = 0.0
  for i in 0..<n {
    let middle = if i + 1 == n { 0 } else { i + 1 }
    let upper = if i + 2 >= n { (i + 2) % n } else { i + 2 }
    let lower_x = c[(p0 + i) * 2] * to_rad
    let middle_y = c[(p0 + middle) * 2 + 1] * to_rad
    let upper_x = c[(p0 + upper) * 2] * to_rad
    total += (upper_x - lower_x) * (trig.sin)(middle_y)
  }
  total * (EARTH_RADIUS * EARTH_RADIUS / 2.0)
}

///|
/// Feature `f`'s area in square meters: exteriors minus holes; 0 for points
/// and lines.
pub fn area(t : @geom.Table, trig : Trig, f : Int32) -> Double {
  guard is_polygon(t.kinds[f]) else { return 0.0 }
  let (p0, p1) = t.parts(f)
  let mut total = 0.0
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    let mut poly = 0.0
    for r in r0..<r1 {
      let a = ring_area(t, trig, r).abs()
      poly = if r == r0 { poly + a } else { poly - a }
    }
    total += poly
  }
  total
}

///|
/// Feature `f`'s length in meters: every segment of its lines or rings; 0 for
/// points.
pub fn length(t : @geom.Table, trig : Trig, f : Int32) -> Double {
  if t.kinds[f] is (NoGeometry | Point | MultiPoint) {
    return 0.0
  }
  let c = t.coords
  let (p0, p1) = t.parts(f)
  if p1 == p0 {
    return 0.0
  }
  let (r0, _) = t.rings(p0)
  let (_, r1) = t.rings(p1 - 1)
  let mut total = 0.0
  for r in r0..<r1 {
    let (a, b) = t.points(r)
    for i in a..<(b - 1) {
      total += distance(
        trig,
        c[i * 2],
        c[i * 2 + 1],
        c[i * 2 + 2],
        c[i * 2 + 3],
      )
    }
  }
  total
}

///|
/// The points of feature `f` as a range of point indices.
fn point_range(t : @geom.Table, f : Int32) -> (Int32, Int32) {
  let (p0, p1) = t.parts(f)
  if p1 == p0 {
    return (0, 0)
  }
  let (r0, _) = t.rings(p0)
  let (_, r1) = t.rings(p1 - 1)
  if r1 == r0 {
    return (0, 0)
  }
  (t.points(r0).0, t.points(r1 - 1).1)
}

///|
/// The mean of feature `f`'s points, leaving out each polygon ring's closing
/// point (Turf's `centroid`); NaN without geometry.
pub fn centroid(t : @geom.Table, f : Int32) -> (Double, Double) {
  let c = t.coords
  let skip_last = is_polygon(t.kinds[f])
  let (p0, p1) = t.parts(f)
  let mut x = 0.0
  let mut y = 0.0
  let mut n = 0
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (a, b) = t.points(r)
      let end = if skip_last { b - 1 } else { b }
      for i in a..<end {
        x += c[i * 2]
        y += c[i * 2 + 1]
        n += 1
      }
    }
  }
  (x / n.to_double(), y / n.to_double())
}

///|
/// Feature `f`'s box as (min x, min y, max x, max y); infinite and inverted
/// without geometry.
pub fn bbox(t : @geom.Table, f : Int32) -> (Double, Double, Double, Double) {
  let c = t.coords
  let (a, b) = point_range(t, f)
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for i in a..<b {
    let x = c[i * 2]
    let y = c[i * 2 + 1]
    if x0 > x {
      x0 = x
    }
    if y0 > y {
      y0 = y
    }
    if x1 < x {
      x1 = x
    }
    if y1 < y {
      y1 = y
    }
  }
  (x0, y0, x1, y1)
}
