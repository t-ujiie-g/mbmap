///|
/// The number of f64 slots of an encoded definition (docs/FORMATS.md "CRS
/// definition").
pub const DEFINITION_SLOTS : Int32 = 34

///|
let methods : FixedArray[Method] = [
  LongLat,
  Merc,
  Tmerc,
  Utm,
  Lcc,
  Aea,
  Aeqd,
  Stere,
  Sterea,
  Cass,
  Laea,
  Eqc,
  Eqdc,
  Sinu,
  Eck6,
  Moll,
  Robin,
  Cea,
  Mill,
  Poly,
  Omerc,
  Somerc,
  Krovak,
  Ortho,
  Gnom,
  Eqearth,
  Bonne,
]

///|
/// The definition encoded in `s` as docs/FORMATS.md "CRS definition" lays
/// it out; None if the slots are too few or the projection index or
/// `towgs84` count is not one it allows.
pub fn Definition::decode(s : ArrayView[Double]) -> Definition? {
  guard s.length() >= DEFINITION_SLOTS else { return None }
  let index = s[0].to_int()
  let count = s[4].to_int()
  guard index.to_double() == s[0] &&
    index >= 0 &&
    index < methods.length() &&
    (count == 0 || count == 3 || count == 7) else {
    return None
  }
  let d = Definition::new(methods[index], s[1], s[2])
  d.r_a = s[3] != 0.0
  d.towgs84 = Array::makei(count, i => s[5 + i])
  d.datum_wgs84 = s[12] != 0.0
  d.to_meter = s[13]
  d.from_greenwich = s[14]
  d.long_wrap = s[15]
  d.lat0 = s[16]
  d.lat1 = s[17]
  d.lat2 = s[18]
  d.lat_ts = s[19]
  d.long0 = s[20]
  d.long1 = s[21]
  d.long2 = s[22]
  d.alpha = s[23]
  d.gamma = s[24]
  d.longc = s[25]
  d.x0 = s[26]
  d.y0 = s[27]
  d.k0 = s[28]
  d.zone = if s[29].is_nan() { 0 } else { s[29].to_int() }
  d.south = s[30] != 0.0
  d.no_uoff = s[31] != 0.0
  d.no_rot = s[32] != 0.0
  d.czech = s[33] != 0.0
  Some(d)
}
