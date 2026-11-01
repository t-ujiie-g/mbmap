// Follows proj4js 2.22.0's extended transverse Mercator (lib/projections/
// etmerc.js and lib/common/gatg.js, clens.js, clens_cmplx.js, asinhy.js,
// hypot.js, log1py.js, sinh.js, adjust_lon.js: Poder/Engsager's Krüger series
// to 6th order), MIT License, Copyright (c) 2014, Mike Adair, Richard Greenwood,
// Didier Richard, Stephen Irons, Olivier Terral, Calvin Metcalf. See NOTICE.

///|
const PI : Double = 3.141592653589793

///|
/// Degrees to radians as proj4js converts them.
const D2R : Double = 0.01745329251994329577

///|
const R2D : Double = 57.29577951308232088

///|
/// Slightly more than π, as proj4js's `adjust_lon` tests against.
const SPI : Double = 3.14159265359

///|
fn adjust_lon(x : Double) -> Double {
  if x.abs() <= SPI {
    x
  } else {
    x - (if x < 0.0 { -1.0 } else { 1.0 }) * 2.0 * PI
  }
}

///|
fn sinh(x : Double) -> Double {
  let r = @math.exp(x)
  (r - 1.0 / r) / 2.0
}

///|
fn cosh(x : Double) -> Double {
  let r = @math.exp(x)
  (r + 1.0 / r) / 2.0
}

///|
fn hypot(x : Double, y : Double) -> Double {
  let x = x.abs()
  let y = y.abs()
  let a = @cmp.maximum(x, y)
  let b = @cmp.minimum(x, y) / (if a != 0.0 { a } else { 1.0 })
  a * (1.0 + b * b).sqrt()
}

///|
fn log1py(x : Double) -> Double {
  let y = 1.0 + x
  let z = y - 1.0
  if z == 0.0 {
    x
  } else {
    x * @math.ln(y) / z
  }
}

///|
fn asinhy(x : Double) -> Double {
  let y = x.abs()
  let y = log1py(y * (1.0 + y / (hypot(1.0, y) + 1.0)))
  if x < 0.0 {
    -y
  } else {
    y
  }
}

///|
/// Gaussian to geodetic latitude and back (`gatg`), by Clenshaw summation.
fn gatg(pp : FixedArray[Double], b : Double) -> Double {
  let cos_2b = 2.0 * @math.cos(2.0 * b)
  let mut i = pp.length() - 1
  let mut h1 = pp[i]
  let mut h2 = 0.0
  let mut h = 0.0
  while i > 0 {
    i -= 1
    h = -h2 + cos_2b * h1 + pp[i]
    h2 = h1
    h1 = h
  }
  b + h * @math.sin(2.0 * b)
}

///|
fn clens(pp : FixedArray[Double], arg_r : Double) -> Double {
  let r = 2.0 * @math.cos(arg_r)
  let mut i = pp.length() - 1
  let mut hr1 = pp[i]
  let mut hr2 = 0.0
  let mut hr = 0.0
  while i > 0 {
    i -= 1
    hr = -hr2 + r * hr1 + pp[i]
    hr2 = hr1
    hr1 = hr
  }
  @math.sin(arg_r) * hr
}

///|
fn clens_cmplx(
  pp : FixedArray[Double],
  arg_r : Double,
  arg_i : Double,
) -> (Double, Double) {
  let sin_arg_r = @math.sin(arg_r)
  let cos_arg_r = @math.cos(arg_r)
  let sinh_arg_i = sinh(arg_i)
  let cosh_arg_i = cosh(arg_i)
  let r = 2.0 * cos_arg_r * cosh_arg_i
  let i = -2.0 * sin_arg_r * sinh_arg_i
  let mut j = pp.length() - 1
  let mut hr = pp[j]
  let mut hi1 = 0.0
  let mut hr1 = 0.0
  let mut hi = 0.0
  while j > 0 {
    j -= 1
    let hr2 = hr1
    let hi2 = hi1
    hr1 = hr
    hi1 = hi
    hr = -hr2 + r * hr1 - i * hi1 + pp[j]
    hi = -hi2 + i * hr1 + r * hi1
  }
  let r = sin_arg_r * cosh_arg_i
  let i = cos_arg_r * sinh_arg_i
  (r * hr - i * hi, r * hi + i * hr)
}

///|
/// A transverse Mercator projection (`etmerc`): its ellipsoid's semi-major
/// axis, the origin, scale and false easting/northing, and the series'
/// coefficients.
priv struct Etmerc {
  a : Double
  long0 : Double
  x0 : Double
  y0 : Double
  qn : Double
  zb : Double
  cgb : FixedArray[Double]
  cbg : FixedArray[Double]
  utg : FixedArray[Double]
  gtu : FixedArray[Double]
}

///|
fn Etmerc::new(
  e : Ellipsoid,
  lat0 : Double,
  long0 : Double,
  k0 : Double,
  x0 : Double,
  y0 : Double,
) -> Etmerc {
  let es = e.es()
  let f = es / (1.0 + (1.0 - es).sqrt())
  let n = f / (2.0 - f)
  let mut np = n
  let cgb = FixedArray::make(6, 0.0)
  let cbg = FixedArray::make(6, 0.0)
  let utg = FixedArray::make(6, 0.0)
  let gtu = FixedArray::make(6, 0.0)
  cgb[0] = n *
    (
      2.0 +
      n *
      (
        -2.0 / 3.0 +
        n *
        (-2.0 + n * (116.0 / 45.0 + n * (26.0 / 45.0 + n * (-2854.0 / 675.0))))
      )
    )
  cbg[0] = n *
    (
      -2.0 +
      n *
      (
        2.0 / 3.0 +
        n *
        (
          4.0 / 3.0 +
          n * (-82.0 / 45.0 + n * (32.0 / 45.0 + n * (4642.0 / 4725.0)))
        )
      )
    )
  np = np * n
  cgb[1] = np *
    (
      7.0 / 3.0 +
      n *
      (
        -8.0 / 5.0 +
        n * (-227.0 / 45.0 + n * (2704.0 / 315.0 + n * (2323.0 / 945.0)))
      )
    )
  cbg[1] = np *
    (
      5.0 / 3.0 +
      n *
      (
        -16.0 / 15.0 +
        n * (-13.0 / 9.0 + n * (904.0 / 315.0 + n * (-1522.0 / 945.0)))
      )
    )
  np = np * n
  cgb[2] = np *
    (
      56.0 / 15.0 +
      n * (-136.0 / 35.0 + n * (-1262.0 / 105.0 + n * (73814.0 / 2835.0)))
    )
  cbg[2] = np *
    (
      -26.0 / 15.0 +
      n * (34.0 / 21.0 + n * (8.0 / 5.0 + n * (-12686.0 / 2835.0)))
    )
  np = np * n
  cgb[3] = np *
    (4279.0 / 630.0 + n * (-332.0 / 35.0 + n * (-399572.0 / 14175.0)))
  cbg[3] = np * (1237.0 / 630.0 + n * (-12.0 / 5.0 + n * (-24832.0 / 14175.0)))
  np = np * n
  cgb[4] = np * (4174.0 / 315.0 + n * (-144838.0 / 6237.0))
  cbg[4] = np * (-734.0 / 315.0 + n * (109598.0 / 31185.0))
  np = np * n
  cgb[5] = np * (601676.0 / 22275.0)
  cbg[5] = np * (444337.0 / 155925.0)
  np = @math.pow(n, 2.0)
  let qn = k0 /
    (1.0 + n) *
    (1.0 + np * (1.0 / 4.0 + np * (1.0 / 64.0 + np / 256.0)))
  utg[0] = n *
    (
      -0.5 +
      n *
      (
        2.0 / 3.0 +
        n *
        (
          -37.0 / 96.0 +
          n * (1.0 / 360.0 + n * (81.0 / 512.0 + n * (-96199.0 / 604800.0)))
        )
      )
    )
  gtu[0] = n *
    (
      0.5 +
      n *
      (
        -2.0 / 3.0 +
        n *
        (
          5.0 / 16.0 +
          n * (41.0 / 180.0 + n * (-127.0 / 288.0 + n * (7891.0 / 37800.0)))
        )
      )
    )
  utg[1] = np *
    (
      -1.0 / 48.0 +
      n *
      (
        -1.0 / 15.0 +
        n * (437.0 / 1440.0 + n * (-46.0 / 105.0 + n * (1118711.0 / 3870720.0)))
      )
    )
  gtu[1] = np *
    (
      13.0 / 48.0 +
      n *
      (
        -3.0 / 5.0 +
        n *
        (557.0 / 1440.0 + n * (281.0 / 630.0 + n * (-1983433.0 / 1935360.0)))
      )
    )
  np = np * n
  utg[2] = np *
    (
      -17.0 / 480.0 +
      n * (37.0 / 840.0 + n * (209.0 / 4480.0 + n * (-5569.0 / 90720.0)))
    )
  gtu[2] = np *
    (
      61.0 / 240.0 +
      n * (-103.0 / 140.0 + n * (15061.0 / 26880.0 + n * (167603.0 / 181440.0)))
    )
  np = np * n
  utg[3] = np *
    (-4397.0 / 161280.0 + n * (11.0 / 504.0 + n * (830251.0 / 7257600.0)))
  gtu[3] = np *
    (49561.0 / 161280.0 + n * (-179.0 / 168.0 + n * (6601661.0 / 7257600.0)))
  np = np * n
  utg[4] = np * (-4583.0 / 161280.0 + n * (108847.0 / 3991680.0))
  gtu[4] = np * (34729.0 / 80640.0 + n * (-3418889.0 / 1995840.0))
  np = np * n
  utg[5] = np * (-20648693.0 / 638668800.0)
  gtu[5] = np * (212378941.0 / 319334400.0)
  let z = gatg(cbg, lat0)
  let zb = -qn * (z + clens(gtu, 2.0 * z))
  { a: e.a, long0, x0, y0, qn, zb, cgb, cbg, utg, gtu, }
}

///|
/// Longitude and latitude in radians to easting and northing; None beyond the
/// series' reach.
fn Etmerc::forward(
  self : Etmerc,
  lon : Double,
  lat : Double,
) -> (Double, Double)? {
  let ce = adjust_lon(lon - self.long0)
  let cn = gatg(self.cbg, lat)
  let sin_cn = @math.sin(cn)
  let cos_cn = @math.cos(cn)
  let sin_ce = @math.sin(ce)
  let cos_ce = @math.cos(ce)
  let cn = @math.atan2(sin_cn, cos_ce * cos_cn)
  let ce = @math.atan2(sin_ce * cos_cn, hypot(sin_cn, cos_cn * cos_ce))
  let ce = asinhy(@math.tan(ce))
  let (tr, ti) = clens_cmplx(self.gtu, 2.0 * cn, 2.0 * ce)
  let cn = cn + tr
  let ce = ce + ti
  if ce.abs() <= 2.623395162778 {
    Some(
      (
        self.a * (self.qn * ce) + self.x0,
        self.a * (self.qn * cn + self.zb) + self.y0,
      ),
    )
  } else {
    None
  }
}

///|
/// Easting and northing to longitude and latitude in radians.
fn Etmerc::inverse(self : Etmerc, x : Double, y : Double) -> (Double, Double)? {
  let ce = (x - self.x0) * (1.0 / self.a)
  let cn = (y - self.y0) * (1.0 / self.a)
  let cn = (cn - self.zb) / self.qn
  let ce = ce / self.qn
  if ce.abs() > 2.623395162778 {
    return None
  }
  let (tr, ti) = clens_cmplx(self.utg, 2.0 * cn, 2.0 * ce)
  let cn = cn + tr
  let ce = @math.atan(sinh(ce + ti))
  let sin_cn = @math.sin(cn)
  let cos_cn = @math.cos(cn)
  let sin_ce = @math.sin(ce)
  let cos_ce = @math.cos(ce)
  let cn = @math.atan2(sin_cn * cos_ce, hypot(sin_ce, cos_ce * cos_cn))
  let ce = @math.atan2(sin_ce, cos_ce * cos_cn)
  Some((adjust_lon(ce + self.long0), gatg(self.cgb, cn)))
}
