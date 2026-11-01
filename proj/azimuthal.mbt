// Follows proj4js 2.22.0's azimuthal projections (lib/projections/aeqd.js,
// stere.js, sterea.js, gauss.js, laea.js, ortho.js, gnom.js and
// lib/common/vincenty.js), MIT License, Copyright (c) 2014, Mike Adair,
// Richard Greenwood, Didier Richard, Stephen Irons, Olivier Terral, Calvin
// Metcalf. See NOTICE.

///|
/// Azimuthal equidistant: by Vincenty's formulas on the ellipsoid, except
/// at the poles.
priv struct Aeqd {
  p : Base
  sin_p12 : Double
  cos_p12 : Double
  f : Double
  en : (Double, Double, Double, Double)
}

///|
fn Aeqd::new(p : Base) -> Aeqd {
  let m = p.m
  {
    p,
    sin_p12: m.sin(p.lat0),
    cos_p12: m.cos(p.lat0),
    f: p.es / (1.0 + (1.0 - p.es).sqrt()),
    en: mlfn_coefficients(p.es),
  }
}

///|
fn Aeqd::forward(self : Aeqd, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let sinphi = m.sin(lat)
  let cosphi = m.cos(lat)
  let dlon = adjust_lon(lon - p.long0)
  let north = (self.sin_p12 - 1.0).abs() <= EPSLN
  let south = (self.sin_p12 + 1.0).abs() <= EPSLN
  if p.sphere {
    if north {
      let r = p.a * (HALF_PI - lat)
      (p.x0 + r * m.sin(dlon), p.y0 - r * m.cos(dlon))
    } else if south {
      let r = p.a * (HALF_PI + lat)
      (p.x0 + r * m.sin(dlon), p.y0 + r * m.cos(dlon))
    } else {
      let cos_c = self.sin_p12 * sinphi + self.cos_p12 * cosphi * m.cos(dlon)
      let c = m.acos(cos_c)
      let kp = if c != 0.0 { c / m.sin(c) } else { 1.0 }
      (
        p.x0 + p.a * kp * cosphi * m.sin(dlon),
        p.y0 +
        p.a * kp * (self.cos_p12 * sinphi - self.sin_p12 * cosphi * m.cos(dlon)),
      )
    }
  } else if north || south {
    let mlp = p.a * mlfn(m, self.en, HALF_PI)
    let ml = p.a * mlfn(m, self.en, lat)
    if north {
      (p.x0 + (mlp - ml) * m.sin(dlon), p.y0 - (mlp - ml) * m.cos(dlon))
    } else {
      (p.x0 + (mlp + ml) * m.sin(dlon), p.y0 + (mlp + ml) * m.cos(dlon))
    }
  } else if lon.abs() < EPSLN && (lat - p.lat0).abs() < EPSLN {
    (p.x0, p.y0)
  } else {
    let (azi1, s12) = vincenty_inverse(
      m,
      p.lat0,
      p.long0,
      lat,
      lon,
      p.a,
      self.f,
    )
    (p.x0 + s12 * m.sin(azi1), p.y0 + s12 * m.cos(azi1))
  }
}

///|
fn Aeqd::inverse(self : Aeqd, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  let rh = (x * x + y * y).sqrt()
  if p.sphere {
    if rh > 2.0 * HALF_PI * p.a {
      return nan2
    }
    let z = rh / p.a
    let sinz = m.sin(z)
    let cosz = m.cos(z)
    if rh.abs() <= EPSLN {
      return (p.long0, p.lat0)
    }
    let lat = asinz(m, cosz * self.sin_p12 + y * sinz * self.cos_p12 / rh)
    let lon = if (p.lat0.abs() - HALF_PI).abs() <= EPSLN {
      if p.lat0 >= 0.0 {
        adjust_lon(p.long0 + m.atan2(x, -y))
      } else {
        adjust_lon(p.long0 - m.atan2(-x, y))
      }
    } else {
      adjust_lon(
        p.long0 +
        m.atan2(x * sinz, rh * self.cos_p12 * cosz - y * self.sin_p12 * sinz),
      )
    }
    (lon, lat)
  } else if (self.sin_p12 - 1.0).abs() <= EPSLN {
    let mlp = p.a * mlfn(m, self.en, HALF_PI)
    (
      adjust_lon(p.long0 + m.atan2(x, -1.0 * y)),
      imlfn(m, (mlp - rh) / p.a, self.en),
    )
  } else if (self.sin_p12 + 1.0).abs() <= EPSLN {
    let mlp = p.a * mlfn(m, self.en, HALF_PI)
    (adjust_lon(p.long0 + m.atan2(x, y)), imlfn(m, (rh - mlp) / p.a, self.en))
  } else {
    let (lat2, lon2) = vincenty_direct(
      m,
      p.lat0,
      p.long0,
      m.atan2(x, y),
      rh,
      p.a,
      self.f,
    )
    (lon2, lat2)
  }
}

///|
/// The initial azimuth and distance from (`lat1`, `lon1`) to (`lat2`,
/// `lon2`) on the ellipsoid of semi-major axis `a` and flattening `f`.
fn vincenty_inverse(
  m : Trig,
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
  a : Double,
  f : Double,
) -> (Double, Double) {
  let l = lon2 - lon1
  let u1 = m.atan((1.0 - f) * m.tan(lat1))
  let u2 = m.atan((1.0 - f) * m.tan(lat2))
  let sin_u1 = m.sin(u1)
  let cos_u1 = m.cos(u1)
  let sin_u2 = m.sin(u2)
  let cos_u2 = m.cos(u2)
  let mut lambda = l
  let mut sin_lambda = 0.0
  let mut cos_lambda = 0.0
  let mut sin_sigma = 0.0
  let mut cos_sigma = 0.0
  let mut sigma = 0.0
  let mut cos2_alpha = 0.0
  let mut cos2_sigma_m = 0.0
  let mut converged = false
  for _ in 0..<100 {
    sin_lambda = m.sin(lambda)
    cos_lambda = m.cos(lambda)
    let t = cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda
    sin_sigma = (cos_u2 * sin_lambda * (cos_u2 * sin_lambda) + t * t).sqrt()
    if sin_sigma == 0.0 {
      return (0.0, 0.0)
    }
    cos_sigma = sin_u1 * sin_u2 + cos_u1 * cos_u2 * cos_lambda
    sigma = m.atan2(sin_sigma, cos_sigma)
    let sin_alpha = cos_u1 * cos_u2 * sin_lambda / sin_sigma
    cos2_alpha = 1.0 - sin_alpha * sin_alpha
    cos2_sigma_m = if cos2_alpha != 0.0 {
      cos_sigma - 2.0 * sin_u1 * sin_u2 / cos2_alpha
    } else {
      0.0
    }
    let c = f / 16.0 * cos2_alpha * (4.0 + f * (4.0 - 3.0 * cos2_alpha))
    let previous = lambda
    lambda = l +
      (1.0 - c) *
      f *
      sin_alpha *
      (
        sigma +
        c *
        sin_sigma *
        (
          cos2_sigma_m +
          c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m)
        )
      )
    if (lambda - previous).abs() <= 1.0e-12 {
      converged = true
      break
    }
  }
  if !converged {
    return nan2
  }
  let b = a * (1.0 - f)
  let u_sq = cos2_alpha * (a * a - b * b) / (b * b)
  let big_a = 1.0 +
    u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
  let big_b = u_sq /
    1024.0 *
    (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
  let delta_sigma = big_b *
    sin_sigma *
    (
      cos2_sigma_m +
      big_b /
      4.0 *
      (
        cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m) -
        big_b /
        6.0 *
        cos2_sigma_m *
        (-3.0 + 4.0 * sin_sigma * sin_sigma) *
        (-3.0 + 4.0 * cos2_sigma_m * cos2_sigma_m)
      )
    )
  (
    m.atan2(cos_u2 * sin_lambda, cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda),
    b * big_a * (sigma - delta_sigma),
  )
}

///|
/// The point (latitude, longitude) at distance `s12` and azimuth `azi1` from
/// (`lat1`, `lon1`).
fn vincenty_direct(
  m : Trig,
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
  s12 : Double,
  a : Double,
  f : Double,
) -> (Double, Double) {
  let u1 = m.atan((1.0 - f) * m.tan(lat1))
  let sin_u1 = m.sin(u1)
  let cos_u1 = m.cos(u1)
  let sin_alpha1 = m.sin(azi1)
  let cos_alpha1 = m.cos(azi1)
  let sigma1 = m.atan2(sin_u1, cos_u1 * cos_alpha1)
  let sin_alpha = cos_u1 * sin_alpha1
  let cos2_alpha = 1.0 - sin_alpha * sin_alpha
  let b = a * (1.0 - f)
  let u_sq = cos2_alpha * (a * a - b * b) / (b * b)
  let big_a = 1.0 +
    u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
  let big_b = u_sq /
    1024.0 *
    (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))
  let mut sigma = s12 / (b * big_a)
  let mut sin_sigma = 0.0
  let mut cos_sigma = 0.0
  let mut cos2_sigma_m = 0.0
  let mut converged = false
  for _ in 0..<100 {
    cos2_sigma_m = m.cos(2.0 * sigma1 + sigma)
    sin_sigma = m.sin(sigma)
    cos_sigma = m.cos(sigma)
    let delta_sigma = big_b *
      sin_sigma *
      (
        cos2_sigma_m +
        big_b /
        4.0 *
        (
          cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m) -
          big_b /
          6.0 *
          cos2_sigma_m *
          (-3.0 + 4.0 * sin_sigma * sin_sigma) *
          (-3.0 + 4.0 * cos2_sigma_m * cos2_sigma_m)
        )
      )
    let previous = sigma
    sigma = s12 / (b * big_a) + delta_sigma
    if (sigma - previous).abs() <= 1.0e-12 {
      converged = true
      break
    }
  }
  if !converged {
    return nan2
  }
  let tmp = sin_u1 * sin_sigma - cos_u1 * cos_sigma * cos_alpha1
  let lat2 = m.atan2(
    sin_u1 * cos_sigma + cos_u1 * sin_sigma * cos_alpha1,
    (1.0 - f) * (sin_alpha * sin_alpha + tmp * tmp).sqrt(),
  )
  let lambda = m.atan2(
    sin_sigma * sin_alpha1,
    cos_u1 * cos_sigma - sin_u1 * sin_sigma * cos_alpha1,
  )
  let c = f / 16.0 * cos2_alpha * (4.0 + f * (4.0 - 3.0 * cos2_alpha))
  let l = lambda -
    (1.0 - c) *
    f *
    sin_alpha *
    (
      sigma +
      c *
      sin_sigma *
      (
        cos2_sigma_m +
        c * cos_sigma * (-1.0 + 2.0 * cos2_sigma_m * cos2_sigma_m)
      )
    )
  (lat2, lon1 + l)
}

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

///|
/// Lambert azimuthal equal area, in its polar, equatorial or oblique form.
priv struct Laea {
  p : Base
  mode : Int32
  qp : Double
  apa : FixedArray[Double]
  rq : Double
  dd : Double
  xmf : Double
  ymf : Double
  sinb1 : Double
  cosb1 : Double
  sinph0 : Double
  cosph0 : Double
}

///|
const S_POLE : Int32 = 1

///|
const N_POLE : Int32 = 2

///|
const EQUIT : Int32 = 3

///|
const OBLIQ : Int32 = 4

///|
fn Laea::new(p : Base) -> Laea {
  let m = p.m
  let t = p.lat0.abs()
  let mode = if (t - HALF_PI).abs() < EPSLN {
    if p.lat0 < 0.0 {
      S_POLE
    } else {
      N_POLE
    }
  } else if t < EPSLN {
    EQUIT
  } else {
    OBLIQ
  }
  let l : Laea = {
    p,
    mode,
    qp: 0.0,
    apa: [],
    rq: 0.0,
    dd: 1.0,
    xmf: 1.0,
    ymf: 1.0,
    sinb1: 0.0,
    cosb1: 0.0,
    sinph0: m.sin(p.lat0),
    cosph0: m.cos(p.lat0),
  }
  if p.es <= 0.0 {
    return l
  }
  let qp = qsfnz(m, p.e, 1.0)
  let l = { ..l, qp, apa: authset(p.es), }
  if mode == EQUIT {
    let rq = (0.5 * qp).sqrt()
    { ..l, rq, dd: 1.0 / rq, xmf: 1.0, ymf: 0.5 * qp, }
  } else if mode == OBLIQ {
    let rq = (0.5 * qp).sqrt()
    let sinphi = m.sin(p.lat0)
    let sinb1 = qsfnz(m, p.e, sinphi) / qp
    let cosb1 = (1.0 - sinb1 * sinb1).sqrt()
    let dd = m.cos(p.lat0) /
      ((1.0 - p.es * sinphi * sinphi).sqrt() * rq * cosb1)
    { ..l, rq, sinb1, cosb1, dd, xmf: rq * dd, ymf: rq / dd, }
  } else {
    l
  }
}

///|
fn Laea::forward(self : Laea, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lam = adjust_lon(lon - p.long0)
  let mode = self.mode
  let (x, y) = if p.sphere {
    let sinphi = m.sin(lat)
    let cosphi = m.cos(lat)
    let coslam = m.cos(lam)
    if mode == OBLIQ || mode == EQUIT {
      let y = if mode == EQUIT {
        1.0 + cosphi * coslam
      } else {
        1.0 + self.sinph0 * sinphi + self.cosph0 * cosphi * coslam
      }
      if y <= EPSLN {
        return nan2
      }
      let y = (2.0 / y).sqrt()
      (
        y * cosphi * m.sin(lam),
        y *
        (if mode == EQUIT {
          sinphi
        } else {
          self.cosph0 * sinphi - self.sinph0 * cosphi * coslam
        }),
      )
    } else {
      let coslam = if mode == N_POLE { -coslam } else { coslam }
      if (lat + p.lat0).abs() < EPSLN {
        return nan2
      }
      let y = FORTPI - lat * 0.5
      let y = 2.0 * (if mode == S_POLE { m.cos(y) } else { m.sin(y) })
      (y * m.sin(lam), y * coslam)
    }
  } else {
    let coslam = m.cos(lam)
    let sinlam = m.sin(lam)
    let mut q = qsfnz(m, p.e, m.sin(lat))
    let (sinb, cosb) = if mode == OBLIQ || mode == EQUIT {
      let sinb = q / self.qp
      (sinb, (1.0 - sinb * sinb).sqrt())
    } else {
      (0.0, 0.0)
    }
    let b = if mode == OBLIQ {
      1.0 + self.sinb1 * sinb + self.cosb1 * cosb * coslam
    } else if mode == EQUIT {
      1.0 + cosb * coslam
    } else if mode == N_POLE {
      q = self.qp - q
      HALF_PI + lat
    } else {
      q = self.qp + q
      lat - HALF_PI
    }
    if b.abs() < EPSLN {
      return nan2
    }
    if mode == OBLIQ {
      let b = (2.0 / b).sqrt()
      (
        self.xmf * b * cosb * sinlam,
        self.ymf * b * (self.cosb1 * sinb - self.sinb1 * cosb * coslam),
      )
    } else if mode == EQUIT {
      let b = (2.0 / (1.0 + cosb * coslam)).sqrt()
      (self.xmf * b * cosb * sinlam, b * sinb * self.ymf)
    } else if q >= 0.0 {
      let b = q.sqrt()
      (b * sinlam, coslam * (if mode == S_POLE { b } else { -b }))
    } else {
      (0.0, 0.0)
    }
  }
  (p.a * x + p.x0, p.a * y + p.y0)
}

///|
fn Laea::inverse(self : Laea, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let mode = self.mode
  let mut x = (x - p.x0) / p.a
  let mut y = (y - p.y0) / p.a
  let (lam, phi) = if p.sphere {
    let rh = (x * x + y * y).sqrt()
    let mut phi = rh * 0.5
    if phi > 1.0 {
      return nan2
    }
    phi = 2.0 * m.asin(phi)
    let sinz = m.sin(phi)
    let cosz = m.cos(phi)
    if mode == EQUIT {
      phi = if rh.abs() <= EPSLN { 0.0 } else { m.asin(y * sinz / rh) }
      x *= sinz
      y = cosz * rh
    } else if mode == OBLIQ {
      phi = if rh.abs() <= EPSLN {
        p.lat0
      } else {
        m.asin(cosz * self.sinph0 + y * sinz * self.cosph0 / rh)
      }
      x *= sinz * self.cosph0
      y = (cosz - m.sin(phi) * self.sinph0) * rh
    } else if mode == N_POLE {
      y = -y
      phi = HALF_PI - phi
    } else {
      phi -= HALF_PI
    }
    let lam = if y == 0.0 && (mode == EQUIT || mode == OBLIQ) {
      0.0
    } else {
      m.atan2(x, y)
    }
    (lam, phi)
  } else {
    let mut ab = 0.0
    if mode == OBLIQ || mode == EQUIT {
      x /= self.dd
      y *= self.dd
      let rho = (x * x + y * y).sqrt()
      if rho < EPSLN {
        return (p.long0, p.lat0)
      }
      let s_ce = 2.0 * m.asin(0.5 * rho / self.rq)
      let c_ce = m.cos(s_ce)
      let s_ce = m.sin(s_ce)
      x *= s_ce
      if mode == OBLIQ {
        ab = c_ce * self.sinb1 + y * s_ce * self.cosb1 / rho
        y = rho * self.cosb1 * c_ce - y * self.sinb1 * s_ce
      } else {
        ab = y * s_ce / rho
        y = rho * c_ce
      }
    } else {
      if mode == N_POLE {
        y = -y
      }
      let q = x * x + y * y
      if q == 0.0 {
        return (p.long0, p.lat0)
      }
      ab = 1.0 - q / self.qp
      if mode == S_POLE {
        ab = -ab
      }
    }
    (m.atan2(x, y), authlat(m, m.asin(ab), self.apa))
  }
  (adjust_lon(p.long0 + lam), phi)
}

///|
/// Orthographic, and gnomonic (which shares its constants), on a sphere of
/// radius `a`.
priv struct Ortho {
  p : Base
  sin_p14 : Double
  cos_p14 : Double
}

///|
fn Ortho::new(p : Base) -> Ortho {
  let m = p.m
  { p, sin_p14: m.sin(p.lat0), cos_p14: m.cos(p.lat0), }
}

///|
fn Ortho::forward(self : Ortho, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let dlon = adjust_lon(lon - p.long0)
  let sinphi = m.sin(lat)
  let cosphi = m.cos(lat)
  let coslon = m.cos(dlon)
  let g = self.sin_p14 * sinphi + self.cos_p14 * cosphi * coslon
  if g > 0.0 || g.abs() <= EPSLN {
    (
      p.x0 + p.a * cosphi * m.sin(dlon),
      p.y0 + p.a * (self.cos_p14 * sinphi - self.sin_p14 * cosphi * coslon),
    )
  } else {
    nan2
  }
}

///|
fn Ortho::inverse(self : Ortho, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = x - p.x0
  let y = y - p.y0
  let rh = (x * x + y * y).sqrt()
  let z = asinz(m, rh / p.a)
  let sinz = m.sin(z)
  let cosz = m.cos(z)
  if rh.abs() <= EPSLN {
    return (p.long0, p.lat0)
  }
  let lat = asinz(m, cosz * self.sin_p14 + y * sinz * self.cos_p14 / rh)
  let lon = if (p.lat0.abs() - HALF_PI).abs() <= EPSLN {
    if p.lat0 >= 0.0 {
      adjust_lon(p.long0 + m.atan2(x, -y))
    } else {
      adjust_lon(p.long0 - m.atan2(-x, y))
    }
  } else {
    adjust_lon(
      p.long0 +
      m.atan2(x * sinz, rh * self.cos_p14 * cosz - y * self.sin_p14 * sinz),
    )
  }
  (lon, lat)
}

///|
fn Ortho::gnom_forward(
  self : Ortho,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let dlon = adjust_lon(lon - p.long0)
  let sinphi = m.sin(lat)
  let cosphi = m.cos(lat)
  let coslon = m.cos(dlon)
  let g = self.sin_p14 * sinphi + self.cos_p14 * cosphi * coslon
  let x = cosphi * m.sin(dlon)
  let y = self.cos_p14 * sinphi - self.sin_p14 * cosphi * coslon
  if g > 0.0 || g.abs() <= EPSLN {
    (p.x0 + p.a * x / g, p.y0 + p.a * y / g)
  } else {
    let far = 1000.0 * p.a
    (p.x0 + far * x, p.y0 + far * y)
  }
}

///|
fn Ortho::gnom_inverse(
  self : Ortho,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) / p.a / p.k0
  let y = (y - p.y0) / p.a / p.k0
  let rh = (x * x + y * y).sqrt()
  if rh == 0.0 {
    // proj4js answers with an unset latitude here; PROJ gives the center.
    return (p.long0, p.lat0)
  }
  let c = m.atan2(rh, 1.0)
  let sinc = m.sin(c)
  let cosc = m.cos(c)
  (
    adjust_lon(
      p.long0 +
      m.atan2(x * sinc, rh * self.cos_p14 * cosc - y * self.sin_p14 * sinc),
    ),
    asinz(m, cosc * self.sin_p14 + y * sinc * self.cos_p14 / rh),
  )
}
