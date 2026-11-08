// Ported from Esri's LEPCC (src/BitStuffer2.cpp, src/BitStuffer2.h): Apache License 2.0,
// Copyright 2016 Esri. See NOTICE.

///|
/// A read position in `data` that never passes `end`.
priv struct Cursor {
  data : FixedArray[Byte]
  mut pos : Int32
  end : Int32
}

///|
fn Cursor::has(self : Cursor, n : Int64) -> Bool {
  n >= 0L && self.pos.to_int64() + n <= self.end.to_int64()
}

///|
/// `BitStuffer2::DecodeUInt`: a little-endian unsigned of `size` bytes (1, 2 or 4).
fn Cursor::uint(self : Cursor, size : Int32) -> UInt32? {
  guard (size == 1 || size == 2 || size == 4) && self.has(size.to_int64()) else {
    return None
  }
  let p = self.pos
  self.pos += size
  match size {
    1 => Some(self.data[p].to_uint())
    2 => Some(u16_at(self.data, p).reinterpret_as_uint())
    _ => Some(u32_at(self.data, p))
  }
}

///|
fn bit_count(v : UInt32) -> Int32 {
  let mut n = 0
  while n < 32 && v >> n != 0 {
    n += 1
  }
  n
}

///|
/// `BitStuffer2::NumTailBytesNotNeeded`.
fn tail_bytes_not_needed(count : Int32, bits : Int32) -> Int32 {
  let tail = (count * bits) & 31
  let bytes = (tail + 7) >> 3
  if bytes > 0 {
    4 - bytes
  } else {
    0
  }
}

///|
/// `BitStuffer2::BitUnStuff`: `count` values of `bits` bits (1 to 31), packed from the low bits of
/// little-endian u32s whose unused tail bytes are left out. None where the C++ would index an
/// empty buffer (no values) or read past the cursor's end.
fn Cursor::unstuff(
  self : Cursor,
  count : Int32,
  bits : Int32,
) -> FixedArray[UInt32]? {
  guard count > 0 && count <= MAX_POINTS && bits > 0 && bits < 32 else {
    return None
  }
  let num_uints = (count * bits + 31) / 32
  let used = num_uints * 4 - tail_bytes_not_needed(count, bits)
  guard self.has(used.to_int64()) else { return None }
  let words = FixedArray::make(num_uints, 0U)
  for i in 0..<num_uints {
    let at = self.pos + i * 4
    let mut w = 0U
    for k in 0..<4 {
      if i * 4 + k < used {
        w = w | (self.data[at + k].to_uint() << (8 * k))
      }
    }
    words[i] = w
  }
  self.pos += used
  let out = FixedArray::make(count, 0U)
  let mut src = 0
  let mut bit_pos = 0
  let nb = 32 - bits
  for i in 0..<count {
    if nb - bit_pos >= 0 {
      out[i] = words[src] << (nb - bit_pos) >> nb
      bit_pos += bits
      if bit_pos == 32 {
        src += 1
        bit_pos = 0
      }
    } else {
      let lo = words[src] >> bit_pos
      src += 1
      out[i] = lo | (words[src] << (64 - bits - bit_pos) >> nb)
      bit_pos -= nb
    }
  }
  Some(out)
}

///|
/// `BitStuffer2::Decode` with `lerc2Version` 3: a byte of bit count, table mode and count size, the
/// count, then the values stuffed (in table mode, the table without its 0, then the indexes). None
/// where the C++ fails, or would read past the end or out of its table.
fn Cursor::decode(self : Cursor) -> FixedArray[UInt32]? {
  guard self.has(1L) else { return None }
  let head = u8_at(self.data, self.pos)
  self.pos += 1
  let bits67 = head >> 6
  let size = if bits67 == 0 { 4 } else { 3 - bits67 }
  let lut = (head & 32) != 0
  let bits = head & 31
  guard self.uint(size) is Some(n) else { return None }
  guard n <= MAX_POINTS.reinterpret_as_uint() else { return None }
  let count = n.reinterpret_as_int()
  if !lut {
    if bits > 0 {
      return self.unstuff(count, bits)
    }
    return Some(FixedArray::make(count, 0U))
  }
  guard self.has(1L) else { return None }
  let num_lut = u8_at(self.data, self.pos) - 1
  self.pos += 1
  guard num_lut >= 1 && self.unstuff(num_lut, bits) is Some(values) else {
    return None
  }
  let lut_bits = bit_count(num_lut.reinterpret_as_uint())
  guard self.unstuff(count, lut_bits) is Some(out) else { return None }
  for i in 0..<count {
    let index = out[i].reinterpret_as_int()
    guard index <= num_lut else { return None }
    out[i] = if index == 0 { 0 } else { values[index - 1] }
  }
  Some(out)
}
