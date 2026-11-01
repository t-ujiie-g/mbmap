// Follows proj4js 2.22.0's lib/common/ helpers and lib/constants/values.js,
// MIT License, Copyright (c) 2014, Mike Adair, Richard Greenwood, Didier
// Richard, Stephen Irons, Olivier Terral, Calvin Metcalf. See NOTICE.

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
fn sinh(m : Trig, x : Double) -> Double {
  let r = m.exp(x)
  (r - 1.0 / r) / 2.0
}

///|
fn cosh(m : Trig, x : Double) -> Double {
  let r = m.exp(x)
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
fn log1py(m : Trig, x : Double) -> Double {
  let y = 1.0 + x
  let z = y - 1.0
  if z == 0.0 {
    x
  } else {
    x * m.ln(y) / z
  }
}

///|
fn asinhy(m : Trig, x : Double) -> Double {
  let y = x.abs()
  let y = log1py(m, y * (1.0 + y / (hypot(1.0, y) + 1.0)))
  if x < 0.0 {
    -y
  } else {
    y
  }
}

///|
/// Gaussian to geodetic latitude and back (`gatg`), by Clenshaw summation.
fn gatg(m : Trig, pp : FixedArray[Double], b : Double) -> Double {
  let cos_2b = 2.0 * m.cos(2.0 * b)
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
  b + h * m.sin(2.0 * b)
}

///|
fn clens(m : Trig, pp : FixedArray[Double], arg_r : Double) -> Double {
  let r = 2.0 * m.cos(arg_r)
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
  m.sin(arg_r) * hr
}

///|
fn clens_cmplx(
  m : Trig,
  pp : FixedArray[Double],
  arg_r : Double,
  arg_i : Double,
) -> (Double, Double) {
  let sin_arg_r = m.sin(arg_r)
  let cos_arg_r = m.cos(arg_r)
  let sinh_arg_i = sinh(m, arg_i)
  let cosh_arg_i = cosh(m, arg_i)
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
/// What a projection gives for a point beyond its reach.
let nan2 : (Double, Double) = (@double.not_a_number, @double.not_a_number)

///|
const HALF_PI : Double = 1.5707963267948966

///|
const FORTPI : Double = 0.7853981633974483

///|
const EPSLN : Double = 1.0e-10

///|
fn sign(x : Double) -> Double {
  if x < 0.0 {
    -1.0
  } else {
    1.0
  }
}

///|
fn adjust_lat(x : Double) -> Double {
  if x.abs() < HALF_PI {
    x
  } else {
    x - sign(x) * PI
  }
}

///|
/// JavaScript's `x || d` for a parameter: `d` when `x` is missing (NaN) or 0.
fn or(x : Double, d : Double) -> Double {
  if x.is_nan() || x == 0.0 {
    d
  } else {
    x
  }
}

///|
fn asinz(m : Trig, x : Double) -> Double {
  m.asin(if x.abs() > 1.0 { sign(x) } else { x })
}

///|
fn msfnz(e : Double, sinphi : Double, cosphi : Double) -> Double {
  let con = e * sinphi
  cosphi / (1.0 - con * con).sqrt()
}

///|
fn tsfnz(m : Trig, e : Double, phi : Double, sinphi : Double) -> Double {
  let con = e * sinphi
  let con = m.pow((1.0 - con) / (1.0 + con), 0.5 * e)
  m.tan(0.5 * (HALF_PI - phi)) / con
}

///|
/// The latitude of isometric `ts`; NaN if the iteration does not settle
/// (proj4js's -9999).
fn phi2z(m : Trig, e : Double, ts : Double) -> Double {
  let eccnth = 0.5 * e
  let mut phi = HALF_PI - 2.0 * m.atan(ts)
  for _ in 0..<=15 {
    let con = e * m.sin(phi)
    let dphi = HALF_PI -
      2.0 * m.atan(ts * m.pow((1.0 - con) / (1.0 + con), eccnth)) -
      phi
    phi += dphi
    if dphi.abs() <= 0.0000000001 {
      return phi
    }
  }
  @double.not_a_number
}

///|
fn qsfnz(m : Trig, e : Double, sinphi : Double) -> Double {
  if e > 1.0e-7 {
    let con = e * sinphi
    (1.0 - e * e) *
    (sinphi / (1.0 - con * con) - 0.5 / e * m.ln((1.0 - con) / (1.0 + con)))
  } else {
    2.0 * sinphi
  }
}

///|
fn iqsfnz(m : Trig, e : Double, q : Double) -> Double {
  let temp = 1.0 - (1.0 - e * e) / (2.0 * e) * m.ln((1.0 - e) / (1.0 + e))
  if (q.abs() - temp).abs() < 1.0e-6 {
    return if q < 0.0 { -HALF_PI } else { HALF_PI }
  }
  let mut phi = m.asin(0.5 * q)
  for _ in 0..<30 {
    let sin_phi = m.sin(phi)
    let cos_phi = m.cos(phi)
    let con = e * sin_phi
    let dphi = m.pow(1.0 - con * con, 2.0) /
      (2.0 * cos_phi) *
      (
        q / (1.0 - e * e) -
        sin_phi / (1.0 - con * con) +
        0.5 / e * m.ln((1.0 - con) / (1.0 + con))
      )
    phi += dphi
    if dphi.abs() <= 0.0000000001 {
      return phi
    }
  }
  @double.not_a_number
}

///|
/// The meridian distance series' coefficients e0-e3 (`e0fn`-`e3fn`).
fn mlfn_coefficients(es : Double) -> (Double, Double, Double, Double) {
  (
    1.0 - 0.25 * es * (1.0 + es / 16.0 * (3.0 + 1.25 * es)),
    0.375 * es * (1.0 + 0.25 * es * (1.0 + 0.46875 * es)),
    0.05859375 * es * es * (1.0 + 0.75 * es),
    es * es * es * (35.0 / 3072.0),
  )
}

///|
fn mlfn(m : Trig, e : (Double, Double, Double, Double), phi : Double) -> Double {
  let (e0, e1, e2, e3) = e
  e0 * phi -
  e1 * m.sin(2.0 * phi) +
  e2 * m.sin(4.0 * phi) -
  e3 * m.sin(6.0 * phi)
}

///|
fn imlfn(m : Trig, ml : Double, e : (Double, Double, Double, Double)) -> Double {
  let (e0, e1, e2, e3) = e
  let mut phi = ml / e0
  for _ in 0..<15 {
    let dphi = (
        ml -
        (
          e0 * phi -
          e1 * m.sin(2.0 * phi) +
          e2 * m.sin(4.0 * phi) -
          e3 * m.sin(6.0 * phi)
        )
      ) /
      (
        e0 -
        2.0 * e1 * m.cos(2.0 * phi) +
        4.0 * e2 * m.cos(4.0 * phi) -
        6.0 * e3 * m.cos(6.0 * phi)
      )
    phi += dphi
    if dphi.abs() <= 0.0000000001 {
      return phi
    }
  }
  @double.not_a_number
}

///|
fn g_n(a : Double, e : Double, sinphi : Double) -> Double {
  let temp = e * sinphi
  a / (1.0 - temp * temp).sqrt()
}

///|
fn srat(m : Trig, esinp : Double, exp : Double) -> Double {
  m.pow((1.0 - esinp) / (1.0 + esinp), exp)
}

///|
fn pj_enfn(es : Double) -> FixedArray[Double] {
  let en = FixedArray::make(5, 0.0)
  en[0] = 1.0 -
    es * (0.25 + es * (0.046875 + es * (0.01953125 + es * 0.01068115234375)))
  en[1] = es *
    (0.75 - es * (0.046875 + es * (0.01953125 + es * 0.01068115234375)))
  let t = es * es
  en[2] = t *
    (0.46875 - es * (0.01302083333333333333 + es * 0.00712076822916666666))
  let t = t * es
  en[3] = t * (0.36458333333333333333 - es * 0.00569661458333333333)
  en[4] = t * es * 0.3076171875
  en
}

///|
fn pj_mlfn(
  phi : Double,
  sphi : Double,
  cphi : Double,
  en : FixedArray[Double],
) -> Double {
  let cphi = cphi * sphi
  let sphi = sphi * sphi
  en[0] * phi - cphi * (en[1] + sphi * (en[2] + sphi * (en[3] + sphi * en[4])))
}

///|
fn pj_inv_mlfn(
  m : Trig,
  arg : Double,
  es : Double,
  en : FixedArray[Double],
) -> Double {
  let k = 1.0 / (1.0 - es)
  let mut phi = arg
  for _ in 0..<20 {
    let s = m.sin(phi)
    let t = 1.0 - es * s * s
    let t = (pj_mlfn(phi, s, m.cos(phi), en) - arg) * (t * t.sqrt()) * k
    phi -= t
    if t.abs() < EPSLN {
      return phi
    }
  }
  phi
}

///|
/// The authalic latitude series' coefficients (`authset`).
fn authset(es : Double) -> FixedArray[Double] {
  let apa = FixedArray::make(3, 0.0)
  apa[0] = es * 0.33333333333333333333
  let t = es * es
  apa[0] += t * 0.17222222222222222222
  apa[1] = t * 0.06388888888888888888
  let t = t * es
  apa[0] += t * 0.10257936507936507936
  apa[1] += t * 0.06640211640211640211
  apa[2] = t * 0.01641501294219154443
  apa
}

///|
fn authlat(m : Trig, beta : Double, apa : FixedArray[Double]) -> Double {
  let t = beta + beta
  beta + apa[0] * m.sin(t) + apa[1] * m.sin(t + t) + apa[2] * m.sin(t + t + t)
}

///|
/// The elementary functions the projections use: MoonBit's own
/// (`Trig::moonbit`), or a host's, so that a wasm build can use JavaScript's
/// `Math` as proj4js does.
pub(all) struct Trig {
  sin : (Double) -> Double
  cos : (Double) -> Double
  tan : (Double) -> Double
  asin : (Double) -> Double
  acos : (Double) -> Double
  atan : (Double) -> Double
  atan2 : (Double, Double) -> Double
  exp : (Double) -> Double
  ln : (Double) -> Double
  pow : (Double, Double) -> Double
}

///|
pub fn Trig::moonbit() -> Trig {
  {
    sin: @math.sin,
    cos: @math.cos,
    tan: @math.tan,
    asin: @math.asin,
    acos: @math.acos,
    atan: @math.atan,
    atan2: @math.atan2,
    exp: @math.exp,
    ln: @math.ln,
    pow: @math.pow,
  }
}

///|
fn Trig::sin(self : Trig, x : Double) -> Double {
  (self.sin)(x)
}

///|
fn Trig::cos(self : Trig, x : Double) -> Double {
  (self.cos)(x)
}

///|
fn Trig::tan(self : Trig, x : Double) -> Double {
  (self.tan)(x)
}

///|
fn Trig::asin(self : Trig, x : Double) -> Double {
  (self.asin)(x)
}

///|
fn Trig::acos(self : Trig, x : Double) -> Double {
  (self.acos)(x)
}

///|
fn Trig::atan(self : Trig, x : Double) -> Double {
  (self.atan)(x)
}

///|
fn Trig::atan2(self : Trig, y : Double, x : Double) -> Double {
  (self.atan2)(y, x)
}

///|
fn Trig::exp(self : Trig, x : Double) -> Double {
  (self.exp)(x)
}

///|
fn Trig::ln(self : Trig, x : Double) -> Double {
  (self.ln)(x)
}

///|
fn Trig::pow(self : Trig, x : Double, y : Double) -> Double {
  (self.pow)(x, y)
}
