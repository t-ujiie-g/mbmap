// Port of GeographicLib's geographiclib-geodesic 2.2.0 (src/Math.js), MIT
// License, Copyright (c) Charles Karney (2011-2022). See NOTICE.

///|
/// The trigonometry geodesics use (`@core.Trig`): a wasm build passes the
/// host's `Math` to match the JavaScript library bit for bit.
pub using @core {type Trig}

///|
const DEGREE : Double = 0.017453292519943295

///|
let nan : Double = @double.not_a_number

///|
fn sq(x : Double) -> Double {
  x * x
}

///|
/// GeographicLib's `hypot` (not `Math.hypot`, which differs in the last bit).
fn hypot(x : Double, y : Double) -> Double {
  (x * x + y * y).sqrt()
}

///|
/// `Math.max` and `Math.min`: NaN wins, and +0 is above -0.
fn jmax(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    nan
  } else if a > b || (a == b && !signbit(a)) {
    a
  } else {
    b
  }
}

///|
fn jmin(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    nan
  } else if a < b || (a == b && signbit(a)) {
    a
  } else {
    b
  }
}

///|
fn signbit(x : Double) -> Bool {
  x.reinterpret_as_int64() < 0L
}

///|
/// `Math.round`: halves go up, and a zero result keeps the sign of `x`.
fn jround(x : Double) -> Double {
  let f = x.floor()
  let r = if x - f >= 0.5 { f + 1.0 } else { f }
  if r == 0.0 && signbit(x) {
    -0.0
  } else {
    r
  }
}

///|
/// The magnitude of `x` with the sign of `y` (a NaN `y` counts as positive).
fn copysign(x : Double, y : Double) -> Double {
  if y < 0.0 || (y == 0.0 && signbit(y)) {
    -x.abs()
  } else {
    x.abs()
  }
}

///|
/// The error-free sum: `s` = round(u + v) and `t` = u + v - s.
fn sum(u : Double, v : Double) -> (Double, Double) {
  let s = u + v
  let up = s - v
  let vpp = s - up
  let t = if s == 0.0 || s.is_nan() { s } else { 0.0 - (up - u + (vpp - v)) }
  (s, t)
}

///|
/// The polynomial of degree `n` whose coefficients start at `p[s]`, leading first.
fn polyval(n : Int32, p : FixedArray[Double], s : Int32, x : Double) -> Double {
  if n < 0 {
    return 0.0
  }
  let mut y = p[s]
  for i in 1..<=n {
    y = y * x + p[s + i]
  }
  y
}

///|
/// Coarsens angles close to zero to steps of 2^-57 degrees.
fn ang_round(x : Double) -> Double {
  let z = 1.0 / 16.0
  let y = x.abs()
  let y = if y < z { z - (z - y) } else { y }
  copysign(y, x)
}

///|
/// `x` modulo `y`, in [-y/2, y/2].
fn remainder(x : Double, y : Double) -> Double {
  let x = x % y
  if x < -y / 2.0 {
    x + y
  } else if x < y / 2.0 {
    x
  } else {
    x - y
  }
}

///|
/// An angle in degrees reduced to [-180, 180].
fn ang_normalize(x : Double) -> Double {
  let y = remainder(x, 360.0)
  if y.abs() == 180.0 {
    copysign(180.0, x)
  } else {
    y
  }
}

///|
fn lat_fix(x : Double) -> Double {
  if x.abs() > 90.0 {
    nan
  } else {
    x
  }
}

///|
/// y - x reduced to [-180, 180] exactly, as `d` + `e`.
fn ang_diff(x : Double, y : Double) -> (Double, Double) {
  let (s, t) = sum(remainder(-x, 360.0), remainder(y, 360.0))
  let (d, e) = sum(remainder(s, 360.0), t)
  let d = if d == 0.0 || d.abs() == 180.0 {
    copysign(d, if e == 0.0 { y - x } else { -e })
  } else {
    d
  }
  (d, e)
}

///|
/// sin and cos of `x` + `t` degrees, reduced to [-45, 45] exactly first.
fn sincosde(
  trig : Trig,
  x : Double,
  t : Double,
  round : Bool,
) -> (Double, Double) {
  let d = x % 360.0
  let q = jround(d / 90.0)
  let d = if round { ang_round(d - 90.0 * q + t) } else { d - 90.0 * q }
  let r = d * DEGREE
  let (s, c) = if d.abs() == 45.0 {
    let c = 0.5.sqrt()
    (copysign(c, r), c)
  } else if d.abs() == 30.0 {
    (copysign(0.5, r), 0.75.sqrt())
  } else {
    (trig.sin(r), trig.cos(r))
  }
  let (sinx, cosx) = match q.to_int() & 3 {
    0 => (s, c)
    1 => (c, -s)
    2 => (-s, -c)
    _ => (-c, s)
  }
  let sinx = if sinx == 0.0 {
    copysign(sinx, if round { x + t } else { x })
  } else {
    sinx
  }
  (sinx, cosx + 0.0)
}

///|
fn sincosd(trig : Trig, x : Double) -> (Double, Double) {
  sincosde(trig, x, 0.0, false)
}

///|
/// atan2 in degrees, in [-180, 180].
fn atan2d(trig : Trig, y : Double, x : Double) -> Double {
  let (y, x, q) = if y.abs() > x.abs() { (x, y, 2) } else { (y, x, 0) }
  let (x, q) = if copysign(1.0, x) < 0.0 { (-x, q + 1) } else { (x, q) }
  let ang = trig.atan2(y, x) / DEGREE
  match q {
    1 => copysign(180.0, y) - ang
    2 => 90.0 - ang
    3 => -90.0 + ang
    _ => ang
  }
}

///|
/// GeographicLib's `Accumulator`: a sum held to twice the precision.
priv struct Accumulator {
  mut s : Double
  mut t : Double
}

///|
fn Accumulator::new(y : Double) -> Accumulator {
  { s: y, t: 0.0, }
}

///|
fn Accumulator::copy(self : Accumulator) -> Accumulator {
  { s: self.s, t: self.t, }
}

///|
fn Accumulator::add(self : Accumulator, y : Double) -> Unit {
  let (us, ut) = sum(y, self.t)
  let (vs, vt) = sum(us, self.s)
  self.s = vs
  self.t = vt
  if self.s == 0.0 {
    self.s = ut
  } else {
    self.t += ut
  }
}

///|
/// The sum plus `y` (a zero or NaN `y` is left out, as the library does).
fn Accumulator::sum(self : Accumulator, y : Double) -> Double {
  if y == 0.0 || y.is_nan() {
    self.s
  } else {
    let b = self.copy()
    b.add(y)
    b.s
  }
}

///|
fn Accumulator::negate(self : Accumulator) -> Unit {
  self.s *= -1.0
  self.t *= -1.0
}

///|
fn Accumulator::remainder(self : Accumulator, y : Double) -> Unit {
  self.s = remainder(self.s, y)
  self.add(0.0)
}
