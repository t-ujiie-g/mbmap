// Port of proj4js 2.22.0's cylindrical projections (lib/projections/merc.js,
// cass.js, eqc.js, cea.js, mill.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

///|
/// Mercator, spherical or ellipsoidal, scaled by `k0` or true at `lat_ts`.
priv struct Merc {
  p : Base
  k0 : Double
}

///|
fn Merc::new(p : Base, d : Definition) -> Merc {
  let m = p.m
  let k0 = if or(d.lat_ts, 0.0) != 0.0 {
    if p.sphere {
      m.cos(d.lat_ts)
    } else {
      msfnz(p.e, m.sin(d.lat_ts), m.cos(d.lat_ts))
    }
  } else {
    p.k0
  }
  { p, k0, }
}

///|
fn Merc::forward(self : Merc, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  if (lat.abs() - HALF_PI).abs() <= EPSLN {
    return nan2
  }
  let x = p.x0 + p.a * self.k0 * adjust_lon(lon - p.long0)
  if p.sphere {
    (x, p.y0 + p.a * self.k0 * m.ln(m.tan(FORTPI + 0.5 * lat)))
  } else {
    (x, p.y0 - p.a * self.k0 * m.ln(tsfnz(m, p.e, lat, m.sin(lat))))
  }
}

///|
fn Merc::inverse(self : Merc, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  let lat = if p.sphere {
    HALF_PI - 2.0 * m.atan(m.exp(-y / (p.a * self.k0)))
  } else {
    phi2z(m, p.e, m.exp(-y / (p.a * self.k0)))
  }
  (adjust_lon(p.long0 + x / (p.a * self.k0)), lat)
}

///|
/// Cassini-Soldner.
priv struct Cass {
  p : Base
  en : (Double, Double, Double, Double)
  ml0 : Double
}

///|
fn Cass::new(p : Base) -> Cass {
  let m = p.m
  let en = mlfn_coefficients(p.es)
  { p, en, ml0: p.a * mlfn(m, en, p.lat0), }
}

///|
fn Cass::forward(self : Cass, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lam = adjust_lon(lon - p.long0)
  let (x, y) = if p.sphere {
    (
      p.a * m.asin(m.cos(lat) * m.sin(lam)),
      p.a * (m.atan2(m.tan(lat), m.cos(lam)) - p.lat0),
    )
  } else {
    let sinphi = m.sin(lat)
    let cosphi = m.cos(lat)
    let nl = g_n(p.a, p.e, sinphi)
    let tl = m.tan(lat) * m.tan(lat)
    let al = lam * cosphi
    let asq = al * al
    let cl = p.es * cosphi * cosphi / (1.0 - p.es)
    let ml = p.a * mlfn(m, self.en, lat)
    (
      nl *
      al *
      (1.0 - asq * tl * (1.0 / 6.0 - (8.0 - tl + 8.0 * cl) * asq / 120.0)),
      ml -
      self.ml0 +
      nl * sinphi / cosphi * asq * (0.5 + (5.0 - tl + 6.0 * cl) * asq / 24.0),
    )
  }
  (x + p.x0, y + p.y0)
}

///|
fn Cass::inverse(self : Cass, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.a
  let y = (y - p.y0) / p.a
  let (phi, lam) = if p.sphere {
    let dd = y + p.lat0
    (m.asin(m.sin(dd) * m.cos(x)), m.atan2(m.tan(x), m.cos(dd)))
  } else {
    let phi1 = imlfn(m, self.ml0 / p.a + y, self.en)
    if (phi1.abs() - HALF_PI).abs() <= EPSLN {
      return (p.long0, if y < 0.0 { -HALF_PI } else { HALF_PI })
    }
    let nl1 = g_n(p.a, p.e, m.sin(phi1))
    let rl1 = nl1 * nl1 * nl1 / p.a / p.a * (1.0 - p.es)
    let tl1 = m.pow(m.tan(phi1), 2.0)
    let dl = x * p.a / nl1
    let dsq = dl * dl
    (
      phi1 -
      nl1 *
      m.tan(phi1) /
      rl1 *
      dl *
      dl *
      (0.5 - (1.0 + 3.0 * tl1) * dl * dl / 24.0),
      dl *
      (1.0 - dsq * (tl1 / 3.0 + (1.0 + 3.0 * tl1) * tl1 * dsq / 15.0)) /
      m.cos(phi1),
    )
  }
  (adjust_lon(lam + p.long0), adjust_lat(phi))
}

///|
/// Equidistant cylindrical (plate carrée), true at `lat_ts`.
priv struct Eqc {
  p : Base
  rc : Double
}

///|
fn Eqc::new(p : Base, d : Definition) -> Eqc {
  let m = p.m
  { p, rc: m.cos(or(d.lat_ts, 0.0)), }
}

///|
fn Eqc::forward(self : Eqc, lon : Double, lat : Double) -> (Double, Double) {
  let p = self.p
  (
    p.x0 + p.a * adjust_lon(lon - p.long0) * self.rc,
    p.y0 + p.a * adjust_lat(lat - p.lat0),
  )
}

///|
fn Eqc::inverse(self : Eqc, x : Double, y : Double) -> (Double, Double) {
  let p = self.p
  (
    adjust_lon(p.long0 + (x - p.x0) / (p.a * self.rc)),
    adjust_lat(p.lat0 + (y - p.y0) / p.a),
  )
}

///|
/// Lambert cylindrical equal area, true at `lat_ts`.
priv struct Cea {
  p : Base
  lat_ts : Double
  k0 : Double
}

///|
fn Cea::new(p : Base, d : Definition) -> Cea {
  let m = p.m
  let lat_ts = or(d.lat_ts, 0.0)
  let k0 = if p.sphere {
    p.k0
  } else {
    msfnz(p.e, m.sin(lat_ts), m.cos(lat_ts))
  }
  { p, lat_ts, k0, }
}

///|
fn Cea::forward(self : Cea, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let dlon = adjust_lon(lon - p.long0)
  if p.sphere {
    (
      p.x0 + p.a * dlon * m.cos(self.lat_ts),
      p.y0 + p.a * m.sin(lat) / m.cos(self.lat_ts),
    )
  } else {
    let qs = qsfnz(m, p.e, m.sin(lat))
    (p.x0 + p.a * self.k0 * dlon, p.y0 + p.a * qs * 0.5 / self.k0)
  }
}

///|
fn Cea::inverse(self : Cea, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  if p.sphere {
    (
      adjust_lon(p.long0 + x / p.a / m.cos(self.lat_ts)),
      m.asin(y / p.a * m.cos(self.lat_ts)),
    )
  } else {
    (
      adjust_lon(p.long0 + x / (p.a * self.k0)),
      iqsfnz(m, p.e, 2.0 * y * self.k0 / p.a),
    )
  }
}

///|
/// Miller cylindrical.
fn mill_forward(
  m : Trig,
  p : Base,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  (
    p.x0 + p.a * adjust_lon(lon - p.long0),
    p.y0 + p.a * m.ln(m.tan(PI / 4.0 + lat / 2.5)) * 1.25,
  )
}

///|
fn mill_inverse(m : Trig, p : Base, x : Double, y : Double) -> (Double, Double) {
  (
    adjust_lon(p.long0 + (x - p.x0) / p.a),
    2.5 * (m.atan(m.exp(0.8 * (y - p.y0) / p.a)) - PI / 4.0),
  )
}
