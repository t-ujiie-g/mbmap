// Port of GeographicLib's geographiclib-geodesic 2.2.0 (src/GeodesicLine.js),
// MIT License, Copyright (c) Charles Karney (2011-2022). See NOTICE. Only the
// capabilities for latitude, longitude, azimuth and distance are kept.

///|
/// A geodesic from point 1 (`lat1`, `lon1`, azimuth `azi1`, degrees), whose
/// points are found by distance or arc length; `s13` and `a13` are the
/// distance and arc to point 3 when the line was made from two points.
pub struct GeodesicLine {
  lat1 : Double
  lon1 : Double
  azi1 : Double
  s13 : Double
  a13 : Double
  priv geod : Geodesic
  priv salp0 : Double
  priv calp0 : Double
  priv ssig1 : Double
  priv csig1 : Double
  priv somg1 : Double
  priv comg1 : Double
  priv k2 : Double
  priv a1m1 : Double
  priv c1a : FixedArray[Double]
  priv b11 : Double
  priv stau1 : Double
  priv ctau1 : Double
  priv c1pa : FixedArray[Double]
  priv c3a : FixedArray[Double]
  priv a3c : Double
  priv b31 : Double
}

///|
fn GeodesicLine::make(
  geod : Geodesic,
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
  salp1 : Double,
  calp1 : Double,
  s13 : Double,
  a13 : Double,
) -> GeodesicLine {
  let trig = geod.trig
  let lat1 = lat_fix(lat1)
  let (s, c) = sincosd(trig, ang_round(lat1))
  let mut sbet1 = geod.f1 * s
  let mut cbet1 = c
  let t = hypot(sbet1, cbet1)
  sbet1 /= t
  cbet1 /= t
  cbet1 = jmax(TINY, cbet1)
  let salp0 = salp1 * cbet1
  let calp0 = hypot(calp1, salp1 * sbet1)
  let mut ssig1 = sbet1
  let somg1 = salp0 * sbet1
  let comg1 = if sbet1 != 0.0 || calp1 != 0.0 { cbet1 * calp1 } else { 1.0 }
  let mut csig1 = comg1
  let t = hypot(ssig1, csig1)
  ssig1 /= t
  csig1 /= t
  let k2 = sq(calp0) * geod.ep2
  let eps = k2 / (2.0 * (1.0 + (1.0 + k2).sqrt()) + k2)
  let a1m1 = a1m1f(eps)
  let c1a = FixedArray::make(ORDER + 1, 0.0)
  fourier(c1f_coeff, eps, c1a)
  let b11 = sin_cos_series(true, ssig1, csig1, c1a)
  let s = trig.sin(b11)
  let c = trig.cos(b11)
  let stau1 = ssig1 * c + csig1 * s
  let ctau1 = csig1 * c - ssig1 * s
  let c1pa = FixedArray::make(ORDER + 1, 0.0)
  fourier(c1pf_coeff, eps, c1pa)
  let c3a = FixedArray::make(ORDER, 0.0)
  geod.c3f(eps, c3a)
  let a3c = -geod.f * salp0 * geod.a3f(eps)
  let b31 = sin_cos_series(true, ssig1, csig1, c3a)
  {
    lat1,
    lon1,
    azi1,
    s13,
    a13,
    geod,
    salp0,
    calp0,
    ssig1,
    csig1,
    somg1,
    comg1,
    k2,
    a1m1,
    c1a,
    b11,
    stau1,
    ctau1,
    c1pa,
    c3a,
    a3c,
    b31,
  }
}

///|
/// The geodesic leaving (`lat1`, `lon1`) at azimuth `azi1` (degrees).
pub fn Geodesic::line(
  self : Geodesic,
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
) -> GeodesicLine {
  let azi1 = ang_normalize(azi1)
  let (salp1, calp1) = sincosd(self.trig, ang_round(azi1))
  GeodesicLine::make(self, lat1, lon1, azi1, salp1, calp1, nan, nan)
}

///|
/// The geodesic from point 1 to point 2 (degrees), which is point 3 of the
/// line (`s13`, `a13`).
pub fn Geodesic::inverse_line(
  self : Geodesic,
  lat1 : Double,
  lon1 : Double,
  lat2 : Double,
  lon2 : Double,
) -> GeodesicLine {
  let r = self.inverse_int(lat1, lon1, lat2, lon2, false)
  let azi1 = atan2d(self.trig, r.salp1, r.calp1)
  let line = GeodesicLine::make(
    self,
    lat1,
    lon1,
    azi1,
    r.salp1,
    r.calp1,
    nan,
    r.a12,
  )
  { ..line, s13: line.position(true, r.a12).s12, }
}

///|
/// A point on a geodesic line: `lat2`, `lon2`, `azi2` in degrees, `s12` the
/// distance from point 1 in meters and `a12` the arc in degrees.
pub(all) struct Position {
  lat2 : Double
  lon2 : Double
  azi2 : Double
  s12 : Double
  a12 : Double
}

///|
/// `GenPosition`: the point `s12_a12` meters (or degrees of arc, `arcmode`)
/// along the line; `unroll` lets the longitude run past ±180 continuously.
pub fn GeodesicLine::position(
  self : GeodesicLine,
  arcmode : Bool,
  s12_a12 : Double,
  unroll~ : Bool = false,
) -> Position {
  let geod = self.geod
  let trig = geod.trig
  let mut b12 = 0.0
  let mut sig12 = 0.0
  let mut ssig12 = 0.0
  let mut csig12 = 0.0
  if arcmode {
    sig12 = s12_a12 * DEGREE
    let (s, c) = sincosd(trig, s12_a12)
    ssig12 = s
    csig12 = c
  } else {
    let tau12 = s12_a12 / (geod.b * (1.0 + self.a1m1))
    let s = trig.sin(tau12)
    let c = trig.cos(tau12)
    b12 = -sin_cos_series(
      true,
      self.stau1 * c + self.ctau1 * s,
      self.ctau1 * c - self.stau1 * s,
      self.c1pa,
    )
    sig12 = tau12 - (b12 - self.b11)
    ssig12 = trig.sin(sig12)
    csig12 = trig.cos(sig12)
    if geod.f.abs() > 0.01 {
      let ssig2 = self.ssig1 * csig12 + self.csig1 * ssig12
      let csig2 = self.csig1 * csig12 - self.ssig1 * ssig12
      b12 = sin_cos_series(true, ssig2, csig2, self.c1a)
      let serr = (1.0 + self.a1m1) * (sig12 + (b12 - self.b11)) -
        s12_a12 / geod.b
      sig12 = sig12 - serr / (1.0 + self.k2 * sq(ssig2)).sqrt()
      ssig12 = trig.sin(sig12)
      csig12 = trig.cos(sig12)
    }
  }
  let ssig2 = self.ssig1 * csig12 + self.csig1 * ssig12
  let mut csig2 = self.csig1 * csig12 - self.ssig1 * ssig12
  let s12 = if arcmode {
    let b12 = sin_cos_series(true, ssig2, csig2, self.c1a)
    let ab1 = (1.0 + self.a1m1) * (b12 - self.b11)
    geod.b * ((1.0 + self.a1m1) * sig12 + ab1)
  } else {
    s12_a12
  }
  let sbet2 = self.calp0 * ssig2
  let mut cbet2 = hypot(self.salp0, self.calp0 * csig2)
  if cbet2 == 0.0 {
    cbet2 = TINY
    csig2 = TINY
  }
  let salp2 = self.salp0
  let calp2 = self.calp0 * csig2
  let somg2 = self.salp0 * ssig2
  let comg2 = csig2
  let e = copysign(1.0, self.salp0)
  let omg12 = if unroll {
    e *
    (
      sig12 -
      (trig.atan2(ssig2, csig2) - trig.atan2(self.ssig1, self.csig1)) +
      (trig.atan2(e * somg2, comg2) - trig.atan2(e * self.somg1, self.comg1))
    )
  } else {
    trig.atan2(
      somg2 * self.comg1 - comg2 * self.somg1,
      comg2 * self.comg1 + somg2 * self.somg1,
    )
  }
  let lam12 = omg12 +
    self.a3c *
    (sig12 + (sin_cos_series(true, ssig2, csig2, self.c3a) - self.b31))
  let lon12 = lam12 / DEGREE
  let lon2 = if unroll {
    self.lon1 + lon12
  } else {
    ang_normalize(ang_normalize(self.lon1) + ang_normalize(lon12))
  }
  {
    lat2: atan2d(trig, sbet2, geod.f1 * cbet2),
    lon2,
    azi2: atan2d(trig, salp2, calp2),
    s12,
    a12: if arcmode {
      s12_a12
    } else {
      sig12 / DEGREE
    },
  }
}

///|
/// Solves the direct problem: the point `s12` meters from (`lat1`, `lon1`)
/// at azimuth `azi1` (degrees).
pub fn Geodesic::direct(
  self : Geodesic,
  lat1 : Double,
  lon1 : Double,
  azi1 : Double,
  s12 : Double,
) -> Position {
  self.line(lat1, lon1, azi1).position(false, s12)
}
