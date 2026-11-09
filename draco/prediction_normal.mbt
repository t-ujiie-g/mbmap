// Ported from Draco 1.5.7 (compression/attributes/prediction_schemes/: the geometric normal
// decoder and its area predictor): Apache License 2.0, Copyright 2016 The Draco Authors. See
// NOTICE.

///|
fn Scheme::position_of_corner(
  self : Scheme,
  t : Table,
  parent : Parent,
  points : Array[Int32],
  c : Int32,
  out : FixedArray[Int64],
) -> Bool {
  let v = t.vertex(c)
  guard v >= 0 && v < self.enc.vertex_values.length() else { return false }
  let id = self.enc.vertex_values[v]
  guard id >= 0 && id < points.length() else { return false }
  parent.position(points[id], out)
}

///|
fn sat_abs_sum(a : Int64, b : Int64, c : Int64) -> Int64 {
  let mut result = 0L
  for x in [a, b, c] {
    let v = abs64(x)
    if result > 0x7fffffffffffffffL - v {
      return 0x7fffffffffffffffL
    }
    result = result + v
  }
  result
}

///|
/// `MeshPredictionSchemeGeometricNormalDecoder::ComputeOriginalValues`.
fn Scheme::geometric_normal(
  self : Scheme,
  t : Table,
  data : FixedArray[Int32],
  points : Array[Int32],
) -> Bool {
  let tb = Toolbox::new()
  let _ = tb.set_bits(self.transform.bits())
  guard self.parent is Some(parent) else { return false }
  let limit = t.face_count() * 3 + 1
  let cent = FixedArray::make(3, 0L)
  let pn = FixedArray::make(3, 0L)
  let pp = FixedArray::make(3, 0L)
  let normal3 = FixedArray::make(3, 0)
  let oct = FixedArray::make(2, 0)
  let corners = self.enc.corners
  for data_id in 0..<corners.length() {
    let corner = corners[data_id]
    guard self.position_of_corner(t, parent, points, corner, cent) else {
      return false
    }
    let mut n0 = 0L
    let mut n1 = 0L
    let mut n2 = 0L
    let mut c = corner
    let mut left = true
    let mut steps = 0
    while c >= 0 {
      let (c_next, c_prev) = if self.normal_mode == 0 {
        (next(corner), previous(corner))
      } else {
        (next(c), previous(c))
      }
      guard self.position_of_corner(t, parent, points, c_next, pn) &&
        self.position_of_corner(t, parent, points, c_prev, pp) else {
        return false
      }
      let dn0 = pn[0] - cent[0]
      let dn1 = pn[1] - cent[1]
      let dn2 = pn[2] - cent[2]
      let dp0 = pp[0] - cent[0]
      let dp1 = pp[1] - cent[1]
      let dp2 = pp[2] - cent[2]
      n0 = n0 + (dn1 * dp2 - dn2 * dp1)
      n1 = n1 + (dn2 * dp0 - dn0 * dp2)
      n2 = n2 + (dn0 * dp1 - dn1 * dp0)
      if left {
        c = t.swing_left(c)
        if c < 0 {
          c = t.swing_right(corner)
          left = false
        } else if c == corner {
          c = -1
        }
      } else {
        c = t.swing_right(c)
      }
      steps += 1
      guard steps <= limit else { return false }
    }
    let upper_bound = 0x20000000L
    let abs_sum = if self.normal_mode == 0 {
      sat_abs_sum(n0, n1, n2).to_int().to_int64()
    } else {
      sat_abs_sum(n0, n1, n2)
    }
    if abs_sum > upper_bound {
      let quotient = abs_sum / upper_bound
      n0 = n0 / quotient
      n1 = n1 / quotient
      n2 = n2 / quotient
    }
    normal3[0] = n0.to_int()
    normal3[1] = n1.to_int()
    normal3[2] = n2.to_int()
    tb.canonicalize_vector(normal3)
    if self.flip.bit() {
      normal3[0] = -normal3[0]
      normal3[1] = -normal3[1]
      normal3[2] = -normal3[2]
    }
    tb.vector_to_coords(normal3, oct)
    guard data_id * 2 + 2 <= data.length() else { return false }
    self.transform.compute(oct, 0, data, data_id * 2, data, data_id * 2)
  }
  true
}
