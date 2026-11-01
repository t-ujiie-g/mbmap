///|
/// A reference ellipsoid: semi-major axis in meters and inverse flattening.
pub(all) struct Ellipsoid {
  a : Double
  rf : Double
}

///|
pub let wgs84 : Ellipsoid = { a: 6378137.0, rf: 298.257223563, }

///|
pub let grs80 : Ellipsoid = { a: 6378137.0, rf: 298.257222101, }

///|
/// The first eccentricity squared, as proj4js derives it from a and b.
fn Ellipsoid::es(self : Ellipsoid) -> Double {
  let b = (1.0 - 1.0 / self.rf) * self.a
  (self.a * self.a - b * b) / (self.a * self.a)
}

///|
priv enum Projection {
  LonLat
  /// Spherical Mercator on a sphere of radius `a` (EPSG:3857).
  Mercator(a~ : Double)
  TransverseMercator(Etmerc)
}

///|
/// A coordinate reference system by EPSG code. WGS 84, JGD2000 and JGD2011
/// are treated as one datum (they differ by centimeters at most in Japan).
pub struct Crs {
  code : Int32
  priv projection : Projection
}

///|
/// Origins of Japan's plane rectangular zones I-XIX: latitude, then
/// longitude in degrees and minutes (GSI; EPSG 6669-6687 and 2443-2461).
let plane_origins : FixedArray[(Double, Double, Double)] = [
  (33.0, 129.0, 30.0),
  (33.0, 131.0, 0.0),
  (36.0, 132.0, 10.0),
  (33.0, 133.0, 30.0),
  (36.0, 134.0, 20.0),
  (36.0, 136.0, 0.0),
  (36.0, 137.0, 10.0),
  (36.0, 138.0, 30.0),
  (36.0, 139.0, 50.0),
  (40.0, 140.0, 50.0),
  (44.0, 140.0, 15.0),
  (44.0, 142.0, 15.0),
  (44.0, 144.0, 15.0),
  (26.0, 142.0, 0.0),
  (26.0, 127.0, 30.0),
  (26.0, 124.0, 0.0),
  (26.0, 131.0, 0.0),
  (20.0, 136.0, 0.0),
  (26.0, 154.0, 0.0),
]

///|
fn plane(e : Ellipsoid, zone : Int32) -> Projection {
  let (lat, deg, min) = plane_origins[zone - 1]
  TransverseMercator(
    Etmerc::new(e, lat * D2R, (deg + min / 60.0) * D2R, 0.9999, 0.0, 0.0),
  )
}

///|
fn utm(e : Ellipsoid, zone : Int32, south : Bool) -> Projection {
  TransverseMercator(
    Etmerc::new(
      e,
      0.0,
      (6 * zone - 183).to_double() * D2R,
      0.9996,
      500000.0,
      if south {
        10000000.0
      } else {
        0.0
      },
    ),
  )
}

///|
/// The CRS with EPSG `code`, if supported: longitude and latitude (4326,
/// 4612, 6668), Web Mercator (3857, 3785, 900913), Japan's plane rectangular
/// zones on JGD2011 (6669-6687) and JGD2000 (2443-2461), UTM on WGS 84
/// (32601-32660 north, 32701-32760 south), JGD2011 (6688-6692, zones 51-55)
/// and JGD2000 (3097-3101). Projected axes are easting, then northing.
pub fn Crs::from_epsg(code : Int32) -> Crs? {
  let projection = match code {
    4326 | 4612 | 6668 => LonLat
    3857 | 3785 | 900913 => Mercator(a=wgs84.a)
    c if c >= 6669 && c <= 6687 => plane(grs80, c - 6668)
    c if c >= 2443 && c <= 2461 => plane(grs80, c - 2442)
    c if c >= 32601 && c <= 32660 => utm(wgs84, c - 32600, false)
    c if c >= 32701 && c <= 32760 => utm(wgs84, c - 32700, true)
    c if c >= 6688 && c <= 6692 => utm(grs80, c - 6688 + 51, false)
    c if c >= 3097 && c <= 3101 => utm(grs80, c - 3097 + 51, false)
    _ => return None
  }
  Some({ code, projection, })
}

///|
/// Whether the CRS's coordinates are longitude and latitude in degrees.
pub fn Crs::is_geographic(self : Crs) -> Bool {
  self.projection is LonLat
}

///|
/// Longitude and latitude in degrees to this CRS's coordinates; None where
/// the projection cannot reach (a pole in Web Mercator, far from a transverse
/// Mercator's meridian).
pub fn Crs::forward(
  self : Crs,
  lon : Double,
  lat : Double,
) -> (Double, Double)? {
  match self.projection {
    LonLat => Some((lon, lat))
    Mercator(a~) => {
      let lat = lat * D2R
      if (lat.abs() - PI / 2.0).abs() <= 1.0e-10 {
        return None
      }
      Some(
        (
          a * adjust_lon(lon * D2R),
          a * @math.ln(@math.tan(PI / 4.0 + 0.5 * lat)),
        ),
      )
    }
    TransverseMercator(t) => t.forward(lon * D2R, lat * D2R)
  }
}

///|
/// This CRS's coordinates to longitude and latitude in degrees.
pub fn Crs::inverse(self : Crs, x : Double, y : Double) -> (Double, Double)? {
  match self.projection {
    LonLat => Some((x, y))
    Mercator(a~) =>
      Some(
        (
          adjust_lon(x / a) * R2D,
          (PI / 2.0 - 2.0 * @math.atan(@math.exp(-y / a))) * R2D,
        ),
      )
    TransverseMercator(t) =>
      match t.inverse(x, y) {
        Some((lon, lat)) => Some((lon * R2D, lat * R2D))
        None => None
      }
  }
}

///|
/// (`x`, `y`) in `from` as coordinates of `to`; None if either projection
/// cannot reach the point.
pub fn transform(
  from : Crs,
  to : Crs,
  x : Double,
  y : Double,
) -> (Double, Double)? {
  if from.code == to.code {
    return Some((x, y))
  }
  match from.inverse(x, y) {
    Some((lon, lat)) => to.forward(lon, lat)
    None => None
  }
}
