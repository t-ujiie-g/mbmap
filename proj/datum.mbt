// Port of proj4js 2.22.0's datum shifts (lib/datum.js, lib/datum_transform.js,
// lib/datumUtils.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

///|
/// How a datum shifts to WGS 84: `Unknown` (no `towgs84`: never shifted),
/// `Wgs84` (a zero shift), or a Helmert shift of three or seven parameters
/// (rotations in radians, the scale as a factor).
#derive(Eq)
priv enum DatumKind {
  Unknown
  Wgs84
  ThreeParam
  SevenParam
}

///|
/// A datum: its Helmert shift to WGS 84 and its ellipsoid.
priv struct Datum {
  kind : DatumKind
  params : FixedArray[Double]
  a : Double
  b : Double
  es : Double
}

///|
const SEC_TO_RAD : Double = 4.84813681109535993589914102357e-6

///|
fn Datum::new(towgs84 : Array[Double], a : Double, b : Double) -> Datum {
  let params = FixedArray::make(7, 0.0)
  for i, v in towgs84 {
    if i < 7 {
      params[i] = v
    }
  }
  let mut kind = if towgs84.is_empty() { Unknown } else { Wgs84 }
  if params[0] != 0.0 || params[1] != 0.0 || params[2] != 0.0 {
    kind = ThreeParam
  }
  if towgs84.length() > 3 &&
    (
      params[3] != 0.0 ||
      params[4] != 0.0 ||
      params[5] != 0.0 ||
      params[6] != 0.0
    ) {
    kind = SevenParam
    for i in 3..<6 {
      params[i] *= SEC_TO_RAD
    }
    params[6] = params[6] / 1000000.0 + 1.0
  }
  { kind, params, a, b, es: (a * a - b * b) / (a * a), }
}

///|
let wgs84_datum : Datum = Datum::new(
  [0.0, 0.0, 0.0],
  6378137.0,
  6356752.314245179,
)

///|
fn Datum::shifts(self : Datum) -> Bool {
  self.kind is (ThreeParam | SevenParam)
}

///|
fn Datum::same(self : Datum, other : Datum) -> Bool {
  if self.kind != other.kind ||
    self.a != other.a ||
    (self.es - other.es).abs() > 0.000000000050 {
    return false
  }
  let n = match self.kind {
    ThreeParam => 3
    SevenParam => 7
    _ => 0
  }
  for i in 0..<n {
    if self.params[i] != other.params[i] {
      return false
    }
  }
  true
}

///|
/// Longitude, latitude (radians) and height on `from` to the same on `to`.
fn datum_transform(
  m : Trig,
  from : Datum,
  to : Datum,
  p : (Double, Double, Double),
) -> (Double, Double, Double) {
  if from.same(to) || from.kind is Unknown || to.kind is Unknown {
    return p
  }
  if from.es == to.es && from.a == to.a && !from.shifts() && !to.shifts() {
    return p
  }
  let g = geodetic_to_geocentric(m, p, from.es, from.a)
  let g = from.to_wgs84(g)
  let g = to.from_wgs84(g)
  geocentric_to_geodetic(m, g, to.es, to.a, to.b)
}

///|
fn geodetic_to_geocentric(
  m : Trig,
  p : (Double, Double, Double),
  es : Double,
  a : Double,
) -> (Double, Double, Double) {
  let (lon, lat, h) = p
  let lat = if lat < -HALF_PI && lat > -1.001 * HALF_PI {
    -HALF_PI
  } else if lat > HALF_PI && lat < 1.001 * HALF_PI {
    HALF_PI
  } else if lat.abs() > HALF_PI {
    return (@double.not_a_number, @double.not_a_number, h)
  } else {
    lat
  }
  let lon = if lon > PI { lon - 2.0 * PI } else { lon }
  let sin_lat = m.sin(lat)
  let cos_lat = m.cos(lat)
  let rn = a / (1.0 - es * sin_lat * sin_lat).sqrt()
  (
    (rn + h) * cos_lat * m.cos(lon),
    (rn + h) * cos_lat * m.sin(lon),
    (rn * (1.0 - es) + h) * sin_lat,
  )
}

///|
/// Geocentric to geodetic by the iteration of the Institut für Erdmessung,
/// Hannover (to 1e-12 rad).
fn geocentric_to_geodetic(
  m : Trig,
  g : (Double, Double, Double),
  es : Double,
  a : Double,
  b : Double,
) -> (Double, Double, Double) {
  let genau = 1.0e-12
  let (x, y, z) = g
  let p = (x * x + y * y).sqrt()
  let rr = (x * x + y * y + z * z).sqrt()
  let lon = if p / a < genau {
    if rr / a < genau {
      return (0.0, HALF_PI, -b)
    }
    0.0
  } else {
    m.atan2(y, x)
  }
  let ct = z / rr
  let st = p / rr
  let mut rx = 1.0 / (1.0 - es * (2.0 - es) * st * st).sqrt()
  let mut cphi0 = st * (1.0 - es) * rx
  let mut sphi0 = ct * rx
  let mut height = 0.0
  for _ in 0..<30 {
    let rn = a / (1.0 - es * sphi0 * sphi0).sqrt()
    height = p * cphi0 + z * sphi0 - rn * (1.0 - es * sphi0 * sphi0)
    let rk = es * rn / (rn + height)
    rx = 1.0 / (1.0 - rk * (2.0 - rk) * st * st).sqrt()
    let cphi = st * (1.0 - rk) * rx
    let sphi = ct * rx
    let sdphi = sphi * cphi0 - cphi * sphi0
    cphi0 = cphi
    sphi0 = sphi
    if sdphi * sdphi <= genau * genau {
      break
    }
  }
  (lon, m.atan(sphi0 / cphi0.abs()), height)
}

///|
fn Datum::to_wgs84(
  self : Datum,
  g : (Double, Double, Double),
) -> (Double, Double, Double) {
  let (x, y, z) = g
  let p = self.params
  match self.kind {
    ThreeParam => (x + p[0], y + p[1], z + p[2])
    SevenParam =>
      (
        p[6] * (x - p[5] * y + p[4] * z) + p[0],
        p[6] * (p[5] * x + y - p[3] * z) + p[1],
        p[6] * (-p[4] * x + p[3] * y + z) + p[2],
      )
    _ => g
  }
}

///|
fn Datum::from_wgs84(
  self : Datum,
  g : (Double, Double, Double),
) -> (Double, Double, Double) {
  let (x, y, z) = g
  let p = self.params
  match self.kind {
    ThreeParam => (x - p[0], y - p[1], z - p[2])
    SevenParam => {
      let x = (x - p[0]) / p[6]
      let y = (y - p[1]) / p[6]
      let z = (z - p[2]) / p[6]
      (
        x + p[5] * y - p[4] * z,
        -p[5] * x + y + p[3] * z,
        p[4] * x - p[3] * y + z,
      )
    }
    _ => g
  }
}
