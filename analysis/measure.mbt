// Measures follow @turf/area, @turf/length, @turf/distance, @turf/centroid and
// @turf/bbox 7.4.0 (MIT License, Copyright (c) 2017 TurfJS). See NOTICE.

///|
/// The trigonometry measures use (`@core.Trig`): a wasm build passes the
/// host's `Math` to match Turf bit for bit; `@math` can differ in the last bit.
pub using @core {type Trig}

///|
/// Great-circle distance in meters between two lng/lat points (haversine).
pub fn distance(
  trig : Trig,
  lng1 : Double,
  lat1 : Double,
  lng2 : Double,
  lat2 : Double,
) -> Double {
  @core.haversine(trig, lng1, lat1, lng2, lat2) * @core.EARTH_RADIUS
}

///|
fn is_polygon(k : @geom.GeomKind) -> Bool {
  k is (Polygon | MultiPolygon)
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
      let (c0, c1) = t.points(r)
      let a = @core.turf_ring_area(trig, t.coords, c0, c1).abs()
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
  let (a, b) = t.feature_points(f)
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
