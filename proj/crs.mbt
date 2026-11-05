// The transform pipeline of proj4js 2.22.0 (lib/Proj.js, lib/transform.js,
// lib/deriveConstants.js, lib/datum.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

///|
/// The map projections a `Definition` can name, as PROJ calls them
/// (`+proj=...`).
pub(all) enum Method {
  LongLat
  Merc
  Tmerc
  Utm
  Lcc
  Aea
  Aeqd
  Stere
  Sterea
  Cass
  Laea
  Eqc
  Eqdc
  Sinu
  Eck6
  Moll
  Robin
  Cea
  Mill
  Poly
  Omerc
  Somerc
  Krovak
  Ortho
  Gnom
  Eqearth
  Bonne
}

///|
/// A parsed PROJ string: `a`, `b` in meters (`r_a`: the sphere of equal area), `towgs84` 3 or 7 Helmert
/// parameters in meters, arc seconds and ppm (empty for an unknown datum: no shifts), `to_meter` NaN for
/// meters, then the projection's parameters. Angles are in radians; NaN marks a parameter not given.
pub(all) struct Definition {
  mut proj : Method
  mut a : Double
  mut b : Double
  mut r_a : Bool
  mut towgs84 : Array[Double]
  mut datum_wgs84 : Bool
  mut to_meter : Double
  mut from_greenwich : Double
  mut long_wrap : Double
  mut lat0 : Double
  mut lat1 : Double
  mut lat2 : Double
  mut lat_ts : Double
  mut long0 : Double
  mut long1 : Double
  mut long2 : Double
  mut alpha : Double
  mut gamma : Double
  mut longc : Double
  mut x0 : Double
  mut y0 : Double
  mut k0 : Double
  mut zone : Int32
  mut south : Bool
  mut no_uoff : Bool
  mut no_rot : Bool
  mut czech : Bool
}

///|
/// A definition of `method` on the ellipsoid with semi-axes `a` and `b`,
/// with no datum shift and no other parameter given.
pub fn Definition::new(proj : Method, a : Double, b : Double) -> Definition {
  let nan = @double.not_a_number
  {
    proj,
    a,
    b,
    r_a: false,
    towgs84: [],
    datum_wgs84: false,
    to_meter: nan,
    from_greenwich: 0.0,
    long_wrap: nan,
    lat0: nan,
    lat1: nan,
    lat2: nan,
    lat_ts: nan,
    long0: nan,
    long1: nan,
    long2: nan,
    alpha: nan,
    gamma: nan,
    longc: nan,
    x0: nan,
    y0: nan,
    k0: nan,
    zone: 0,
    south: false,
    no_uoff: false,
    no_rot: false,
    czech: false,
  }
}

///|
/// What every projection reads from its definition: the ellipsoid (`es`,
/// `e`, `ep2` derived as proj4js does; `sphere` when the axes are equal) and
/// the origin, with missing values defaulted.
priv struct Base {
  m : Trig
  a : Double
  b : Double
  rf : Double
  es : Double
  e : Double
  sphere : Bool
  lat0 : Double
  long0 : Double
  x0 : Double
  y0 : Double
  k0 : Double
}

///|
fn base(d : Definition, m : Trig) -> Base {
  let sphere = (d.a - d.b).abs() < EPSLN
  let b = if sphere { d.a } else { d.b }
  let mut a = d.a
  let mut es = (a * a - b * b) / (a * a)
  if d.r_a {
    a *= 1.0 -
      es *
      (
        0.1666666666666666667 +
        es * (0.04722222222222222222 + es * 0.02215608465608465608)
      )
    es = 0.0
  }
  let given = (x : Double) => if x.is_nan() { 0.0 } else { x }
  {
    m,
    a,
    b,
    rf: d.a / (d.a - b),
    es,
    e: es.sqrt(),
    sphere,
    lat0: given(d.lat0),
    long0: given(d.long0),
    x0: given(d.x0),
    y0: given(d.y0),
    k0: or(d.k0, 1.0),
  }
}

///|
priv enum Projection {
  LongLat
  Merc(Merc)
  Tmerc(Etmerc)
  Lcc(Lcc)
  Aea(Aea)
  Aeqd(Aeqd)
  Stere(Stere)
  Sterea(Sterea)
  Cass(Cass)
  Laea(Laea)
  Eqc(Eqc)
  Eqdc(Eqdc)
  Sinu(Sinu)
  Moll(Base)
  Robin(Base)
  Cea(Cea)
  Mill(Base)
  Poly(Poly)
  Omerc(Omerc)
  Somerc(Somerc)
  Krovak(Krovak)
  Ortho(Ortho)
  Gnom(Ortho)
  Eqearth(Eqearth)
  Bonne(Bonne)
}

///|
/// A coordinate reference system: from an EPSG code (`from_epsg`) or a
/// parsed PROJ string (`new`).
pub struct Crs {
  priv m : Trig
  priv projection : Projection
  priv datum : Datum
  priv datum_wgs84 : Bool
  priv to_meter : Double
  priv from_greenwich : Double
  priv long_wrap : Double
}

///|
/// The CRS `d` defines, computing with `trig`; None if its parameters are out of the projection's
/// domain (an oblique Mercator without a line, a transverse Mercator on a
/// sphere, a UTM zone outside 1-60, ...).
pub fn Crs::new(d : Definition, trig~ : Trig = Trig::moonbit()) -> Crs? {
  let m = trig
  guard d.a > 0.0 &&
    d.a < 1.0e300 &&
    d.b > 0.0 &&
    d.b <= d.a &&
    (d.to_meter.is_nan() || d.to_meter > 0.0) &&
    d.from_greenwich.abs() <= PI else {
    return None
  }
  let d = { ..d, lat1: or(d.lat1, d.lat0), }
  let p = base(d, m)
  let projection : Projection = match d.proj {
    LongLat => LongLat
    Merc => Merc(Merc::new(p, d))
    Tmerc | Utm => {
      guard p.es > 0.0 else { return None }
      if d.proj is Utm {
        let zone = if d.zone == 0 {
          @math.floor((adjust_lon(p.long0) + PI) * 30.0 / PI).to_int() + 1
        } else {
          d.zone.abs()
        }
        guard zone >= 1 && zone <= 60 else { return None }
        Tmerc(
          Etmerc::new(
            m,
            p.es,
            p.a,
            0.0,
            (6 * zone - 183).to_double() * D2R,
            0.9996,
            500000.0,
            if d.south {
              10000000.0
            } else {
              0.0
            },
          ),
        )
      } else {
        Tmerc(
          Etmerc::new(
            m,
            p.es,
            p.a,
            p.lat0,
            p.long0,
            if d.k0.is_nan() {
              1.0
            } else {
              d.k0
            },
            p.x0,
            p.y0,
          ),
        )
      }
    }
    Lcc => Lcc(Lcc::new(p, d))
    Aea => Aea(Aea::new(p, d))
    Aeqd => Aeqd(Aeqd::new(p))
    Stere => Stere(Stere::new(p, d))
    Sterea => Sterea(Sterea::new(p))
    Cass => Cass(Cass::new(p))
    Laea => Laea(Laea::new(p))
    Eqc => Eqc(Eqc::new(p, d))
    Eqdc => Eqdc(Eqdc::new(p, d))
    Sinu => Sinu(Sinu::new(p, false))
    Eck6 => Sinu(Sinu::new(p, true))
    Moll => Moll(p)
    Robin => Robin(p)
    Cea => Cea(Cea::new(p, d))
    Mill => Mill(p)
    Poly => Poly(Poly::new(p))
    Omerc =>
      match Omerc::new(p, d) {
        Some(o) => Omerc(o)
        None => return None
      }
    Somerc => Somerc(Somerc::new(p))
    Krovak => Krovak(Krovak::new(p, d))
    Ortho => Ortho(Ortho::new(p))
    Gnom => Gnom(Ortho::new(p))
    Eqearth => Eqearth(Eqearth::new(p))
    Bonne =>
      match Bonne::new(p, d) {
        Some(b) => Bonne(b)
        None => return None
      }
  }
  Some({
    m,
    projection,
    datum: Datum::new(d.towgs84, d.a, p.b),
    datum_wgs84: d.datum_wgs84,
    to_meter: d.to_meter,
    from_greenwich: d.from_greenwich,
    long_wrap: d.long_wrap,
  })
}

///|
/// Whether the CRS's coordinates are longitude and latitude in degrees.
pub fn Crs::is_geographic(self : Crs) -> Bool {
  self.projection is LongLat
}

///|
fn finite(p : (Double, Double)) -> (Double, Double)? {
  if p.0 - p.0 == 0.0 && p.1 - p.1 == 0.0 {
    Some(p)
  } else {
    None
  }
}

///|
/// This CRS's coordinates to longitude and latitude in radians on its own
/// datum and from Greenwich.
fn Crs::to_geodetic(self : Crs, x : Double, y : Double) -> (Double, Double) {
  let m = self.m
  let (lon, lat) = match self.projection {
    LongLat => (x * D2R, y * D2R)
    projection => {
      let (x, y) = if self.to_meter.is_nan() || self.to_meter == 0.0 {
        (x, y)
      } else {
        (x * self.to_meter, y * self.to_meter)
      }
      match projection {
        LongLat => (x, y)
        Merc(m) => m.inverse(x, y)
        Tmerc(t) => t.inverse(x, y)
        Lcc(l) => l.inverse(x, y)
        Aea(l) => l.inverse(x, y)
        Aeqd(l) => l.inverse(x, y)
        Stere(l) => l.inverse(x, y)
        Sterea(l) => l.inverse(x, y)
        Cass(l) => l.inverse(x, y)
        Laea(l) => l.inverse(x, y)
        Eqc(l) => l.inverse(x, y)
        Eqdc(l) => l.inverse(x, y)
        Sinu(l) => l.inverse(x, y)
        Moll(p) => moll_inverse(m, p, x, y)
        Robin(p) => robin_inverse(p, x, y)
        Cea(l) => l.inverse(x, y)
        Mill(p) => mill_inverse(m, p, x, y)
        Poly(l) => l.inverse(x, y)
        Omerc(l) => l.inverse(x, y)
        Somerc(l) => l.inverse(x, y)
        Krovak(l) => l.inverse(x, y)
        Ortho(l) => l.inverse(x, y)
        Gnom(l) => l.gnom_inverse(x, y)
        Eqearth(l) => l.inverse(x, y)
        Bonne(l) => l.inverse(x, y)
      }
    }
  }
  (lon + self.from_greenwich, lat)
}

///|
/// Longitude and latitude in radians on this CRS's datum to its coordinates.
fn Crs::from_geodetic(
  self : Crs,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.m
  let lon = lon - self.from_greenwich
  let xy = match self.projection {
    LongLat => {
      let lon = if self.long_wrap.is_nan() {
        lon
      } else {
        self.long_wrap + adjust_lon(lon - self.long_wrap)
      }
      return (lon * R2D, lat * R2D)
    }
    Merc(m) => m.forward(lon, lat)
    Tmerc(t) => t.forward(lon, lat)
    Lcc(l) => l.forward(lon, lat)
    Aea(l) => l.forward(lon, lat)
    Aeqd(l) => l.forward(lon, lat)
    Stere(l) => l.forward(lon, lat)
    Sterea(l) => l.forward(lon, lat)
    Cass(l) => l.forward(lon, lat)
    Laea(l) => l.forward(lon, lat)
    Eqc(l) => l.forward(lon, lat)
    Eqdc(l) => l.forward(lon, lat)
    Sinu(l) => l.forward(lon, lat)
    Moll(p) => moll_forward(m, p, lon, lat)
    Robin(p) => robin_forward(p, lon, lat)
    Cea(l) => l.forward(lon, lat)
    Mill(p) => mill_forward(m, p, lon, lat)
    Poly(l) => l.forward(lon, lat)
    Omerc(l) => l.forward(lon, lat)
    Somerc(l) => l.forward(lon, lat)
    Krovak(l) => l.forward(lon, lat)
    Ortho(l) => l.forward(lon, lat)
    Gnom(l) => l.gnom_forward(lon, lat)
    Eqearth(l) => l.forward(lon, lat)
    Bonne(l) => l.forward(lon, lat)
  }
  let (x, y) = xy
  if self.to_meter.is_nan() || self.to_meter == 0.0 {
    (x, y)
  } else {
    (x / self.to_meter, y / self.to_meter)
  }
}

///|
/// Whether proj4js goes through WGS 84 first (`checkNotWGS`): a CRS with a
/// Helmert shift paired with one not declared `+datum=WGS84`.
fn not_wgs(from : Crs, to : Crs) -> Bool {
  (from.datum.shifts() && !to.datum_wgs84) ||
  (to.datum.shifts() && !from.datum_wgs84)
}

///|
/// (`x`, `y`) in `from` as coordinates of `to`, shifting datums through
/// WGS 84 where both are known; None where a projection cannot reach the
/// point or the input is not finite.
pub fn transform(
  from : Crs,
  to : Crs,
  x : Double,
  y : Double,
) -> (Double, Double)? {
  if physical_equal(from, to) {
    return finite((x, y))
  }
  let m = from.m
  // NaN and infinities run through to the one check at the end.
  let (lon, lat) = from.to_geodetic(x, y)
  let p = if not_wgs(from, to) {
    let p = datum_transform(m, from.datum, wgs84_datum, (lon, lat, 0.0))
    // proj4js returns the intermediate point in degrees, without its height.
    let p = (p.0 * R2D * D2R, p.1 * R2D * D2R, 0.0)
    datum_transform(m, wgs84_datum, to.datum, p)
  } else {
    datum_transform(m, from.datum, to.datum, (lon, lat, 0.0))
  }
  finite(to.from_geodetic(p.0, p.1))
}
