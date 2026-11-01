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
/// A definition of `proj` on the ellipsoid of semi-major axis `a` and
/// inverse flattening `rf`, with the Helmert shift `towgs84`.
fn on(
  proj : Method,
  a : Double,
  rf : Double,
  towgs84 : Array[Double],
) -> Definition {
  let d = Definition::new(proj, a, (1.0 - 1.0 / rf) * a)
  d.towgs84 = towgs84
  d
}

///|
fn wgs84(proj : Method) -> Definition {
  let d = on(proj, 6378137.0, 298.257223563, [0.0, 0.0, 0.0])
  d.datum_wgs84 = true
  d
}

///|
fn grs80(proj : Method) -> Definition {
  on(proj, 6378137.0, 298.257222101, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
}

///|
/// The Tokyo datum on Bessel 1841, by the 3-parameter shift EPSG gives for
/// Japan (EPSG:15484).
fn tokyo(proj : Method) -> Definition {
  on(proj, 6377397.155, 299.1528128, [
    -146.414, 507.337, 680.507, 0.0, 0.0, 0.0, 0.0,
  ])
}

///|
fn plane(d : Definition, zone : Int32) -> Definition {
  let (lat, deg, min) = plane_origins[zone - 1]
  d.lat0 = lat * D2R
  d.long0 = (deg + min / 60.0) * D2R
  d.k0 = 0.9999
  d.x0 = 0.0
  d.y0 = 0.0
  d
}

///|
fn utm(d : Definition, zone : Int32, south~ : Bool = false) -> Definition {
  d.zone = zone
  d.south = south
  d
}

///|
/// The CRS with EPSG `code`, if this table has it:
/// - longitude and latitude: 4326 (WGS 84), 4612 (JGD2000), 6668 (JGD2011),
///   4301 (Tokyo);
/// - Web Mercator: 3857 (and 3785, 900913);
/// - Japan's plane rectangular zones I-XIX: 6669-6687 (JGD2011), 2443-2461
///   (JGD2000), 30161-30179 (Tokyo);
/// - UTM: 32601-32660 and 32701-32760 (WGS 84 north and south), 6688-6692
///   (JGD2011, zones 51-55), 3097-3101 (JGD2000), 3092-3096 (Tokyo).
///
/// Other CRSs are made from their PROJ strings (`Crs::new`). Projected axes
/// are easting, then northing; `trig` is as for `Crs::new`.
pub fn Crs::from_epsg(code : Int32, trig~ : Trig = Trig::moonbit()) -> Crs? {
  let d = match code {
    4326 => wgs84(LongLat)
    4612 | 6668 => grs80(LongLat)
    4301 => tokyo(LongLat)
    3857 | 3785 | 900913 => {
      let d = Definition::new(Merc, 6378137.0, 6378137.0)
      d.lat_ts = 0.0
      d.long0 = 0.0
      d.x0 = 0.0
      d.y0 = 0.0
      d.k0 = 1.0
      d
    }
    c if c >= 6669 && c <= 6687 => plane(grs80(Tmerc), c - 6668)
    c if c >= 2443 && c <= 2461 => plane(grs80(Tmerc), c - 2442)
    c if c >= 30161 && c <= 30179 => plane(tokyo(Tmerc), c - 30160)
    c if c >= 32601 && c <= 32660 => utm(wgs84(Utm), c - 32600)
    c if c >= 32701 && c <= 32760 => utm(wgs84(Utm), c - 32700, south=true)
    c if c >= 6688 && c <= 6692 => utm(grs80(Utm), c - 6688 + 51)
    c if c >= 3097 && c <= 3101 => utm(grs80(Utm), c - 3097 + 51)
    c if c >= 3092 && c <= 3096 => utm(tokyo(Utm), c - 3092 + 51)
    _ => return None
  }
  Crs::new(d, trig~)
}
