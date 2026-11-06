///|
/// A 4x4 matrix in column-major order, as WebGL takes it: row `r` of column
/// `c` is `m[c * 4 + r]`. Operations follow gl-matrix: `translate`, `scale`
/// and the rotations multiply on the right.
#derive(Debug, Eq)
pub struct Mat4 {
  m : FixedArray[Double]
}

///|
/// The identity matrix.
pub fn Mat4::identity() -> Mat4 {
  let m = FixedArray::make(16, 0.0)
  m[0] = 1.0
  m[5] = 1.0
  m[10] = 1.0
  m[15] = 1.0
  { m, }
}

///|
/// `self * other`.
pub fn Mat4::mul(self : Mat4, other : Mat4) -> Mat4 {
  let a = self.m
  let b = other.m
  let m = FixedArray::make(16, 0.0)
  for c in 0..<4 {
    for r in 0..<4 {
      let mut s = 0.0
      for k in 0..<4 {
        s += a[k * 4 + r] * b[c * 4 + k]
      }
      m[c * 4 + r] = s
    }
  }
  { m, }
}

///|
/// A perspective projection with vertical field of view `fovy` (radians), as
/// gl-matrix's `perspective` (clip z from -1 at `near` to 1 at `far`).
pub fn Mat4::perspective(
  fovy : Double,
  aspect : Double,
  near : Double,
  far : Double,
) -> Mat4 {
  let f = 1.0 / @math.tan(fovy / 2.0)
  let nf = 1.0 / (near - far)
  let m = FixedArray::make(16, 0.0)
  m[0] = f / aspect
  m[5] = f
  m[10] = (far + near) * nf
  m[11] = -1.0
  m[14] = 2.0 * far * near * nf
  { m, }
}

///|
/// This matrix with a translation applied before it.
pub fn Mat4::translate(self : Mat4, x : Double, y : Double, z : Double) -> Mat4 {
  let t = Mat4::identity()
  t.m[12] = x
  t.m[13] = y
  t.m[14] = z
  self.mul(t)
}

///|
/// This matrix with a scaling applied before it.
pub fn Mat4::scale(self : Mat4, x : Double, y : Double, z : Double) -> Mat4 {
  let s = Mat4::identity()
  s.m[0] = x
  s.m[5] = y
  s.m[10] = z
  self.mul(s)
}

///|
/// Rotation by `rad` about the x axis.
pub fn Mat4::rotate_x(self : Mat4, rad : Double) -> Mat4 {
  let (s, c) = (@math.sin(rad), @math.cos(rad))
  let r = Mat4::identity()
  r.m[5] = c
  r.m[6] = s
  r.m[9] = -s
  r.m[10] = c
  self.mul(r)
}

///|
/// Rotation by `rad` about the z axis.
pub fn Mat4::rotate_z(self : Mat4, rad : Double) -> Mat4 {
  let (s, c) = (@math.sin(rad), @math.cos(rad))
  let r = Mat4::identity()
  r.m[0] = c
  r.m[1] = s
  r.m[4] = -s
  r.m[5] = c
  self.mul(r)
}

///|
/// `self * (x, y, z, w)`.
pub fn Mat4::apply(
  self : Mat4,
  x : Double,
  y : Double,
  z : Double,
  w : Double,
) -> (Double, Double, Double, Double) {
  let m = self.m
  (
    m[0] * x + m[4] * y + m[8] * z + m[12] * w,
    m[1] * x + m[5] * y + m[9] * z + m[13] * w,
    m[2] * x + m[6] * y + m[10] * z + m[14] * w,
    m[3] * x + m[7] * y + m[11] * z + m[15] * w,
  )
}

///|
/// The inverse, or None for a singular matrix (gl-matrix's `invert`).
pub fn Mat4::invert(self : Mat4) -> Mat4? {
  let a = self.m
  let b00 = a[0] * a[5] - a[1] * a[4]
  let b01 = a[0] * a[6] - a[2] * a[4]
  let b02 = a[0] * a[7] - a[3] * a[4]
  let b03 = a[1] * a[6] - a[2] * a[5]
  let b04 = a[1] * a[7] - a[3] * a[5]
  let b05 = a[2] * a[7] - a[3] * a[6]
  let b06 = a[8] * a[13] - a[9] * a[12]
  let b07 = a[8] * a[14] - a[10] * a[12]
  let b08 = a[8] * a[15] - a[11] * a[12]
  let b09 = a[9] * a[14] - a[10] * a[13]
  let b10 = a[9] * a[15] - a[11] * a[13]
  let b11 = a[10] * a[15] - a[11] * a[14]
  let det = b00 * b11 -
    b01 * b10 +
    b02 * b09 +
    b03 * b08 -
    b04 * b07 +
    b05 * b06
  if det == 0.0 || det.is_nan() {
    return None
  }
  let d = 1.0 / det
  Some({
    m: [
      (a[5] * b11 - a[6] * b10 + a[7] * b09) * d,
      (a[2] * b10 - a[1] * b11 - a[3] * b09) * d,
      (a[13] * b05 - a[14] * b04 + a[15] * b03) * d,
      (a[10] * b04 - a[9] * b05 - a[11] * b03) * d,
      (a[6] * b08 - a[4] * b11 - a[7] * b07) * d,
      (a[0] * b11 - a[2] * b08 + a[3] * b07) * d,
      (a[14] * b02 - a[12] * b05 - a[15] * b01) * d,
      (a[8] * b05 - a[10] * b02 + a[11] * b01) * d,
      (a[4] * b10 - a[5] * b08 + a[7] * b06) * d,
      (a[1] * b08 - a[0] * b10 - a[3] * b06) * d,
      (a[12] * b04 - a[13] * b02 + a[15] * b00) * d,
      (a[9] * b02 - a[8] * b04 - a[11] * b00) * d,
      (a[5] * b07 - a[4] * b09 - a[6] * b06) * d,
      (a[0] * b09 - a[1] * b07 + a[2] * b06) * d,
      (a[13] * b01 - a[12] * b03 - a[14] * b00) * d,
      (a[8] * b03 - a[9] * b01 + a[10] * b00) * d,
    ],
  })
}
