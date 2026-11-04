// Port of GeographicLib's geographiclib-geodesic 2.2.0 (src/Geodesic.js), MIT
// License, Copyright (c) Charles Karney (2011-2022). See NOTICE.

///|
let a1m1f_coeff : FixedArray[Double] = [1, 4, 64, 0, 256]

///|
let c1f_coeff : FixedArray[Double] = [
  -1, 6, -16, 32, -9, 64, -128, 2048, 9, -16, 768, 3, -5, 512, -7, 1280, -7, 2048,
]

///|
let c1pf_coeff : FixedArray[Double] = [
  205, -432, 768, 1536, 4005, -4736, 3840, 12288, -225, 116, 384, -7173, 2695, 7680,
  3467, 7680, 38081, 61440,
]

///|
let a2m1f_coeff : FixedArray[Double] = [-11, -28, -192, 0, 256]

///|
let c2f_coeff : FixedArray[Double] = [
  1, 2, 16, 32, 35, 64, 384, 2048, 15, 80, 768, 7, 35, 512, 63, 1280, 77, 2048,
]

///|
let a3_coeff : FixedArray[Double] = [
  -3, 128, -2, -3, 64, -1, -3, -1, 16, 3, -1, -2, 8, 1, -1, 2, 1, 1,
]

///|
let c3_coeff : FixedArray[Double] = [
  3, 128, 2, 5, 128, -1, 3, 3, 64, -1, 0, 1, 8, -1, 1, 4, 5, 256, 1, 3, 128, -3,
  -2, 3, 64, 1, -3, 2, 32, 7, 512, -10, 9, 384, 5, -9, 5, 192, 7, 512, -14, 7, 512,
  21, 2560,
]

///|
let c4_coeff : FixedArray[Double] = [
  97, 15015, 1088, 156, 45045, -224, -4784, 1573, 45045, -10656, 14144, -4576, -858,
  45045, 64, 624, -4576, 6864, -3003, 15015, 100, 208, 572, 3432, -12012, 30030,
  45045, 1, 9009, -2944, 468, 135135, 5792, 1040, -1287, 135135, 5952, -11648, 9152,
  -2574, 135135, -64, -624, 4576, -6864, 3003, 135135, 8, 10725, 1856, -936, 225225,
  -8448, 4992, -1144, 225225, -1440, 4160, -4576, 1716, 225225, -136, 63063, 1024,
  -208, 105105, 3584, -3328, 1144, 315315, -128, 135135, -2560, 832, 405405, 128,
  99099,
]

///|
/// Evaluates sum(c[i] sin(2ix), i = 1..n) (`sinp`) or sum(c[i] cos((2i+1)x),
/// i = 0..n-1) by Clenshaw summation; c[0] is unused for the sine series.
fn sin_cos_series(
  sinp : Bool,
  sinx : Double,
  cosx : Double,
  c : FixedArray[Double],
) -> Double {
  let mut k = c.length()
  let n = k - (if sinp { 1 } else { 0 })
  let ar = 2.0 * (cosx - sinx) * (cosx + sinx)
  let mut y0 = 0.0
  if (n & 1) != 0 {
    k -= 1
    y0 = c[k]
  }
  let mut y1 = 0.0
  for _ in 0..<(n / 2) {
    k -= 1
    y1 = ar * y0 - y1 + c[k]
    k -= 1
    y0 = ar * y1 - y0 + c[k]
  }
  if sinp {
    2.0 * sinx * cosx * y0
  } else {
    cosx * (y0 - y1)
  }
}

///|
fn a1m1f(eps : Double) -> Double {
  let p = ORDER / 2
  let t = polyval(p, a1m1f_coeff, 0, sq(eps)) / a1m1f_coeff[p + 1]
  (t + eps) / (1.0 - eps)
}

///|
fn a2m1f(eps : Double) -> Double {
  let p = ORDER / 2
  let t = polyval(p, a2m1f_coeff, 0, sq(eps)) / a2m1f_coeff[p + 1]
  (t - eps) / (1.0 + eps)
}

///|
/// The Fourier coefficients c[1..ORDER] of B1 (`c1f_coeff`), B1p or B2.
fn fourier(
  coeff : FixedArray[Double],
  eps : Double,
  c : FixedArray[Double],
) -> Unit {
  let eps2 = sq(eps)
  let mut d = eps
  let mut o = 0
  for l in 1..<=ORDER {
    let p = (ORDER - l) / 2
    c[l] = d * polyval(p, coeff, o, eps2) / coeff[o + p + 1]
    o += p + 2
    d *= eps
  }
}

///|
fn Geodesic::a3f(self : Geodesic, eps : Double) -> Double {
  polyval(ORDER - 1, self.a3x, 0, eps)
}

///|
fn Geodesic::c3f(self : Geodesic, eps : Double, c : FixedArray[Double]) -> Unit {
  let mut mult = 1.0
  let mut o = 0
  for l in 1..<ORDER {
    let p = ORDER - l - 1
    mult *= eps
    c[l] = mult * polyval(p, self.c3x, o, eps)
    o += p + 1
  }
}

///|
fn Geodesic::c4f(self : Geodesic, eps : Double, c : FixedArray[Double]) -> Unit {
  let mut mult = 1.0
  let mut o = 0
  for l in 0..<ORDER {
    let p = ORDER - l - 1
    c[l] = mult * polyval(p, self.c4x, o, eps)
    o += p + 1
    mult *= eps
  }
}
