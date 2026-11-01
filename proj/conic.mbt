// Follows proj4js 2.22.0's conic projections (lib/projections/lcc.js, aea.js,
// eqdc.js, bonne.js, poly.js), MIT License, Copyright (c) 2014, Mike Adair,
// Richard Greenwood, Didier Richard, Stephen Irons, Olivier Terral, Calvin
// Metcalf. See NOTICE.

///|
/// Lambert conformal conic, on one standard parallel or two.
priv struct Lcc {
  p : Base
  e : Double
  ns : Double
  f0 : Double
  rh : Double
}

///|
fn Lcc::new(p : Base, d : Definition) -> Lcc {
  let m = p.m
  let lat1 = d.lat1
  let lat2 = or(d.lat2, lat1)
  let p = { ..p, x0: or(d.x0, 0.0), y0: or(d.y0, 0.0), }
  let temp = p.b / p.a
  let e = (1.0 - temp * temp).sqrt()
  let sin1 = m.sin(lat1)
  let ms1 = msfnz(e, sin1, m.cos(lat1))
  let ts1 = tsfnz(m, e, lat1, sin1)
  let sin2 = m.sin(lat2)
  let ms2 = msfnz(e, sin2, m.cos(lat2))
  let ts2 = tsfnz(m, e, lat2, sin2)
  let ts0 = tsfnz(m, e, p.lat0, m.sin(p.lat0))
  let mut ns = if (lat1 - lat2).abs() > EPSLN {
    m.ln(ms1 / ms2) / m.ln(ts1 / ts2)
  } else {
    sin1
  }
  if ns.is_nan() {
    ns = sin1
  }
  let f0 = ms1 / (ns * m.pow(ts1, ns))
  let rh = if (p.lat0.abs() - HALF_PI).abs() < EPSLN {
    0.0
  } else {
    p.a * f0 * m.pow(ts0, ns)
  }
  { p, e, ns, f0, rh, }
}

///|
fn Lcc::forward(self : Lcc, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lat = if (2.0 * lat.abs() - PI).abs() <= EPSLN {
    sign(lat) * (HALF_PI - 2.0 * EPSLN)
  } else {
    lat
  }
  let rh1 = if (lat.abs() - HALF_PI).abs() > EPSLN {
    p.a * self.f0 * m.pow(tsfnz(m, self.e, lat, m.sin(lat)), self.ns)
  } else if lat * self.ns <= 0.0 {
    return nan2
  } else {
    0.0
  }
  let theta = self.ns * adjust_lon(lon - p.long0)
  (
    p.k0 * (rh1 * m.sin(theta)) + p.x0,
    p.k0 * (self.rh - rh1 * m.cos(theta)) + p.y0,
  )
}

///|
fn Lcc::inverse(self : Lcc, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.k0
  let y = self.rh - (y - p.y0) / p.k0
  let (rh1, con) = if self.ns > 0.0 {
    ((x * x + y * y).sqrt(), 1.0)
  } else {
    (-(x * x + y * y).sqrt(), -1.0)
  }
  let theta = if rh1 != 0.0 { m.atan2(con * x, con * y) } else { 0.0 }
  let lat = if rh1 != 0.0 || self.ns > 0.0 {
    phi2z(m, self.e, m.pow(rh1 / (p.a * self.f0), 1.0 / self.ns))
  } else {
    -HALF_PI
  }
  (adjust_lon(theta / self.ns + p.long0), lat)
}

///|
/// Albers conic equal area.
priv struct Aea {
  p : Base
  e3 : Double
  ns0 : Double
  c : Double
  rh : Double
}

///|
fn Aea::new(p : Base, d : Definition) -> Aea {
  let m = p.m
  let lat1 = d.lat1
  let lat2 = if d.lat2.is_nan() { lat1 } else { d.lat2 }
  let temp = p.b / p.a
  let es = 1.0 - temp * temp
  let e3 = es.sqrt()
  let sin1 = m.sin(lat1)
  let ms1 = msfnz(e3, sin1, m.cos(lat1))
  let qs1 = qsfnz(m, e3, sin1)
  let sin2 = m.sin(lat2)
  let ms2 = msfnz(e3, sin2, m.cos(lat2))
  let qs2 = qsfnz(m, e3, sin2)
  let qs0 = qsfnz(m, e3, m.sin(p.lat0))
  let ns0 = if (lat1 - lat2).abs() > EPSLN {
    (ms1 * ms1 - ms2 * ms2) / (qs2 - qs1)
  } else {
    sin1
  }
  let c = ms1 * ms1 + ns0 * qs1
  { p, e3, ns0, c, rh: p.a * (c - ns0 * qs0).sqrt() / ns0, }
}

///|
fn Aea::forward(self : Aea, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let qs = qsfnz(m, self.e3, m.sin(lat))
  let rh1 = p.a * (self.c - self.ns0 * qs).sqrt() / self.ns0
  let theta = self.ns0 * adjust_lon(lon - p.long0)
  (rh1 * m.sin(theta) + p.x0, self.rh - rh1 * m.cos(theta) + p.y0)
}

///|
fn Aea::inverse(self : Aea, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = self.rh - y + p.y0
  let (rh1, con) = if self.ns0 >= 0.0 {
    ((x * x + y * y).sqrt(), 1.0)
  } else {
    (-(x * x + y * y).sqrt(), -1.0)
  }
  let theta = if rh1 != 0.0 { m.atan2(con * x, con * y) } else { 0.0 }
  let con = rh1 * self.ns0 / p.a
  let lat = if p.sphere {
    m.asin((self.c - con * con) / (2.0 * self.ns0))
  } else {
    aea_phi1z(m, self.e3, (self.c - con * con) / self.ns0)
  }
  (adjust_lon(theta / self.ns0 + p.long0), lat)
}

///|
fn aea_phi1z(m : Trig, e : Double, qs : Double) -> Double {
  let mut phi = asinz(m, 0.5 * qs)
  if e < EPSLN {
    return phi
  }
  let eccnts = e * e
  for _ in 1..<=25 {
    let sinphi = m.sin(phi)
    let cosphi = m.cos(phi)
    let con = e * sinphi
    let com = 1.0 - con * con
    let dphi = 0.5 *
      com *
      com /
      cosphi *
      (
        qs / (1.0 - eccnts) -
        sinphi / com +
        0.5 / e * m.ln((1.0 - con) / (1.0 + con))
      )
    phi += dphi
    if dphi.abs() <= 1.0e-7 {
      return phi
    }
  }
  @double.not_a_number
}

///|
/// Equidistant conic.
priv struct Eqdc {
  p : Base
  en : (Double, Double, Double, Double)
  ns : Double
  g : Double
  rh : Double
}

///|
fn Eqdc::new(p : Base, d : Definition) -> Eqdc {
  let m = p.m
  let lat1 = d.lat1
  let lat2 = or(d.lat2, lat1)
  let temp = p.b / p.a
  let es = 1.0 - temp * temp
  let e = es.sqrt()
  let en = mlfn_coefficients(es)
  let ms1 = msfnz(e, m.sin(lat1), m.cos(lat1))
  let ml1 = mlfn(m, en, lat1)
  let ns = if (lat1 - lat2).abs() < EPSLN {
    m.sin(lat1)
  } else {
    let ms2 = msfnz(e, m.sin(lat2), m.cos(lat2))
    (ms1 - ms2) / (mlfn(m, en, lat2) - ml1)
  }
  let g = ml1 + ms1 / ns
  { p, en, ns, g, rh: p.a * (g - mlfn(m, en, p.lat0)), }
}

///|
fn Eqdc::forward(self : Eqdc, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let rh1 = p.a *
    (self.g - (if p.sphere { lat } else { mlfn(m, self.en, lat) }))
  let theta = self.ns * adjust_lon(lon - p.long0)
  (p.x0 + rh1 * m.sin(theta), p.y0 + self.rh - rh1 * m.cos(theta))
}

///|
fn Eqdc::inverse(self : Eqdc, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = self.rh - y + p.y0
  let (rh1, con) = if self.ns >= 0.0 {
    ((x * x + y * y).sqrt(), 1.0)
  } else {
    (-(x * x + y * y).sqrt(), -1.0)
  }
  let theta = if rh1 != 0.0 { m.atan2(con * x, con * y) } else { 0.0 }
  let lon = adjust_lon(p.long0 + theta / self.ns)
  if p.sphere {
    (lon, adjust_lat(self.g - rh1 / p.a))
  } else {
    (lon, imlfn(m, self.g - rh1 / p.a, self.en))
  }
}

///|
/// Bonne (pseudoconic, equal area).
priv struct Bonne {
  p : Base
  phi1 : Double
  en : FixedArray[Double]
  m1 : Double
  am1 : Double
  cphi1 : Double
}

///|
fn Bonne::new(p : Base, d : Definition) -> Bonne? {
  let m = p.m
  let phi1 = d.lat1
  guard phi1.abs() >= EPSLN else { return None }
  if p.es != 0.0 {
    let en = pj_enfn(p.es)
    let s = m.sin(phi1)
    let c = m.cos(phi1)
    let m1 = pj_mlfn(phi1, s, c, en)
    let am1 = c / ((1.0 - p.es * s * s).sqrt() * s)
    Some({ p, phi1, en, m1, am1, cphi1: 0.0, })
  } else {
    let cphi1 = if phi1.abs() + EPSLN >= HALF_PI {
      0.0
    } else {
      1.0 / m.tan(phi1)
    }
    Some({ p, phi1, en: [], m1: 0.0, am1: 0.0, cphi1, })
  }
}

///|
fn Bonne::forward(self : Bonne, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lam = adjust_lon(lon - p.long0)
  let (x, y) = if p.es != 0.0 {
    let s = m.sin(lat)
    let c = m.cos(lat)
    let rh = self.am1 + self.m1 - pj_mlfn(lat, s, c, self.en)
    let e = c * lam / (rh * (1.0 - p.es * s * s).sqrt())
    (rh * m.sin(e), self.am1 - rh * m.cos(e))
  } else {
    let rh = self.cphi1 + self.phi1 - lat
    if rh.abs() > EPSLN {
      let e = lam * m.cos(lat) / rh
      (rh * m.sin(e), self.cphi1 - rh * m.cos(e))
    } else {
      (0.0, 0.0)
    }
  }
  (p.a * x + p.x0, p.a * y + p.y0)
}

///|
fn Bonne::inverse(self : Bonne, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.a
  let y = (y - p.y0) / p.a
  if p.es != 0.0 {
    let y = self.am1 - y
    let rh = hypot(x, y)
    let phi = pj_inv_mlfn(m, self.am1 + self.m1 - rh, p.es, self.en)
    let lam = if phi.abs() < HALF_PI {
      let s = m.sin(phi)
      rh * m.atan2(x, y) * (1.0 - p.es * s * s).sqrt() / m.cos(phi)
    } else if (phi.abs() - HALF_PI).abs() <= EPSLN {
      0.0
    } else {
      return nan2
    }
    (adjust_lon(lam + p.long0), adjust_lat(phi))
  } else {
    let y = self.cphi1 - y
    let rh = hypot(x, y)
    let phi = self.cphi1 + self.phi1 - rh
    guard phi.abs() <= HALF_PI else { return nan2 }
    let lam = if (phi.abs() - HALF_PI).abs() <= EPSLN {
      0.0
    } else {
      rh * m.atan2(x, y) / m.cos(phi)
    }
    (adjust_lon(lam + p.long0), adjust_lat(phi))
  }
}

///|
/// American polyconic.
priv struct Poly {
  p : Base
  e : Double
  es : Double
  en : (Double, Double, Double, Double)
  ml0 : Double
}

///|
fn Poly::new(p : Base) -> Poly {
  let m = p.m
  let temp = p.b / p.a
  let es = 1.0 - temp * temp
  let en = mlfn_coefficients(es)
  { p, e: es.sqrt(), es, en, ml0: p.a * mlfn(m, en, p.lat0), }
}

///|
fn Poly::forward(self : Poly, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let dlon = adjust_lon(lon - p.long0)
  let el = dlon * m.sin(lat)
  let (x, y) = if lat.abs() <= EPSLN {
    (p.a * dlon, if p.sphere { -p.a * p.lat0 } else { -self.ml0 })
  } else if p.sphere {
    (
      p.a * m.sin(el) / m.tan(lat),
      p.a * (adjust_lat(lat - p.lat0) + (1.0 - m.cos(el)) / m.tan(lat)),
    )
  } else {
    let nl = g_n(p.a, self.e, m.sin(lat)) / m.tan(lat)
    (
      nl * m.sin(el),
      p.a * mlfn(m, self.en, lat) - self.ml0 + nl * (1.0 - m.cos(el)),
    )
  }
  (x + p.x0, y + p.y0)
}

///|
fn Poly::inverse(self : Poly, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  let mut lat = @double.not_a_number
  if p.sphere {
    if (y + p.a * p.lat0).abs() <= EPSLN {
      return (adjust_lon(x / p.a + p.long0), 0.0)
    }
    let al = p.lat0 + y / p.a
    let bl = x * x / p.a / p.a + al * al
    let mut phi = al
    for _ in 0..<20 {
      let tanphi = m.tan(phi)
      let dphi = -1.0 *
        (al * (phi * tanphi + 1.0) - phi - 0.5 * (phi * phi + bl) * tanphi) /
        ((phi - al) / tanphi - 1.0)
      phi += dphi
      if dphi.abs() <= EPSLN {
        lat = phi
        break
      }
    }
    (adjust_lon(p.long0 + m.asin(x * m.tan(phi) / p.a) / m.sin(lat)), lat)
  } else {
    if (y + self.ml0).abs() <= EPSLN {
      return (adjust_lon(p.long0 + x / p.a), 0.0)
    }
    let (e0, e1, e2, e3) = self.en
    let al = (self.ml0 + y) / p.a
    let bl = x * x / p.a / p.a + al * al
    let mut phi = al
    for _ in 0..<20 {
      let con = self.e * m.sin(phi)
      let cl = (1.0 - con * con).sqrt() * m.tan(phi)
      let ma = p.a * mlfn(m, self.en, phi) / p.a
      let mlnp = e0 -
        2.0 * e1 * m.cos(2.0 * phi) +
        4.0 * e2 * m.cos(4.0 * phi) -
        6.0 * e3 * m.cos(6.0 * phi)
      let dphi = (al * (cl * ma + 1.0) - ma - 0.5 * cl * (ma * ma + bl)) /
        (
          self.es *
          m.sin(2.0 * phi) *
          (ma * ma + bl - 2.0 * al * ma) /
          (4.0 * cl) +
          (al - ma) * (cl * mlnp - 2.0 / m.sin(2.0 * phi)) -
          mlnp
        )
      phi -= dphi
      if dphi.abs() <= EPSLN {
        lat = phi
        break
      }
    }
    let s = m.sin(lat)
    let cl = (1.0 - self.es * s * s).sqrt() * m.tan(lat)
    (adjust_lon(p.long0 + m.asin(x * cl / p.a) / m.sin(lat)), lat)
  }
}
