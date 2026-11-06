// Port of proj4js 2.22.0's azimuthal projections (lib/projections/aeqd.js,
// laea.js, ortho.js, gnom.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

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
/// Lambert azimuthal equal area, in its polar, equatorial or oblique form.
priv struct Laea {
  p : Base
  mode : LaeaMode
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
/// Which of its forms a Lambert azimuthal equal area takes, by its center.
#derive(Eq)
priv enum LaeaMode {
  SPole
  NPole
  Equit
  Obliq
}

///|
fn Laea::new(p : Base) -> Laea {
  let m = p.m
  let t = p.lat0.abs()
  let mode = if (t - HALF_PI).abs() < EPSLN {
    if p.lat0 < 0.0 {
      SPole
    } else {
      NPole
    }
  } else if t < EPSLN {
    Equit
  } else {
    Obliq
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
  if mode == Equit {
    let rq = (0.5 * qp).sqrt()
    { ..l, rq, dd: 1.0 / rq, xmf: 1.0, ymf: 0.5 * qp, }
  } else if mode == Obliq {
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
    if mode == Obliq || mode == Equit {
      let y = if mode == Equit {
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
        (if mode == Equit {
          sinphi
        } else {
          self.cosph0 * sinphi - self.sinph0 * cosphi * coslam
        }),
      )
    } else {
      let coslam = if mode == NPole { -coslam } else { coslam }
      if (lat + p.lat0).abs() < EPSLN {
        return nan2
      }
      let y = FORTPI - lat * 0.5
      let y = 2.0 * (if mode == SPole { m.cos(y) } else { m.sin(y) })
      (y * m.sin(lam), y * coslam)
    }
  } else {
    let coslam = m.cos(lam)
    let sinlam = m.sin(lam)
    let mut q = qsfnz(m, p.e, m.sin(lat))
    let (sinb, cosb) = if mode == Obliq || mode == Equit {
      let sinb = q / self.qp
      (sinb, (1.0 - sinb * sinb).sqrt())
    } else {
      (0.0, 0.0)
    }
    let b = if mode == Obliq {
      1.0 + self.sinb1 * sinb + self.cosb1 * cosb * coslam
    } else if mode == Equit {
      1.0 + cosb * coslam
    } else if mode == NPole {
      q = self.qp - q
      HALF_PI + lat
    } else {
      q = self.qp + q
      lat - HALF_PI
    }
    if b.abs() < EPSLN {
      return nan2
    }
    if mode == Obliq {
      let b = (2.0 / b).sqrt()
      (
        self.xmf * b * cosb * sinlam,
        self.ymf * b * (self.cosb1 * sinb - self.sinb1 * cosb * coslam),
      )
    } else if mode == Equit {
      let b = (2.0 / (1.0 + cosb * coslam)).sqrt()
      (self.xmf * b * cosb * sinlam, b * sinb * self.ymf)
    } else if q >= 0.0 {
      let b = q.sqrt()
      (b * sinlam, coslam * (if mode == SPole { b } else { -b }))
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
    if mode == Equit {
      phi = if rh.abs() <= EPSLN { 0.0 } else { m.asin(y * sinz / rh) }
      x *= sinz
      y = cosz * rh
    } else if mode == Obliq {
      phi = if rh.abs() <= EPSLN {
        p.lat0
      } else {
        m.asin(cosz * self.sinph0 + y * sinz * self.cosph0 / rh)
      }
      x *= sinz * self.cosph0
      y = (cosz - m.sin(phi) * self.sinph0) * rh
    } else if mode == NPole {
      y = -y
      phi = HALF_PI - phi
    } else {
      phi -= HALF_PI
    }
    let lam = if y == 0.0 && (mode == Equit || mode == Obliq) {
      0.0
    } else {
      m.atan2(x, y)
    }
    (lam, phi)
  } else {
    let mut ab = 0.0
    if mode == Obliq || mode == Equit {
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
      if mode == Obliq {
        ab = c_ce * self.sinb1 + y * s_ce * self.cosb1 / rho
        y = rho * self.cosb1 * c_ce - y * self.sinb1 * s_ce
      } else {
        ab = y * s_ce / rho
        y = rho * c_ce
      }
    } else {
      if mode == NPole {
        y = -y
      }
      let q = x * x + y * y
      if q == 0.0 {
        return (p.long0, p.lat0)
      }
      ab = 1.0 - q / self.qp
      if mode == SPole {
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
