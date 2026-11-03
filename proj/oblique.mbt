// Port of proj4js 2.22.0's oblique projections (lib/projections/omerc.js,
// somerc.js, krovak.js), MIT License, Copyright (c) 2014 Mike Adair et al.; see NOTICE.

///|
/// Hotine oblique Mercator, by its center's azimuth (`alpha`, `gamma`,
/// `longc`) or by two points of its central line; `no_uoff` (variant A)
/// counts from the natural origin.
priv struct Omerc {
  p : Base
  no_rot : Bool
  a_ : Double
  b_ : Double
  e_ : Double
  lam0 : Double
  singam : Double
  cosgam : Double
  sinrot : Double
  cosrot : Double
  arb : Double
  bra : Double
  u_0 : Double
  v_pole_n : Double
  v_pole_s : Double
}

///|
fn Omerc::new(p : Base, d : Definition) -> Omerc? {
  let m = p.m
  let tol = 1.0e-7
  let alp = !d.alpha.is_nan() || !d.gamma.is_nan()
  let mut alpha_c = if d.alpha.is_nan() { 0.0 } else { d.alpha }
  let mut gamma = if d.gamma.is_nan() { 0.0 } else { d.gamma }
  let (lam1, phi1, lam2, phi2) = (d.long1, d.lat1, d.long2, d.lat2)
  if !alp {
    guard (phi1 - phi2).abs() > tol &&
      phi1.abs() > tol &&
      (phi1.abs() - HALF_PI).abs() > tol &&
      (p.lat0.abs() - HALF_PI).abs() > tol &&
      (phi2.abs() - HALF_PI).abs() > tol else {
      return None
    }
  }
  let one_es = 1.0 - p.es
  let com = one_es.sqrt()
  let (b_, a_, e_, d_, f_) = if p.lat0.abs() > EPSLN {
    let sinph0 = m.sin(p.lat0)
    let cosph0 = m.cos(p.lat0)
    let con = 1.0 - p.es * sinph0 * sinph0
    let b_ = cosph0 * cosph0
    let b_ = (1.0 + p.es * b_ * b_ / one_es).sqrt()
    let a_ = b_ * p.k0 * com / con
    let d_ = b_ * com / (cosph0 * con.sqrt())
    let mut f_ = d_ * d_ - 1.0
    if f_ <= 0.0 {
      f_ = 0.0
    } else {
      f_ = f_.sqrt()
      if p.lat0 < 0.0 {
        f_ = -f_
      }
    }
    f_ += d_
    (b_, a_, f_ * m.pow(tsfnz(m, p.e, p.lat0, sinph0), b_), d_, f_)
  } else {
    (1.0 / com, p.k0, 1.0, 1.0, 1.0)
  }
  let (gamma0, lam0) = if alp {
    let gamma0 = if !d.alpha.is_nan() {
      let g0 = m.asin(m.sin(alpha_c) / d_)
      if d.gamma.is_nan() {
        gamma = alpha_c
      }
      g0
    } else {
      alpha_c = m.asin(d_ * m.sin(gamma))
      gamma
    }
    let lamc = if d.longc.is_nan() { 0.0 } else { d.longc }
    (gamma0, lamc - m.asin(0.5 * (f_ - 1.0 / f_) * m.tan(gamma0)) / b_)
  } else {
    let h = m.pow(tsfnz(m, p.e, phi1, m.sin(phi1)), b_)
    let l = m.pow(tsfnz(m, p.e, phi2, m.sin(phi2)), b_)
    let f_ = e_ / h
    let pp = (l - h) / (l + h)
    let j = e_ * e_
    let j = (j - l * h) / (j + l * h)
    let con = lam1 - lam2
    let lam2 = if con < -PI {
      lam2 - 2.0 * PI
    } else if con > PI {
      lam2 + 2.0 * PI
    } else {
      lam2
    }
    let lam0 = adjust_lon(
      0.5 * (lam1 + lam2) -
      m.atan(j * m.tan(0.5 * b_ * (lam1 - lam2)) / pp) / b_,
    )
    let gamma0 = m.atan(
      2.0 * m.sin(b_ * adjust_lon(lam1 - lam0)) / (f_ - 1.0 / f_),
    )
    alpha_c = m.asin(d_ * m.sin(gamma0))
    gamma = alpha_c
    (gamma0, lam0)
  }
  let arb = a_ / b_
  let u_0 = if d.no_uoff {
    0.0
  } else {
    let u = (arb * m.atan((d_ * d_ - 1.0).sqrt() / m.cos(alpha_c))).abs()
    if p.lat0 < 0.0 {
      -u
    } else {
      u
    }
  }
  let f = 0.5 * gamma0
  Some({
    p,
    no_rot: d.no_rot,
    a_,
    b_,
    e_,
    lam0,
    singam: m.sin(gamma0),
    cosgam: m.cos(gamma0),
    sinrot: m.sin(gamma),
    cosrot: m.cos(gamma),
    arb,
    bra: 1.0 / arb,
    u_0,
    v_pole_n: arb * m.ln(m.tan(FORTPI - f)),
    v_pole_s: arb * m.ln(m.tan(FORTPI + f)),
  })
}

///|
fn Omerc::forward(self : Omerc, lon : Double, lat : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let lon = lon - self.lam0
  let (u, v) = if (lat.abs() - HALF_PI).abs() > EPSLN {
    let w = self.e_ / m.pow(tsfnz(m, p.e, lat, m.sin(lat)), self.b_)
    let temp = 1.0 / w
    let s = 0.5 * (w - temp)
    let t = 0.5 * (w + temp)
    let v = m.sin(self.b_ * lon)
    let u = (s * self.singam - v * self.cosgam) / t
    if (u.abs() - 1.0).abs() < EPSLN {
      return nan2
    }
    let v_ = 0.5 * self.arb * m.ln((1.0 - u) / (1.0 + u))
    let temp = m.cos(self.b_ * lon)
    let u_ = if temp.abs() < 1.0e-7 {
      self.a_ * lon
    } else {
      self.arb * m.atan2(s * self.cosgam + v * self.singam, temp)
    }
    (u_, v_)
  } else {
    (self.arb * lat, if lat > 0.0 { self.v_pole_n } else { self.v_pole_s })
  }
  let (x, y) = if self.no_rot {
    (u, v)
  } else {
    let u = u - self.u_0
    (v * self.cosrot + u * self.sinrot, u * self.cosrot - v * self.sinrot)
  }
  (p.a * x + p.x0, p.a * y + p.y0)
}

///|
fn Omerc::inverse(self : Omerc, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let x = (x - p.x0) * (1.0 / p.a)
  let y = (y - p.y0) * (1.0 / p.a)
  let (v, u) = if self.no_rot {
    (y, x)
  } else {
    (
      x * self.cosrot - y * self.sinrot,
      y * self.cosrot + x * self.sinrot + self.u_0,
    )
  }
  let qp = m.exp(-self.bra * v)
  let sp = 0.5 * (qp - 1.0 / qp)
  let tp = 0.5 * (qp + 1.0 / qp)
  let vp = m.sin(self.bra * u)
  let up = (vp * self.cosgam + sp * self.singam) / tp
  let (lon, lat) = if (up.abs() - 1.0).abs() < EPSLN {
    (0.0, if up < 0.0 { -HALF_PI } else { HALF_PI })
  } else {
    let y = self.e_ / ((1.0 + up) / (1.0 - up)).sqrt()
    (
      -1.0 /
      self.b_ *
      m.atan2(sp * self.cosgam - vp * self.singam, m.cos(self.bra * u)),
      phi2z(m, p.e, m.pow(y, 1.0 / self.b_)),
    )
  }
  (lon + self.lam0, lat)
}

///|
/// Swiss oblique Mercator.
priv struct Somerc {
  p : Base
  e : Double
  r : Double
  alpha : Double
  b0 : Double
  k : Double
}

///|
fn Somerc::new(p : Base) -> Somerc {
  let m = p.m
  let phy0 = p.lat0
  let sin_phy0 = m.sin(phy0)
  let flattening = 1.0 / p.rf
  let e2 = 2.0 * flattening - flattening * flattening
  let e = e2.sqrt()
  let r = p.k0 * p.a * (1.0 - e2).sqrt() / (1.0 - e2 * sin_phy0 * sin_phy0)
  let alpha = (1.0 + e2 / (1.0 - e2) * m.pow(m.cos(phy0), 4.0)).sqrt()
  let b0 = m.asin(sin_phy0 / alpha)
  let k1 = m.ln(m.tan(PI / 4.0 + b0 / 2.0))
  let k2 = m.ln(m.tan(PI / 4.0 + phy0 / 2.0))
  let k3 = m.ln((1.0 + e * sin_phy0) / (1.0 - e * sin_phy0))
  { p, e, r, alpha, b0, k: k1 - alpha * k2 + alpha * e / 2.0 * k3, }
}

///|
fn Somerc::forward(
  self : Somerc,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let sa1 = m.ln(m.tan(PI / 4.0 - lat / 2.0))
  let sa2 = self.e /
    2.0 *
    m.ln((1.0 + self.e * m.sin(lat)) / (1.0 - self.e * m.sin(lat)))
  let s = -self.alpha * (sa1 + sa2) + self.k
  let b = 2.0 * (m.atan(m.exp(s)) - PI / 4.0)
  let i = self.alpha * (lon - p.long0)
  let rot_i = m.atan(
    m.sin(i) / (m.sin(self.b0) * m.tan(b) + m.cos(self.b0) * m.cos(i)),
  )
  let rot_b = m.asin(
    m.cos(self.b0) * m.sin(b) - m.sin(self.b0) * m.cos(b) * m.cos(i),
  )
  (
    self.r * rot_i + p.x0,
    self.r / 2.0 * m.ln((1.0 + m.sin(rot_b)) / (1.0 - m.sin(rot_b))) + p.y0,
  )
}

///|
fn Somerc::inverse(self : Somerc, x : Double, y : Double) -> (Double, Double) {
  let m = self.p.m
  let p = self.p
  let rot_i = (x - p.x0) / self.r
  let rot_b = 2.0 * (m.atan(m.exp((y - p.y0) / self.r)) - PI / 4.0)
  let b = m.asin(
    m.cos(self.b0) * m.sin(rot_b) + m.sin(self.b0) * m.cos(rot_b) * m.cos(rot_i),
  )
  let i = m.atan(
    m.sin(rot_i) /
    (m.cos(self.b0) * m.cos(rot_i) - m.sin(self.b0) * m.tan(rot_b)),
  )
  let lambda = p.long0 + i / self.alpha
  let mut phy = b
  let mut prev = -1000.0
  let mut iteration = 0
  while (phy - prev).abs() > 0.0000001 {
    iteration += 1
    if iteration > 20 {
      return nan2
    }
    let s = 1.0 / self.alpha * (m.ln(m.tan(PI / 4.0 + b / 2.0)) - self.k) +
      self.e * m.ln(m.tan(PI / 4.0 + m.asin(self.e * m.sin(phy)) / 2.0))
    prev = phy
    phy = 2.0 * m.atan(m.exp(s)) - PI / 2.0
  }
  (lambda, phy)
}

///|
/// Krovak (Czech and Slovak S-JTSK), always on Bessel 1841 as proj4js has
/// it; `czech` keeps the axes positive to the south and west.
priv struct Krovak {
  m : Trig
  long0 : Double
  czech : Bool
  e : Double
  alfa : Double
  k : Double
  ro0 : Double
  n : Double
  ad : Double
}

///|
const KROVAK_S45 : Double = 0.785398163397448

///|
const KROVAK_S0 : Double = 1.37008346281555

///|
fn Krovak::new(_p : Base, d : Definition) -> Krovak {
  let m = _p.m
  let a = 6377397.155
  let e2 = 0.006674372230614
  let e = e2.sqrt()
  let fi0 = or(d.lat0, 0.863937979737193)
  let long0 = or(d.long0, 0.7417649320975901 - 0.308341501185665)
  let k0 = or(d.k0, 0.9999)
  let alfa = (1.0 + e2 * m.pow(m.cos(fi0), 4.0) / (1.0 - e2)).sqrt()
  let uq = 1.04216856380474
  let u0 = m.asin(m.sin(fi0) / alfa)
  let g = m.pow((1.0 + e * m.sin(fi0)) / (1.0 - e * m.sin(fi0)), alfa * e / 2.0)
  let k = m.tan(u0 / 2.0 + KROVAK_S45) /
    m.pow(m.tan(fi0 / 2.0 + KROVAK_S45), alfa) *
    g
  let n0 = a * (1.0 - e2).sqrt() / (1.0 - e2 * m.pow(m.sin(fi0), 2.0))
  {
    m,
    long0,
    czech: d.czech,
    e,
    alfa,
    k,
    ro0: k0 * n0 / m.tan(KROVAK_S0),
    n: m.sin(KROVAK_S0),
    ad: 2.0 * KROVAK_S45 - uq,
  }
}

///|
fn Krovak::forward(
  self : Krovak,
  lon : Double,
  lat : Double,
) -> (Double, Double) {
  let m = self.m
  let delta_lon = adjust_lon(lon - self.long0)
  let gfi = m.pow(
    (1.0 + self.e * m.sin(lat)) / (1.0 - self.e * m.sin(lat)),
    self.alfa * self.e / 2.0,
  )
  let u = 2.0 *
    (
      m.atan(self.k * m.pow(m.tan(lat / 2.0 + KROVAK_S45), self.alfa) / gfi) -
      KROVAK_S45
    )
  let deltav = -delta_lon * self.alfa
  let s = m.asin(
    m.cos(self.ad) * m.sin(u) + m.sin(self.ad) * m.cos(u) * m.cos(deltav),
  )
  let d = m.asin(m.cos(u) * m.sin(deltav) / m.cos(s))
  let eps = self.n * d
  let ro = self.ro0 *
    m.pow(m.tan(KROVAK_S0 / 2.0 + KROVAK_S45), self.n) /
    m.pow(m.tan(s / 2.0 + KROVAK_S45), self.n)
  let y = ro * m.cos(eps)
  let x = ro * m.sin(eps)
  if self.czech {
    (x, y)
  } else {
    (-x, -y)
  }
}

///|
fn Krovak::inverse(self : Krovak, x : Double, y : Double) -> (Double, Double) {
  let m = self.m
  let (x, y) = if self.czech { (y, x) } else { (-y, -x) }
  let ro = (x * x + y * y).sqrt()
  let eps = m.atan2(y, x)
  let d = eps / m.sin(KROVAK_S0)
  let s = 2.0 *
    (
      m.atan(
        m.pow(self.ro0 / ro, 1.0 / self.n) * m.tan(KROVAK_S0 / 2.0 + KROVAK_S45),
      ) -
      KROVAK_S45
    )
  let u = m.asin(
    m.cos(self.ad) * m.sin(s) - m.sin(self.ad) * m.cos(s) * m.cos(d),
  )
  let deltav = m.asin(m.cos(s) * m.sin(d) / m.cos(u))
  let lon = self.long0 - deltav / self.alfa
  let mut fi1 = u
  for _ in 0..<15 {
    let lat = 2.0 *
      (
        m.atan(
          m.pow(self.k, -1.0 / self.alfa) *
          m.pow(m.tan(u / 2.0 + KROVAK_S45), 1.0 / self.alfa) *
          m.pow(
            (1.0 + self.e * m.sin(fi1)) / (1.0 - self.e * m.sin(fi1)),
            self.e / 2.0,
          ),
        ) -
        KROVAK_S45
      )
    if (fi1 - lat).abs() < 0.0000000001 {
      return (lon, lat)
    }
    fi1 = lat
  }
  nan2
}
