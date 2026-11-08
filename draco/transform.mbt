// Ported from Draco 1.5.7 (compression/attributes/normal_compression_utils.h and the prediction
// scheme transforms prediction_scheme_wrap_*.h, prediction_scheme_normal_octahedron_*.h): Apache
// License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
const TRANSFORM_WRAP = 1

///|
const TRANSFORM_OCTAHEDRON = 2

///|
const TRANSFORM_CANONICALIZED = 3

///|
fn abs32(x : Int32) -> Int32 {
  if x < 0 {
    -x
  } else {
    x
  }
}

///|
/// `OctahedronToolBox`; its fields stay at -1 until `set_bits` succeeds.
priv struct Toolbox {
  mut bits : Int32
  mut max_quantized : Int32
  mut max_value : Int32
  mut scale : Float
  mut center : Int32
}

///|
fn Toolbox::new() -> Toolbox {
  { bits: -1, max_quantized: -1, max_value: -1, scale: 1.0, center: -1, }
}

///|
fn Toolbox::set_bits(self : Toolbox, q : Int32) -> Bool {
  guard q >= 2 && q <= 30 else { return false }
  self.bits = q
  self.max_quantized = (1 << q) - 1
  self.max_value = self.max_quantized - 1
  self.scale = (2.0 : Float) / Float::from_int(self.max_value)
  self.center = self.max_value / 2
  true
}

///|
/// `CanonicalizeOctahedralCoords` into `out[0, 2)`.
fn Toolbox::canonicalize_coords(
  self : Toolbox,
  s0 : Int32,
  t0 : Int32,
  out : FixedArray[Int32],
) -> Unit {
  let mut s = s0
  let mut t = t0
  let max = self.max_value
  let center = self.center
  if (s == 0 && t == 0) || (s == 0 && t == max) || (s == max && t == 0) {
    s = max
    t = max
  } else if s == 0 && t > center {
    t = center - (t - center)
  } else if s == max && t < center {
    t = center + (center - t)
  } else if t == max && s < center {
    s = center + (center - s)
  } else if t == 0 && s > center {
    s = center - (s - center)
  }
  out[0] = s
  out[1] = t
}

///|
/// `IntegerVectorToQuantizedOctahedralCoords`.
fn Toolbox::vector_to_coords(
  self : Toolbox,
  v : FixedArray[Int32],
  out : FixedArray[Int32],
) -> Unit {
  let (s, t) = if v[0] >= 0 {
    (v[1] + self.center, v[2] + self.center)
  } else {
    (
      if v[1] < 0 {
        abs32(v[2])
      } else {
        self.max_value - abs32(v[2])
      },
      if v[2] < 0 {
        abs32(v[1])
      } else {
        self.max_value - abs32(v[1])
      },
    )
  }
  self.canonicalize_coords(s, t, out)
}

///|
/// `CanonicalizeIntegerVector`.
fn Toolbox::canonicalize_vector(self : Toolbox, v : FixedArray[Int32]) -> Unit {
  let abs_sum = abs32(v[0]).to_int64() +
    abs32(v[1]).to_int64() +
    abs32(v[2]).to_int64()
  if abs_sum == 0L {
    v[0] = self.center
  } else {
    let center = self.center.to_int64()
    v[0] = (v[0].to_int64() * center / abs_sum).to_int()
    v[1] = (v[1].to_int64() * center / abs_sum).to_int()
    let rest = self.center - abs32(v[0]) - abs32(v[1])
    v[2] = if v[2] >= 0 { rest } else { -rest }
  }
}

///|
/// `QuantizedOctahedralCoordsToUnitVector` into `out[at, at + 3)`.
fn Toolbox::unit_vector(
  self : Toolbox,
  s : Int32,
  t : Int32,
  out : FixedArray[Float],
) -> Unit {
  let mut y = Float::from_int(s) * self.scale - 1.0
  let mut z = Float::from_int(t) * self.scale - 1.0
  let x = (1.0 : Float) - y.abs() - z.abs()
  let mut x_offset = -x
  x_offset = if x_offset < 0.0 { 0.0 } else { x_offset }
  y = y + (if y < 0.0 { x_offset } else { -x_offset })
  z = z + (if z < 0.0 { x_offset } else { -x_offset })
  let norm_squared = x * x + y * y + z * z
  if norm_squared.to_double() < 1.0e-6 {
    out[0] = 0.0
    out[1] = 0.0
    out[2] = 0.0
  } else {
    let d = (1.0 : Float) / norm_squared.sqrt()
    out[0] = x * d
    out[1] = y * d
    out[2] = z * d
  }
}

///|
fn Toolbox::in_diamond(self : Toolbox, s : Int32, t : Int32) -> Bool {
  !ult(self.center, abs32(s) + abs32(t))
}

///|
/// `InvertDiamond` of `v[at, at + 2)`.
fn Toolbox::invert_diamond(
  self : Toolbox,
  v : FixedArray[Int32],
  at : Int32,
) -> Unit {
  let s = v[at]
  let t = v[at + 1]
  let (sign_s, sign_t) = if s >= 0 && t >= 0 {
    (1, 1)
  } else if s <= 0 && t <= 0 {
    (-1, -1)
  } else {
    (if s > 0 { 1 } else { -1 }, if t > 0 { 1 } else { -1 })
  }
  let corner_s = sign_s * self.center
  let corner_t = sign_t * self.center
  let mut us = s + s - corner_s
  let mut ut = t + t - corner_t
  if sign_s * sign_t >= 0 {
    let temp = us
    us = -ut
    ut = -temp
  } else {
    let temp = us
    us = ut
    ut = temp
  }
  us = us + corner_s
  ut = ut + corner_t
  v[at] = us / 2
  v[at + 1] = ut / 2
}

///|
fn Toolbox::mod_max(self : Toolbox, x : Int32) -> Int32 {
  if x > self.center {
    x - self.max_quantized
  } else if x < -self.center {
    x + self.max_quantized
  } else {
    x
  }
}

///|
/// A prediction scheme's decoding transform: `TRANSFORM_WRAP`, `TRANSFORM_OCTAHEDRON` or
/// `TRANSFORM_CANONICALIZED`.
priv struct Transform {
  kind : Int32
  mut num_components : Int32
  mut min_value : Int32
  mut max_value : Int32
  mut max_dif : Int32
  mut clamped : FixedArray[Int32]
  tb : Toolbox
  point : FixedArray[Int32]
}

///|
fn Transform::new(kind : Int32) -> Transform {
  {
    kind,
    num_components: 0,
    min_value: 0,
    max_value: 0,
    max_dif: 0,
    clamped: [],
    tb: Toolbox::new(),
    point: FixedArray::make(4, 0),
  }
}

///|
fn Transform::init(self : Transform, num_components : Int32) -> Unit {
  if self.kind == TRANSFORM_WRAP {
    self.num_components = num_components
    self.clamped = FixedArray::make(num_components, 0)
  }
}

///|
fn Transform::corrections_positive(self : Transform) -> Bool {
  self.kind != TRANSFORM_WRAP
}

///|
/// `quantization_bits()`: the wrap transform has none (-1).
fn Transform::bits(self : Transform) -> Int32 {
  if self.kind == TRANSFORM_WRAP {
    -1
  } else {
    self.tb.bits
  }
}

///|
/// `set_max_quantized_value`.
fn Transform::set_max_quantized(self : Transform, v : Int32) -> Bool {
  guard v % 2 != 0 else { return false }
  self.tb.set_bits(32 - v.clz())
}

///|
fn Transform::decode_data(self : Transform, b : Buffer) -> Bool {
  match self.kind {
    TRANSFORM_WRAP => {
      let min = b.u32()
      guard !b.failed else { return false }
      let max = b.u32()
      guard !b.failed else { return false }
      guard min <= max else { return false }
      self.min_value = min
      self.max_value = max
      let dif = max.to_int64() - min.to_int64()
      guard dif >= 0L && dif < 0x7fffffffL else { return false }
      self.max_dif = 1 + dif.to_int()
      true
    }
    TRANSFORM_OCTAHEDRON => {
      let max_quantized = b.u32()
      guard !b.failed else { return false }
      if b.version < bitstream(2, 2) {
        let _ = b.u32()
        guard !b.failed else { return false }
      }
      self.set_max_quantized(max_quantized)
    }
    _ => {
      let max_quantized = b.u32()
      guard !b.failed else { return false }
      let _ = b.u32()
      guard !b.failed else { return false }
      self.set_max_quantized(max_quantized)
    }
  }
}

///|
/// `ComputeOriginalValue(pred + p, corr + c, out + o)`; the predictions are read before any
/// output is written, so the three may overlap.
fn Transform::compute(
  self : Transform,
  pred : FixedArray[Int32],
  p : Int32,
  corr : FixedArray[Int32],
  c : Int32,
  out : FixedArray[Int32],
  o : Int32,
) -> Unit {
  if self.kind == TRANSFORM_WRAP {
    let n = self.num_components
    for i in 0..<n {
      let v = pred[p + i]
      self.clamped[i] = if v > self.max_value {
        self.max_value
      } else if v < self.min_value {
        self.min_value
      } else {
        v
      }
    }
    for i in 0..<n {
      let mut v = self.clamped[i] + corr[c + i]
      if v > self.max_value {
        v = v - self.max_dif
      } else if v < self.min_value {
        v = v + self.max_dif
      }
      out[o + i] = v
    }
    return
  }
  let tb = self.tb
  let q = self.point
  q[0] = pred[p] - tb.center
  q[1] = pred[p + 1] - tb.center
  q[2] = corr[c]
  q[3] = corr[c + 1]
  let in_diamond = tb.in_diamond(q[0], q[1])
  if !in_diamond {
    tb.invert_diamond(q, 0)
  }
  if self.kind == TRANSFORM_OCTAHEDRON {
    q[0] = tb.mod_max(q[0] + q[2])
    q[1] = tb.mod_max(q[1] + q[3])
  } else {
    let x = q[0]
    let y = q[1]
    let bottom_left = (x == 0 && y == 0) || (x < 0 && y <= 0)
    let rotation = if x == 0 {
      if y == 0 {
        0
      } else if y > 0 {
        3
      } else {
        1
      }
    } else if x > 0 {
      if y >= 0 {
        2
      } else {
        1
      }
    } else if y <= 0 {
      0
    } else {
      3
    }
    if !bottom_left {
      rotate(q, rotation)
    }
    q[0] = tb.mod_max(q[0] + q[2])
    q[1] = tb.mod_max(q[1] + q[3])
    if !bottom_left {
      rotate(q, (4 - rotation) % 4)
    }
  }
  if !in_diamond {
    tb.invert_diamond(q, 0)
  }
  out[o] = q[0] + tb.center
  out[o + 1] = q[1] + tb.center
}

///|
/// `RotatePoint` of `q[0, 2)`.
fn rotate(q : FixedArray[Int32], count : Int32) -> Unit {
  let x = q[0]
  let y = q[1]
  match count {
    1 => {
      q[0] = y
      q[1] = -x
    }
    2 => {
      q[0] = -x
      q[1] = -y
    }
    3 => {
      q[0] = -y
      q[1] = x
    }
    _ => ()
  }
}
