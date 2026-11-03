///|
const PI : Double = 3.141592653589793

///|
/// GRS80's semi-major axis in meters and first eccentricity squared.
const GRS80_A : Double = 6378137.0

///|
const GRS80_E2 : Double = 0.00669438002290

///|
fn radians(d : Double) -> Double {
  d * PI / 180.0
}

///|
fn degrees(r : Double) -> Double {
  r * 180.0 / PI
}

///|
/// The ellipsoid's radii of curvature at latitude `lat` (degrees): along the
/// meridian (M, north-south) and the prime vertical (N, east-west).
fn curvature_radii(lat : Double) -> (Double, Double) {
  let s = @math.sin(radians(lat))
  let w = 1.0 - GRS80_E2 * s * s
  (GRS80_A * (1.0 - GRS80_E2) / (w * w.sqrt()), GRS80_A / w.sqrt())
}

///|
/// A plane in meters around (`lon0`, `lat0`), true to distances from it: an
/// azimuthal equidistant projection on the unit sphere scaled east-west by the
/// ellipsoid's N and north-south by its M there.
priv struct LocalPlane {
  lon0 : Double
  lat0 : Double
  sin0 : Double
  cos0 : Double
  rx : Double
  ry : Double
}

///|
fn LocalPlane::new(lon0 : Double, lat0 : Double) -> LocalPlane {
  let p = radians(lat0)
  let (m, n) = curvature_radii(lat0)
  { lon0, lat0, sin0: @math.sin(p), cos0: @math.cos(p), rx: n, ry: m, }
}

///|
fn LocalPlane::forward(
  self : LocalPlane,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let p = radians(lat)
  let dl = radians(lon - self.lon0)
  let sp = @math.sin(p)
  let cp = @math.cos(p)
  let cos_c = self.sin0 * sp + self.cos0 * cp * @math.cos(dl)
  let c = @math.acos(@cmp.maximum(-1.0, @cmp.minimum(1.0, cos_c)))
  let k = if c < 1.0e-12 { 1.0 } else { c / @math.sin(c) }
  (
    self.rx * k * cp * @math.sin(dl),
    self.ry * k * (self.cos0 * sp - self.sin0 * cp * @math.cos(dl)),
  )
}

///|
fn LocalPlane::inverse(
  self : LocalPlane,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let x = x / self.rx
  let y = y / self.ry
  let rho = (x * x + y * y).sqrt()
  if rho < 1.0e-15 {
    return (self.lon0, self.lat0)
  }
  let c = rho
  let sc = @math.sin(c)
  let cc = @math.cos(c)
  let lat = @math.asin(
    @cmp.maximum(
      -1.0,
      @cmp.minimum(1.0, cc * self.sin0 + y * sc * self.cos0 / rho),
    ),
  )
  let lon = @math.atan2(x * sc, rho * self.cos0 * cc - y * self.sin0 * sc)
  (self.lon0 + degrees(lon), degrees(lat))
}
