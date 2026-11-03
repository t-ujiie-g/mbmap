// Port of proj4js 2.22.0's stereographic projections (lib/projections/stere.js,
// sterea.js, gauss.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

///|
/// Polar or oblique stereographic (`stere`).
priv struct Stere {
  p : Base
  k0 : Double
  coslat0 : Double
  sinlat0 : Double
  con : Double
  cons : Double
  ms1 : Double
  x0_chi : Double
  cos_x0 : Double
  sin_x0 : Double
}

///|
fn ssfn(m : Trig, phit : Double, sinphi : Double, e : Double) -> Double {
  let sinphi = sinphi * e
  m.tan(0.5 * (HALF_PI + phit)) *
  m.pow((1.0 - sinphi) / (1.0 + sinphi), 0.5 * e)
}

///|
fn Stere::new(p : Base, d : Definition) -> Stere {
  let m = p.m
  let coslat0 = m.cos(p.lat0)
  let sinlat0 = m.sin(p.lat0)
  let polar = coslat0.abs() <= EPSLN
  let lat_ts = d.lat_ts
  if p.sphere {
    let k0 = if !lat_ts.is_nan() && polar {
      0.5 * (1.0 + sign(p.lat0) * m.sin(lat_ts))
    } else {
      p.k0
    }
    return {
      p,
      k0,
      coslat0,
      sinlat0,
      con: 0.0,
      cons: 0.0,
      ms1: 0.0,
      x0_chi: 0.0,
      cos_x0: 0.0,
      sin_x0: 0.0,
    }
  }
  let e = p.e
  let con = if p.lat0 > 0.0 { 1.0 } else { -1.0 }
  let cons = (m.pow(1.0 + e, 1.0 + e) * m.pow(1.0 - e, 1.0 - e)).sqrt()
  let k0 = if !lat_ts.is_nan() && polar && m.cos(lat_ts).abs() > EPSLN {
    0.5 *
    cons *
    msfnz(e, m.sin(lat_ts), m.cos(lat_ts)) /
    tsfnz(m, e, con * lat_ts, con * m.sin(lat_ts))
  } else {
    p.k0
  }
  let x0_chi = 2.0 * m.atan(ssfn(m, p.lat0, sinlat0, e)) - HALF_PI
  {
    p,
    k0,
    coslat0,
    sinlat0,
    con,
    cons,
    ms1: msfnz(e, sinlat0, coslat0),
    x0_chi,
    cos_x0: m.cos(x0_chi),
    sin_x0: m.sin(x0_chi),
  }
}

///|
fn Stere::forward(self : Stere, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let sinlat = m.sin(lat)
  let coslat = m.cos(lat)
  let dlon = adjust_lon(lon - p.long0)
  if ((lon - p.long0).abs() - PI).abs() <= EPSLN &&
    (lat + p.lat0).abs() <= EPSLN {
    return nan2
  }
  if p.sphere {
    let a = 2.0 *
      self.k0 /
      (1.0 + self.sinlat0 * sinlat + self.coslat0 * coslat * m.cos(dlon))
    return (
      p.a * a * coslat * m.sin(dlon) + p.x0,
      p.a * a * (self.coslat0 * sinlat - self.sinlat0 * coslat * m.cos(dlon)) +
      p.y0,
    )
  }
  let chi = 2.0 * m.atan(ssfn(m, lat, sinlat, p.e)) - HALF_PI
  let cos_x = m.cos(chi)
  let sin_x = m.sin(chi)
  if self.coslat0.abs() <= EPSLN {
    let ts = tsfnz(m, p.e, lat * self.con, self.con * sinlat)
    let rh = 2.0 * p.a * self.k0 * ts / self.cons
    return (
      p.x0 + rh * m.sin(lon - p.long0),
      p.y0 - self.con * rh * m.cos(lon - p.long0),
    )
  }
  if self.sinlat0.abs() < EPSLN {
    let a = 2.0 * p.a * self.k0 / (1.0 + cos_x * m.cos(dlon))
    // proj4js leaves out the false northing here; PROJ adds it.
    (a * cos_x * m.sin(dlon) + p.x0, a * sin_x + p.y0)
  } else {
    let a = 2.0 *
      p.a *
      self.k0 *
      self.ms1 /
      (
        self.cos_x0 *
        (1.0 + self.sin_x0 * sin_x + self.cos_x0 * cos_x * m.cos(dlon))
      )
    (
      a * cos_x * m.sin(dlon) + p.x0,
      a * (self.cos_x0 * sin_x - self.sin_x0 * cos_x * m.cos(dlon)) + p.y0,
    )
  }
}

///|
fn Stere::inverse(self : Stere, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  let rh = (x * x + y * y).sqrt()
  if p.sphere {
    let c = 2.0 * m.atan(rh / (2.0 * p.a * self.k0))
    if rh <= EPSLN {
      return (p.long0, p.lat0)
    }
    let lat = m.asin(m.cos(c) * self.sinlat0 + y * m.sin(c) * self.coslat0 / rh)
    let lon = if self.coslat0.abs() < EPSLN {
      if p.lat0 > 0.0 {
        adjust_lon(p.long0 + m.atan2(x, -1.0 * y))
      } else {
        adjust_lon(p.long0 + m.atan2(x, y))
      }
    } else {
      adjust_lon(
        p.long0 +
        m.atan2(
          x * m.sin(c),
          rh * self.coslat0 * m.cos(c) - y * self.sinlat0 * m.sin(c),
        ),
      )
    }
    return (lon, lat)
  }
  if self.coslat0.abs() <= EPSLN {
    if rh <= EPSLN {
      return (p.long0, p.lat0)
    }
    let x = x * self.con
    let y = y * self.con
    let ts = rh * self.cons / (2.0 * p.a * self.k0)
    (
      self.con * adjust_lon(self.con * p.long0 + m.atan2(x, -1.0 * y)),
      self.con * phi2z(m, p.e, ts),
    )
  } else {
    let ce = 2.0 * m.atan(rh * self.cos_x0 / (2.0 * p.a * self.k0 * self.ms1))
    let (lon, chi) = if rh <= EPSLN {
      (p.long0, self.x0_chi)
    } else {
      (
        adjust_lon(
          p.long0 +
          m.atan2(
            x * m.sin(ce),
            rh * self.cos_x0 * m.cos(ce) - y * self.sin_x0 * m.sin(ce),
          ),
        ),
        m.asin(m.cos(ce) * self.sin_x0 + y * m.sin(ce) * self.cos_x0 / rh),
      )
    }
    (lon, -1.0 * phi2z(m, p.e, m.tan(0.5 * (HALF_PI + chi))))
  }
}

///|
/// Oblique stereographic on the Gaussian sphere (`sterea`, as in the
/// Netherlands' RD): the conformal sphere's constants, then its center.
priv struct Sterea {
  p : Base
  c : Double
  k : Double
  ratexp : Double
  phic0 : Double
  sinc0 : Double
  cosc0 : Double
  r2 : Double
}

///|
fn Sterea::new(p : Base) -> Sterea {
  let m = p.m
  let sphi = m.sin(p.lat0)
  let cphi = m.cos(p.lat0)
  let cphi = cphi * cphi
  let rc = (1.0 - p.es).sqrt() / (1.0 - p.es * sphi * sphi)
  let c = (1.0 + p.es * cphi * cphi / (1.0 - p.es)).sqrt()
  let phic0 = m.asin(sphi / c)
  let ratexp = 0.5 * c * p.e
  let k = m.tan(0.5 * phic0 + FORTPI) /
    (m.pow(m.tan(0.5 * p.lat0 + FORTPI), c) * srat(m, p.e * sphi, ratexp))
  {
    p,
    c,
    k,
    ratexp,
    phic0,
    sinc0: m.sin(phic0),
    cosc0: m.cos(phic0),
    r2: 2.0 * rc,
  }
}

///|
fn Sterea::forward(
  self : Sterea,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lon = adjust_lon(lon - p.long0)
  let lat = 2.0 *
    m.atan(
      self.k *
      m.pow(m.tan(0.5 * lat + FORTPI), self.c) *
      srat(m, p.e * m.sin(lat), self.ratexp),
    ) -
    HALF_PI
  let lon = self.c * lon
  let sinc = m.sin(lat)
  let cosc = m.cos(lat)
  let cosl = m.cos(lon)
  let k = p.k0 * self.r2 / (1.0 + self.sinc0 * sinc + self.cosc0 * cosc * cosl)
  (
    p.a * (k * cosc * m.sin(lon)) + p.x0,
    p.a * (k * (self.cosc0 * sinc - self.sinc0 * cosc * cosl)) + p.y0,
  )
}

///|
fn Sterea::inverse(self : Sterea, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.a / p.k0
  let y = (y - p.y0) / p.a / p.k0
  let rho = hypot(x, y)
  let (lon, lat) = if rho != 0.0 {
    let c = 2.0 * m.atan2(rho, self.r2)
    let sinc = m.sin(c)
    let cosc = m.cos(c)
    (
      m.atan2(x * sinc, rho * self.cosc0 * cosc - y * self.sinc0 * sinc),
      m.asin(cosc * self.sinc0 + y * sinc * self.cosc0 / rho),
    )
  } else {
    (0.0, self.phic0)
  }
  let lon = lon / self.c
  let num = m.pow(m.tan(0.5 * lat + FORTPI) / self.k, 1.0 / self.c)
  let mut phi = lat
  let mut settled = false
  for _ in 0..<20 {
    let next = 2.0 * m.atan(num * srat(m, p.e * m.sin(phi), -0.5 * p.e)) -
      HALF_PI
    if (next - phi).abs() < 1.0e-14 {
      phi = next
      settled = true
      break
    }
    phi = next
  }
  if !settled {
    return nan2
  }
  (adjust_lon(lon + p.long0), phi)
}
