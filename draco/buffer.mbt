// Ported from Draco 1.5.7: Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
/// `DRACO_BITSTREAM_VERSION(major, minor)`.
fn bitstream(major : Int32, minor : Int32) -> Int32 {
  (major << 8) | minor
}

///|
fn ult(a : Int32, b : Int32) -> Bool {
  a.reinterpret_as_uint() < b.reinterpret_as_uint()
}

///|
/// Draco's `DecoderBuffer` over `data[start, start + size)`, with its bit reader. A read past the
/// end sets `failed` and moves nothing, as Draco's reads fail; callers check `failed` where Draco
/// checks the read. `floor` is the input's first byte, which no read goes below.
priv struct Buffer {
  data : FixedArray[Byte]
  floor : Int32
  mut start : Int32
  mut size : Int32
  mut pos : Int32
  mut version : Int32
  mut bit_mode : Bool
  mut bit_start : Int32
  mut bit_end : Int32
  mut bit_offset : Int32
  mut failed : Bool
}

///|
fn Buffer::new(data : FixedArray[Byte], start : Int32, size : Int32) -> Buffer {
  {
    data,
    floor: start,
    start,
    size,
    pos: 0,
    version: 0,
    bit_mode: false,
    bit_start: 0,
    bit_end: 0,
    bit_offset: 0,
    failed: false,
  }
}

///|
fn Buffer::copy(self : Buffer) -> Buffer {
  { ..self, }
}

///|
/// `*self = other`.
fn Buffer::assign(self : Buffer, other : Buffer) -> Unit {
  self.start = other.start
  self.size = other.size
  self.pos = other.pos
  self.version = other.version
  self.bit_mode = other.bit_mode
  self.bit_start = other.bit_start
  self.bit_end = other.bit_end
  self.bit_offset = other.bit_offset
  self.failed = other.failed
}

///|
/// `Init(data_head, size, version)`: `start` is absolute in `data`.
fn Buffer::init(
  self : Buffer,
  start : Int32,
  size : Int32,
  version : Int32,
) -> Unit {
  self.start = start
  self.size = size
  self.pos = 0
  self.version = version
}

///|
fn Buffer::head(self : Buffer) -> Int32 {
  self.start + self.pos
}

///|
fn Buffer::remaining(self : Buffer) -> Int32 {
  self.size - self.pos
}

///|
fn Buffer::has(self : Buffer, n : Int32) -> Bool {
  if n < 0 || self.pos + n > self.size || self.size < 0 {
    self.failed = true
    false
  } else {
    true
  }
}

///|
fn Buffer::byte_at(self : Buffer, i : Int32) -> Int32 {
  self.data[self.start + i].to_int()
}

///|
fn Buffer::u8(self : Buffer) -> Int32 {
  guard self.has(1) else { 0 }
  let v = self.byte_at(self.pos)
  self.pos += 1
  v
}

///|
fn Buffer::i8(self : Buffer) -> Int32 {
  self.u8() << 24 >> 24
}

///|
fn Buffer::u16(self : Buffer) -> Int32 {
  guard self.has(2) else { 0 }
  let p = self.pos
  self.pos += 2
  self.byte_at(p) | (self.byte_at(p + 1) << 8)
}

///|
/// A little-endian 32-bit word (signed or unsigned bits).
fn Buffer::u32(self : Buffer) -> Int32 {
  guard self.has(4) else { 0 }
  let p = self.pos
  self.pos += 4
  self.byte_at(p) |
  (self.byte_at(p + 1) << 8) |
  (self.byte_at(p + 2) << 16) |
  (self.byte_at(p + 3) << 24)
}

///|
fn Buffer::u64(self : Buffer) -> UInt64 {
  guard self.has(8) else { 0 }
  let lo = self.u32().reinterpret_as_uint().to_uint64()
  let hi = self.u32().reinterpret_as_uint().to_uint64()
  lo | (hi << 32)
}

///|
fn Buffer::f32(self : Buffer) -> Float {
  Float::reinterpret_from_int(self.u32())
}

///|
/// `DecodeVarint<uint32_t>`: at most five bytes, the value taken mod 2^32; bytes read before a
/// failure stay consumed.
fn Buffer::varint(self : Buffer) -> Int32 {
  let mut v = 0
  for depth in 0..<5 {
    let b = self.u8()
    guard !self.failed else { return 0 }
    v = v | ((b & 0x7f) << (7 * depth))
    if b < 0x80 {
      return v
    }
  }
  self.failed = true
  0
}

///|
/// `DecodeVarint<uint64_t>`: at most ten bytes.
fn Buffer::varint64(self : Buffer) -> UInt64 {
  let mut v : UInt64 = 0
  for depth in 0..<10 {
    let b = self.u8()
    guard !self.failed else { return 0 }
    v = v | ((b & 0x7f).to_uint64() << (7 * depth))
    if b < 0x80 {
      return v
    }
  }
  self.failed = true
  0
}

///|
/// `remaining_size()` against an unsigned count, as Draco compares them (a negative remainder is
/// below every count).
fn Buffer::fits(self : Buffer, n : UInt64) -> Bool {
  let r = self.remaining()
  r >= 0 && n <= r.to_uint64()
}

///|
fn Buffer::start_bits(self : Buffer, decode_size : Bool) -> UInt64 {
  let mut size : UInt64 = 0
  if decode_size {
    size = if self.version < bitstream(2, 2) {
      self.u64()
    } else {
      self.varint64()
    }
    guard !self.failed else { return 0 }
  }
  self.bit_mode = true
  self.bit_start = self.head()
  self.bit_end = self.head() + self.remaining()
  self.bit_offset = 0
  size
}

///|
fn Buffer::end_bits(self : Buffer) -> Unit {
  self.bit_mode = false
  self.pos += (self.bit_offset + 7) / 8
}

///|
/// `GetBits`: bits past the end read as 0 and are not counted. The caller checks `bit_mode` and
/// `nbits <= 32` where Draco does.
fn Buffer::bits(self : Buffer, nbits : Int32) -> Int32 {
  let mut value = 0
  for bit in 0..<nbits {
    let off = self.bit_offset
    let at = self.bit_start + (off >> 3)
    if at < self.bit_end {
      value = value | (((self.data[at].to_int() >> (off & 7)) & 1) << bit)
      self.bit_offset = off + 1
    }
  }
  value
}
