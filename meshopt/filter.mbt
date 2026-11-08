// Ported from meshoptimizer 1.3.0 (src/vertexfilter.cpp, its Wasm SIMD filters, which the
// npm decoder runs): MIT License, Copyright (c) 2016-2026 Arseny Kapoulkine. See NOTICE.

///|
/// 3 << 22: adding it rounds a float of magnitude below 2^22 to the nearest integer
/// (ties to even), whose low bits are then the float's low mantissa bits.
let fsnap : Float = 12582912.0

///|
let sign_bit : Int32 = 0x80000000

///|
/// A NaN (0 times an infinite scale) gives 0, the low bits of every host's quiet NaN.
fn snap(v : Float) -> Int32 {
  let r = v + fsnap
  if r.is_nan() {
    0
  } else {
    r.reinterpret_as_int()
  }
}

///|
fn i8_at(data : FixedArray[Byte], i : Int32) -> Int32 {
  data[i].to_int() << 24 >> 24
}

///|
fn u16_at(data : FixedArray[Byte], i : Int32) -> Int32 {
  data[i].to_int() | (data[i + 1].to_int() << 8)
}

///|
fn i16_at(data : FixedArray[Byte], i : Int32) -> Int32 {
  u16_at(data, i) << 16 >> 16
}

///|
fn set16(data : FixedArray[Byte], i : Int32, v : Int32) -> Unit {
  data[i] = v.to_byte()
  data[i + 1] = (v >> 8).to_byte()
}

///|
/// The octahedral fixup and scale shared by both widths: `x`, `y` and `z` turned back
/// into a unit vector times `max`, each snapped (see `snap`) into `out`.
fn octahedral(
  xf : Int32,
  yf : Int32,
  zf : Int32,
  max : Float,
  out : FixedArray[Int32],
) -> Unit {
  let mut x = Float::from_int(xf)
  let mut y = Float::from_int(yf)
  let z = Float::from_int(zf) - (x.abs() + y.abs())
  // i32 min of the bits with 0: z when its sign bit is set, else +0
  let t = if z.reinterpret_as_int() < 0 { z.reinterpret_as_int() } else { 0 }
  x = x + Float::reinterpret_from_int(t ^ (x.reinterpret_as_int() & sign_bit))
  y = y + Float::reinterpret_from_int(t ^ (y.reinterpret_as_int() & sign_bit))
  let s = max / (x * x + (y * y + z * z)).sqrt()
  out[0] = snap(x * s)
  out[1] = snap(y * s)
  out[2] = snap(z * s)
}

///|
/// `decodeFilterOctSimd8` on `count` 4-byte normals (x, y, z as signed bytes; w kept).
fn filter_oct8(data : FixedArray[Byte], count : Int32) -> Unit {
  let r = FixedArray::make(3, 0)
  for i in 0..<count {
    let o = i * 4
    octahedral(i8_at(data, o), i8_at(data, o + 1), i8_at(data, o + 2), 127.0, r)
    data[o] = r[0].to_byte()
    data[o + 1] = r[1].to_byte()
    data[o + 2] = r[2].to_byte()
  }
}

///|
/// `decodeFilterOctSimd16` on `count` 8-byte normals (x, y signed, z the low 15 bits; w kept).
fn filter_oct16(data : FixedArray[Byte], count : Int32) -> Unit {
  let r = FixedArray::make(3, 0)
  for i in 0..<count {
    let o = i * 8
    octahedral(
      i16_at(data, o),
      i16_at(data, o + 2),
      u16_at(data, o + 4) & 0x7fff,
      32767.0,
      r,
    )
    set16(data, o, r[0])
    set16(data, o + 2, r[1])
    set16(data, o + 4, r[2])
  }
}

///|
/// `decodeFilterQuatSimd` on `count` 8-byte quaternions: three components and, in the
/// fourth, the scale with the dropped component's index in its low 2 bits.
fn filter_quat(data : FixedArray[Byte], count : Int32) -> Unit {
  let scale = Float::from_int(32767) / Float::sqrt(2.0)
  for i in 0..<count {
    let o = i * 8
    let cf = i16_at(data, o + 6)
    let s = Float::from_int(cf | 3)
    let x = Float::from_int(i16_at(data, o))
    let y = Float::from_int(i16_at(data, o + 2))
    let z = Float::from_int(i16_at(data, o + 4))
    let ws = s * s
    let ww = ws + ws - (x * x + (y * y + z * z))
    // i32 max of the bits with 0: negative values (and -0) become +0
    let w : Float = if ww.reinterpret_as_int() < 0 { 0.0 } else { ww.sqrt() }
    let ss = scale / s
    let qc = cf & 3
    set16(data, o + qc * 2, snap(w * ss))
    set16(data, o + ((qc + 1) & 3) * 2, snap(x * ss))
    set16(data, o + ((qc + 2) & 3) * 2, snap(y * ss))
    set16(data, o + ((qc + 3) & 3) * 2, snap(z * ss))
  }
}

///|
/// `decodeFilterExpSimd` on `count` 32-bit words: a signed 24-bit mantissa times 2 to
/// the signed top byte. A NaN result (only for exponent -128 times 0) is written as
/// 0x7fc00000, where the host's NaN may differ.
fn filter_exp(data : FixedArray[Byte], count : Int32) -> Unit {
  for i in 0..<count {
    let o = i * 4
    let v = data[o].to_int() |
      (data[o + 1].to_int() << 8) |
      (data[o + 2].to_int() << 16) |
      (data[o + 3].to_int() << 24)
    let e = Float::reinterpret_from_int(((v >> 24) + 127) << 23)
    let r = e * Float::from_int(v << 8 >> 8)
    let bits = if r.is_nan() { 0x7fc00000 } else { r.reinterpret_as_int() }
    data[o] = bits.to_byte()
    data[o + 1] = (bits >> 8).to_byte()
    data[o + 2] = (bits >> 16).to_byte()
    data[o + 3] = (bits >> 24).to_byte()
  }
}

///|
/// The YCoCg to RGB step shared by both widths: `as_` is the alpha's scale mask
/// (all bits up to its highest), `max` the full range.
fn ycocg(
  y : Int32,
  co : Int32,
  cg : Int32,
  a : Int32,
  as_ : Int32,
  max : Float,
  out : FixedArray[Int32],
) -> Unit {
  let ss = max / Float::from_int(as_)
  let alpha = ((a << 1) & as_) | (a & 1)
  out[0] = snap(Float::from_int(y + (co - cg)) * ss)
  out[1] = snap(Float::from_int(y + cg) * ss)
  out[2] = snap(Float::from_int(y - (co + cg)) * ss)
  out[3] = snap(Float::from_int(alpha) * ss)
}

///|
/// `decodeFilterColorSimd8` on `count` 4-byte colors (Y, Co, Cg, alpha with its scale bit).
fn filter_color8(data : FixedArray[Byte], count : Int32) -> Unit {
  let r = FixedArray::make(4, 0)
  for i in 0..<count {
    let o = i * 4
    let a = data[o + 3].to_int()
    let mut as_ = a | (a >> 1)
    as_ = as_ | (as_ >> 2)
    as_ = as_ | (as_ >> 4)
    ycocg(
      data[o].to_int(),
      i8_at(data, o + 1),
      i8_at(data, o + 2),
      a,
      as_,
      255.0,
      r,
    )
    for c in 0..<4 {
      data[o + c] = r[c].to_byte()
    }
  }
}

///|
/// `decodeFilterColorSimd16` on `count` 8-byte colors.
fn filter_color16(data : FixedArray[Byte], count : Int32) -> Unit {
  let r = FixedArray::make(4, 0)
  for i in 0..<count {
    let o = i * 8
    let a = u16_at(data, o + 6)
    let mut as_ = a | (a >> 1)
    as_ = as_ | (as_ >> 2)
    as_ = as_ | (as_ >> 4)
    as_ = as_ | (as_ >> 8)
    ycocg(
      u16_at(data, o),
      i16_at(data, o + 2),
      i16_at(data, o + 4),
      a,
      as_,
      65535.0,
      r,
    )
    for c in 0..<4 {
      set16(data, o + c * 2, r[c])
    }
  }
}
