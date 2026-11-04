// Port of GeographicLib's geographiclib-geodesic 2.2.0 (src/Geodesic.js), MIT
// License, Copyright (c) Charles Karney (2011-2022). See NOTICE. Algorithms
// from C. F. F. Karney, Algorithms for geodesics, J. Geodesy 87, 43-55 (2013).

///|
const ORDER : Int32 = 6

///|
const MAXIT1 : Int32 = 20

///|
const MAXIT2 : Int32 = 83

///|
const TOL0 : Double = 2.220446049250313e-16

///|
const TOL1 : Double = 4.440892098500626e-14

///|
const TOL2 : Double = 1.4901161193847656e-8

///|
const XTHRESH : Double = 1.4901161193847656e-5

///|
/// sqrt of the smallest normal double, 2^-511.
const TINY : Double = 1.4916681462400413e-154

///|
const PI : Double = 3.141592653589793

///|
/// The positive root k of k^4 + 2k^3 - (x^2 + y^2 - 1)k^2 - 2y^2k - y^2 = 0.
fn astroid(trig : Trig, x : Double, y : Double) -> Double {
  let p = sq(x)
  let q = sq(y)
  let r = (p + q - 1.0) / 6.0
  if q == 0.0 && r <= 0.0 {
    return 0.0
  }
  let s = p * q / 4.0
  let r2 = sq(r)
  let r3 = r * r2
  let disc = s * (s + 2.0 * r3)
  let mut u = r
  if disc >= 0.0 {
    let mut t3 = s + r3
    t3 += if t3 < 0.0 { -disc.sqrt() } else { disc.sqrt() }
    let t = trig.cbrt(t3)
    u += t + (if t != 0.0 { r2 / t } else { 0.0 })
  } else {
    let ang = trig.atan2((-disc).sqrt(), -(s + r3))
    u += 2.0 * r * trig.cos(ang / 3.0)
  }
  let v = (sq(u) + q).sqrt()
  let uv = if u < 0.0 { q / (v - u) } else { u + v }
  let w = (uv - q) / (2.0 * v)
  uv / ((uv + sq(w)).sqrt() + w)
}

///|
/// An ellipsoid of revolution with geodesic problems solved on it: `a` is the
/// equatorial radius in meters and `f` the flattening.
pub struct Geodesic {
  a : Double
  f : Double
  priv f1 : Double
  priv e2 : Double
  priv ep2 : Double
  priv n : Double
  priv b : Double
  priv c2 : Double
  priv etol2 : Double
  priv a3x : FixedArray[Double]
  priv c3x : FixedArray[Double]
  priv c4x : FixedArray[Double]
  priv trig : Trig
}

///|
/// The ellipsoid with equatorial radius `a` (meters) and flattening `f`;
/// None unless both semi-axes are finite and positive.
pub fn Geodesic::new(
  a : Double,
  f : Double,
  trig~ : Trig = Trig::moonbit(),
) -> Geodesic? {
  let f1 = 1.0 - f
  let e2 = f * (2.0 - f)
  let b = a * f1
  if !(a > 0.0 && !a.is_inf() && b > 0.0 && !b.is_inf()) {
    return None
  }
  let n = f / (2.0 - f)
  let c2 = (
      sq(a) +
      sq(b) *
      (if e2 == 0.0 {
        1.0
      } else {
        (if e2 > 0.0 { trig.atanh(e2.sqrt()) } else { trig.atan((-e2).sqrt()) }) /
        e2.abs().sqrt()
      })
    ) /
    2.0
  let etol2 = 0.1 *
    TOL2 /
    (jmax(0.001, f.abs()) * jmin(1.0, 1.0 - f / 2.0) / 2.0).sqrt()
  let a3x = FixedArray::make(ORDER, 0.0)
  let mut o = 0
  let mut k = 0
  for j = ORDER - 1; j >= 0; j = j - 1 {
    let p = if ORDER - j - 1 < j { ORDER - j - 1 } else { j }
    a3x[k] = polyval(p, a3_coeff, o, n) / a3_coeff[o + p + 1]
    k += 1
    o += p + 2
  }
  let c3x = FixedArray::make(ORDER * (ORDER - 1) / 2, 0.0)
  o = 0
  k = 0
  for l in 1..<ORDER {
    for j = ORDER - 1; j >= l; j = j - 1 {
      let p = if ORDER - j - 1 < j { ORDER - j - 1 } else { j }
      c3x[k] = polyval(p, c3_coeff, o, n) / c3_coeff[o + p + 1]
      k += 1
      o += p + 2
    }
  }
  let c4x = FixedArray::make(ORDER * (ORDER + 1) / 2, 0.0)
  o = 0
  k = 0
  for l in 0..<ORDER {
    for j = ORDER - 1; j >= l; j = j - 1 {
      let p = ORDER - j - 1
      c4x[k] = polyval(p, c4_coeff, o, n) / c4_coeff[o + p + 1]
      k += 1
      o += p + 2
    }
  }
  Some({ a, f, f1, e2, ep2: e2 / sq(f1), n, b, c2, etol2, a3x, c3x, c4x, trig, })
}

///|
/// WGS 84's equatorial radius in meters.
pub const WGS84_A : Double = 6378137.0

///|
/// WGS 84's flattening.
pub const WGS84_F : Double = 0.0033528106647474805

///|
/// The WGS 84 ellipsoid.
pub fn Geodesic::wgs84(trig~ : Trig = Trig::moonbit()) -> Geodesic {
  Geodesic::new(WGS84_A, WGS84_F, trig~).unwrap()
}

///|
/// Scratch coefficient arrays of one solution (index 0 of `c1a`, `c2a` unused).
priv struct Coeffs {
  c1a : FixedArray[Double]
  c2a : FixedArray[Double]
  c3a : FixedArray[Double]
}

///|
fn Coeffs::new() -> Coeffs {
  {
    c1a: FixedArray::make(ORDER + 1, 0.0),
    c2a: FixedArray::make(ORDER + 1, 0.0),
    c3a: FixedArray::make(ORDER, 0.0),
  }
}

///|
/// `Lengths`: distance / b (`s12b`, when `distance`), reduced length / b
/// (`m12b`, NaN unless `reduced`) and the secular coefficient `m0`.
fn lengths(
  eps : Double,
  sig12 : Double,
  ssig1 : Double,
  csig1 : Double,
  dn1 : Double,
  ssig2 : Double,
  csig2 : Double,
  dn2 : Double,
  distance : Bool,
  reduced : Bool,
  c : Coeffs,
) -> (Double, Double, Double) {
  let mut m0x = 0.0
  let mut j12 = 0.0
  let mut a1 = 0.0
  let mut a2 = 0.0
  let mut s12b = nan
  a1 = a1m1f(eps)
  fourier(c1f_coeff, eps, c.c1a)
  if reduced {
    a2 = a2m1f(eps)
    fourier(c2f_coeff, eps, c.c2a)
    m0x = a1 - a2
    a2 = 1.0 + a2
  }
  a1 = 1.0 + a1
  if distance {
    let b1 = sin_cos_series(true, ssig2, csig2, c.c1a) -
      sin_cos_series(true, ssig1, csig1, c.c1a)
    s12b = a1 * (sig12 + b1)
    if reduced {
      let b2 = sin_cos_series(true, ssig2, csig2, c.c2a) -
        sin_cos_series(true, ssig1, csig1, c.c2a)
      j12 = m0x * sig12 + (a1 * b1 - a2 * b2)
    }
  } else if reduced {
    for l in 1..<=ORDER {
      c.c2a[l] = a1 * c.c1a[l] - a2 * c.c2a[l]
    }
    j12 = m0x * sig12 +
      (
        sin_cos_series(true, ssig2, csig2, c.c2a) -
        sin_cos_series(true, ssig1, csig1, c.c2a)
      )
  }
  let m12b = if reduced {
    dn2 * (csig1 * ssig2) - dn1 * (ssig1 * csig2) - csig1 * csig2 * j12
  } else {
    nan
  }
  (s12b, m12b, m0x)
}

///|
/// `InverseStart`'s result: `sig12` is -1 unless the line is short enough to
/// need no Newton's method, when `salp2`, `calp2` and `dnm` are set too.
priv struct Start {
  sig12 : Double
  salp1 : Double
  calp1 : Double
  salp2 : Double
  calp2 : Double
  dnm : Double
}

///|
fn Geodesic::inverse_start(
  self : Geodesic,
  sbet1 : Double,
  cbet1 : Double,
  dn1 : Double,
  sbet2 : Double,
  cbet2 : Double,
  dn2 : Double,
  lam12 : Double,
  slam12 : Double,
  clam12 : Double,
  c : Coeffs,
) -> Start {
  let trig = self.trig
  let mut sig12 = -1.0
  let mut salp2 = nan
  let mut calp2 = nan
  let mut dnm = nan
  let sbet12 = sbet2 * cbet1 - cbet2 * sbet1
  let cbet12 = cbet2 * cbet1 + sbet2 * sbet1
  let mut sbet12a = sbet2 * cbet1
  sbet12a += cbet2 * sbet1
  let shortline = cbet12 >= 0.0 && sbet12 < 0.5 && cbet2 * lam12 < 0.5
  let mut somg12 = slam12
  let mut comg12 = clam12
  if shortline {
    let mut sbetm2 = sq(sbet1 + sbet2)
    sbetm2 /= sbetm2 + sq(cbet1 + cbet2)
    dnm = (1.0 + self.ep2 * sbetm2).sqrt()
    let omg12 = lam12 / (self.f1 * dnm)
    somg12 = trig.sin(omg12)
    comg12 = trig.cos(omg12)
  }
  let mut salp1 = cbet2 * somg12
  let mut calp1 = if comg12 >= 0.0 {
    sbet12 + cbet2 * sbet1 * sq(somg12) / (1.0 + comg12)
  } else {
    sbet12a - cbet2 * sbet1 * sq(somg12) / (1.0 - comg12)
  }
  let ssig12 = hypot(salp1, calp1)
  let csig12 = sbet1 * sbet2 + cbet1 * cbet2 * comg12
  if shortline && ssig12 < self.etol2 {
    salp2 = cbet1 * somg12
    calp2 = sbet12 -
      cbet1 *
      sbet2 *
      (if comg12 >= 0.0 { sq(somg12) / (1.0 + comg12) } else { 1.0 - comg12 })
    let t = hypot(salp2, calp2)
    salp2 /= t
    calp2 /= t
    sig12 = trig.atan2(ssig12, csig12)
  } else if self.n.abs() > 0.1 ||
    csig12 >= 0.0 ||
    ssig12 >= 6.0 * self.n.abs() * PI * sq(cbet1) {
    ()
  } else {
    let lam12x = trig.atan2(-slam12, -clam12)
    let mut x = 0.0
    let mut y = 0.0
    let mut lamscale = 0.0
    if self.f >= 0.0 {
      let k2 = sq(sbet1) * self.ep2
      let eps = k2 / (2.0 * (1.0 + (1.0 + k2).sqrt()) + k2)
      lamscale = self.f * cbet1 * self.a3f(eps) * PI
      let betscale = lamscale * cbet1
      x = lam12x / lamscale
      y = sbet12a / betscale
    } else {
      let cbet12a = cbet2 * cbet1 - sbet2 * sbet1
      let bet12a = trig.atan2(sbet12a, cbet12a)
      let (_, m12b, m0) = lengths(
        self.n,
        PI + bet12a,
        sbet1,
        -cbet1,
        dn1,
        sbet2,
        cbet2,
        dn2,
        false,
        true,
        c,
      )
      x = -1.0 + m12b / (cbet1 * cbet2 * m0 * PI)
      let betscale = if x < -0.01 {
        sbet12a / x
      } else {
        -self.f * sq(cbet1) * PI
      }
      lamscale = betscale / cbet1
      y = lam12 / lamscale
    }
    if y > -TOL1 && x > -1.0 - XTHRESH {
      if self.f >= 0.0 {
        salp1 = jmin(1.0, -x)
        calp1 = -(1.0 - sq(salp1)).sqrt()
      } else {
        calp1 = jmax(if x > -TOL1 { 0.0 } else { -1.0 }, x)
        salp1 = (1.0 - sq(calp1)).sqrt()
      }
    } else {
      let k = astroid(trig, x, y)
      let omg12a = lamscale *
        (if self.f >= 0.0 { -x * k / (1.0 + k) } else { -y * (1.0 + k) / k })
      somg12 = trig.sin(omg12a)
      comg12 = -trig.cos(omg12a)
      salp1 = cbet2 * somg12
      calp1 = sbet12a - cbet2 * sbet1 * sq(somg12) / (1.0 - comg12)
    }
  }
  if !(salp1 <= 0.0) {
    let t = hypot(salp1, calp1)
    salp1 /= t
    calp1 /= t
  } else {
    salp1 = 1.0
    calp1 = 0.0
  }
  { sig12, salp1, calp1, salp2, calp2, dnm, }
}

///|
/// `Lambda12`'s result for one guess of alp1.
priv struct Lambda {
  lam12 : Double
  salp2 : Double
  calp2 : Double
  sig12 : Double
  ssig1 : Double
  csig1 : Double
  ssig2 : Double
  csig2 : Double
  eps : Double
  domg12 : Double
  dlam12 : Double
}

///|
fn Geodesic::lambda12(
  self : Geodesic,
  sbet1 : Double,
  cbet1 : Double,
  dn1 : Double,
  sbet2 : Double,
  cbet2 : Double,
  dn2 : Double,
  salp1 : Double,
  calp1 : Double,
  slam120 : Double,
  clam120 : Double,
  diffp : Bool,
  c : Coeffs,
) -> Lambda {
  let trig = self.trig
  let calp1 = if sbet1 == 0.0 && calp1 == 0.0 { -TINY } else { calp1 }
  let salp0 = salp1 * cbet1
  let calp0 = hypot(calp1, salp1 * sbet1)
  let mut ssig1 = sbet1
  let somg1 = salp0 * sbet1
  let comg1 = calp1 * cbet1
  let mut csig1 = comg1
  let t = hypot(ssig1, csig1)
  ssig1 /= t
  csig1 /= t
  let salp2 = if cbet2 != cbet1 { salp0 / cbet2 } else { salp1 }
  let calp2 = if cbet2 != cbet1 || sbet2.abs() != -sbet1 {
    (sq(calp1 * cbet1) +
    (if cbet1 < -sbet1 {
      (cbet2 - cbet1) * (cbet1 + cbet2)
    } else {
      (sbet1 - sbet2) * (sbet1 + sbet2)
    })).sqrt() /
    cbet2
  } else {
    calp1.abs()
  }
  let mut ssig2 = sbet2
  let somg2 = salp0 * sbet2
  let comg2 = calp2 * cbet2
  let mut csig2 = comg2
  let t = hypot(ssig2, csig2)
  ssig2 /= t
  csig2 /= t
  let sig12 = trig.atan2(
    jmax(0.0, csig1 * ssig2 - ssig1 * csig2),
    csig1 * csig2 + ssig1 * ssig2,
  )
  let somg12 = jmax(0.0, comg1 * somg2 - somg1 * comg2)
  let comg12 = comg1 * comg2 + somg1 * somg2
  let eta = trig.atan2(
    somg12 * clam120 - comg12 * slam120,
    comg12 * clam120 + somg12 * slam120,
  )
  let k2 = sq(calp0) * self.ep2
  let eps = k2 / (2.0 * (1.0 + (1.0 + k2).sqrt()) + k2)
  self.c3f(eps, c.c3a)
  let b312 = sin_cos_series(true, ssig2, csig2, c.c3a) -
    sin_cos_series(true, ssig1, csig1, c.c3a)
  let domg12 = -self.f * self.a3f(eps) * salp0 * (sig12 + b312)
  let lam12 = eta + domg12
  let dlam12 = if !diffp {
    nan
  } else if calp2 == 0.0 {
    -2.0 * self.f1 * dn1 / sbet1
  } else {
    let (_, m12b, _) = lengths(
      eps, sig12, ssig1, csig1, dn1, ssig2, csig2, dn2, false, true, c,
    )
    m12b * (self.f1 / (calp2 * cbet2))
  }
  {
    lam12,
    salp2,
    calp2,
    sig12,
    ssig1,
    csig1,
    ssig2,
    csig2,
    eps,
    domg12,
    dlam12,
  }
}

///|
/// An inverse problem's solution: `s12` meters, `azi1` and `azi2` degrees at
/// each end, `a12` the arc in degrees, `area` (S12) square meters between the
/// geodesic and the equator (NaN unless asked for).
pub(all) struct Inverse {
  s12 : Double
  azi1 : Double
  azi2 : Double
  a12 : Double
  area : Double
}

///|
/// `InverseInt`, with the sines and cosines of the azimuths.
priv struct InverseSolution {
  s12 : Double
  a12 : Double
  area : Double
  salp1 : Double
  calp1 : Double
  salp2 : Double
  calp2 : Double
}

///|
fn Geodesic::inverse_int(
  self : Geodesic,
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
  area : Bool,
) -> InverseSolution {
  let trig = self.trig
  let mut lat1 = ang_round(lat_fix(lat1))
  let mut lat2 = ang_round(lat_fix(lat2))
  let (lon12, lon12s) = ang_diff(lon1, lon2)
  let mut lonsign = copysign(1.0, lon12)
  let lon12 = lon12 * lonsign
  let lon12s = lon12s * lonsign
  let lam12 = lon12 * DEGREE
  let (slam12, clam12) = sincosde(trig, lon12, lon12s, true)
  let lon12s = 180.0 - lon12 - lon12s
  let swapp = if lat1.abs() < lat2.abs() || lat2.is_nan() { -1.0 } else { 1.0 }
  if swapp < 0.0 {
    lonsign *= -1.0
    let t = lat1
    lat1 = lat2
    lat2 = t
  }
  let latsign = copysign(1.0, -lat1)
  lat1 *= latsign
  lat2 *= latsign
  let (s, c) = sincosd(trig, lat1)
  let mut sbet1 = self.f1 * s
  let mut cbet1 = c
  let t = hypot(sbet1, cbet1)
  sbet1 /= t
  cbet1 /= t
  cbet1 = jmax(TINY, cbet1)
  let (s, c) = sincosd(trig, lat2)
  let mut sbet2 = self.f1 * s
  let mut cbet2 = c
  let t = hypot(sbet2, cbet2)
  sbet2 /= t
  cbet2 /= t
  cbet2 = jmax(TINY, cbet2)
  if cbet1 < -sbet1 {
    if cbet2 == cbet1 {
      sbet2 = copysign(sbet1, sbet2)
    }
  } else if sbet2.abs() == -sbet1 {
    cbet2 = cbet1
  }
  let dn1 = (1.0 + self.ep2 * sq(sbet1)).sqrt()
  let dn2 = (1.0 + self.ep2 * sq(sbet2)).sqrt()
  let coeffs = Coeffs::new()
  let mut a12 = nan
  let mut s12x = nan
  let mut sig12 = 0.0
  let mut salp1 = 0.0
  let mut calp1 = 0.0
  let mut salp2 = 0.0
  let mut calp2 = 0.0
  let mut omg12 = 0.0
  let mut somg12 = 2.0
  let mut comg12 = 0.0
  let mut meridian = lat1 == -90.0 || slam12 == 0.0
  if meridian {
    calp1 = clam12
    salp1 = slam12
    calp2 = 1.0
    salp2 = 0.0
    let ssig1 = sbet1
    let csig1 = calp1 * cbet1
    let ssig2 = sbet2
    let csig2 = calp2 * cbet2
    sig12 = trig.atan2(
      jmax(0.0, csig1 * ssig2 - ssig1 * csig2),
      csig1 * csig2 + ssig1 * ssig2,
    )
    let (s12b, m12b, _) = lengths(
      self.n,
      sig12,
      ssig1,
      csig1,
      dn1,
      ssig2,
      csig2,
      dn2,
      true,
      true,
      coeffs,
    )
    let mut s12b = s12b
    let mut m12x = m12b
    if sig12 < TOL2 || m12x >= 0.0 {
      if sig12 < 3.0 * TINY || (sig12 < TOL0 && (s12b < 0.0 || m12x < 0.0)) {
        sig12 = 0.0
        m12x = 0.0
        s12b = 0.0
      }
      s12x = s12b * self.b
      a12 = sig12 / DEGREE
    } else {
      meridian = false
    }
  }
  if !meridian && sbet1 == 0.0 && (self.f <= 0.0 || lon12s >= self.f * 180.0) {
    calp1 = 0.0
    calp2 = 0.0
    salp1 = 1.0
    salp2 = 1.0
    s12x = self.a * lam12
    sig12 = lam12 / self.f1
    omg12 = sig12
    a12 = lon12 / self.f1
  } else if !meridian {
    let start = self.inverse_start(
      sbet1, cbet1, dn1, sbet2, cbet2, dn2, lam12, slam12, clam12, coeffs,
    )
    sig12 = start.sig12
    salp1 = start.salp1
    calp1 = start.calp1
    if sig12 >= 0.0 {
      salp2 = start.salp2
      calp2 = start.calp2
      let dnm = start.dnm
      s12x = sig12 * self.b * dnm
      a12 = sig12 / DEGREE
      omg12 = lam12 / (self.f1 * dnm)
    } else {
      let mut numit = 0
      let mut salp1a = TINY
      let mut calp1a = 1.0
      let mut salp1b = TINY
      let mut calp1b = -1.0
      let mut tripn = false
      let mut tripb = false
      let mut l = self.lambda12(
        sbet1,
        cbet1,
        dn1,
        sbet2,
        cbet2,
        dn2,
        salp1,
        calp1,
        slam12,
        clam12,
        numit < MAXIT1,
        coeffs,
      )
      while !(tripb ||
            !(l.lam12.abs() >= (if tripn { 8.0 } else { 1.0 }) * TOL0) ||
            numit == MAXIT2) {
        let v = l.lam12
        let dv = l.dlam12
        if v > 0.0 && (numit < MAXIT1 || calp1 / salp1 > calp1b / salp1b) {
          salp1b = salp1
          calp1b = calp1
        } else if v < 0.0 && (numit < MAXIT1 || calp1 / salp1 < calp1a / salp1a) {
          salp1a = salp1
          calp1a = calp1
        }
        let mut newton = false
        if numit < MAXIT1 && dv > 0.0 {
          let dalp1 = -v / dv
          if dalp1.abs() < PI {
            let sdalp1 = trig.sin(dalp1)
            let cdalp1 = trig.cos(dalp1)
            let nsalp1 = salp1 * cdalp1 + calp1 * sdalp1
            if nsalp1 > 0.0 {
              calp1 = calp1 * cdalp1 - salp1 * sdalp1
              salp1 = nsalp1
              let t = hypot(salp1, calp1)
              salp1 /= t
              calp1 /= t
              tripn = v.abs() <= 16.0 * TOL0
              newton = true
            }
          }
        }
        if !newton {
          salp1 = (salp1a + salp1b) / 2.0
          calp1 = (calp1a + calp1b) / 2.0
          let t = hypot(salp1, calp1)
          salp1 /= t
          calp1 /= t
          tripn = false
          tripb = (salp1a - salp1).abs() + (calp1a - calp1) < TOL0 ||
            (salp1 - salp1b).abs() + (calp1 - calp1b) < TOL0
        }
        numit += 1
        l = self.lambda12(
          sbet1,
          cbet1,
          dn1,
          sbet2,
          cbet2,
          dn2,
          salp1,
          calp1,
          slam12,
          clam12,
          numit < MAXIT1,
          coeffs,
        )
      }
      salp2 = l.salp2
      calp2 = l.calp2
      sig12 = l.sig12
      let (s12b, _, _) = lengths(
        l.eps,
        sig12,
        l.ssig1,
        l.csig1,
        dn1,
        l.ssig2,
        l.csig2,
        dn2,
        true,
        false,
        coeffs,
      )
      s12x = s12b * self.b
      a12 = sig12 / DEGREE
      if area {
        let sdomg12 = trig.sin(l.domg12)
        let cdomg12 = trig.cos(l.domg12)
        somg12 = slam12 * cdomg12 - clam12 * sdomg12
        comg12 = clam12 * cdomg12 + slam12 * sdomg12
      }
    }
  }
  let s12 = 0.0 + s12x
  let mut s12_area = nan
  if area {
    let salp0 = salp1 * cbet1
    let calp0 = hypot(calp1, salp1 * sbet1)
    s12_area = if calp0 != 0.0 && salp0 != 0.0 {
      let mut ssig1 = sbet1
      let mut csig1 = calp1 * cbet1
      let mut ssig2 = sbet2
      let mut csig2 = calp2 * cbet2
      let k2 = sq(calp0) * self.ep2
      let eps = k2 / (2.0 * (1.0 + (1.0 + k2).sqrt()) + k2)
      let a4 = sq(self.a) * calp0 * salp0 * self.e2
      let t = hypot(ssig1, csig1)
      ssig1 /= t
      csig1 /= t
      let t = hypot(ssig2, csig2)
      ssig2 /= t
      csig2 /= t
      let c4a = FixedArray::make(ORDER, 0.0)
      self.c4f(eps, c4a)
      let b41 = sin_cos_series(false, ssig1, csig1, c4a)
      let b42 = sin_cos_series(false, ssig2, csig2, c4a)
      a4 * (b42 - b41)
    } else {
      0.0
    }
    if !meridian && somg12 == 2.0 {
      somg12 = trig.sin(omg12)
      comg12 = trig.cos(omg12)
    }
    let alp12 = if !meridian && comg12 > -0.7071 && sbet2 - sbet1 < 1.75 {
      let domg12 = 1.0 + comg12
      let dbet1 = 1.0 + cbet1
      let dbet2 = 1.0 + cbet2
      2.0 *
      trig.atan2(
        somg12 * (sbet1 * dbet2 + sbet2 * dbet1),
        domg12 * (sbet1 * sbet2 + dbet1 * dbet2),
      )
    } else {
      let mut salp12 = salp2 * calp1 - calp2 * salp1
      let mut calp12 = calp2 * calp1 + salp2 * salp1
      if salp12 == 0.0 && calp12 < 0.0 {
        salp12 = TINY * calp1
        calp12 = -1.0
      }
      trig.atan2(salp12, calp12)
    }
    s12_area += self.c2 * alp12
    s12_area *= swapp * lonsign * latsign
    s12_area += 0.0
  }
  if swapp < 0.0 {
    let t = salp1
    salp1 = salp2
    salp2 = t
    let t = calp1
    calp1 = calp2
    calp2 = t
  }
  salp1 *= swapp * lonsign
  calp1 *= swapp * latsign
  salp2 *= swapp * lonsign
  calp2 *= swapp * latsign
  { s12, a12, area: s12_area, salp1, calp1, salp2, calp2, }
}

///|
/// Solves the inverse problem between two points (degrees); `area` asks for
/// S12 too.
pub fn Geodesic::inverse(
  self : Geodesic,
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
  area~ : Bool = false,
) -> Inverse {
  let r = self.inverse_int(lat1, lon1, lat2, lon2, area)
  {
    s12: r.s12,
    azi1: atan2d(self.trig, r.salp1, r.calp1),
    azi2: atan2d(self.trig, r.salp2, r.calp2),
    a12: r.a12,
    area: r.area,
  }
}
