// Ported from Draco 1.5.7 (compression/entropy/ans.h, rans_symbol_decoder.h, symbol_decoding.cc,
// compression/bit_coders/rans_bit_decoder.cc): Apache License 2.0, Copyright 2016 The Draco
// Authors. See NOTICE.

///|
const ANS_L_BASE : UInt32 = 4096

///|
/// The most symbols a rANS table may declare; Draco only bounds it by the bytes left.
const MAX_SYMBOLS : Int32 = 0x100000

///|
/// `RAnsBitDecoder` (`rabs_desc_read` over a byte-wise rANS state).
priv struct BitDecoder {
  data : FixedArray[Byte]
  mut base : Int32
  mut offset : Int32
  mut state : UInt32
  mut prob_zero : Int32
}

///|
fn BitDecoder::new(data : FixedArray[Byte]) -> BitDecoder {
  { data, base: 0, offset: 0, state: 0, prob_zero: 0, }
}

///|
fn BitDecoder::start(self : BitDecoder, b : Buffer) -> Bool {
  self.prob_zero = b.u8()
  guard !b.failed else { return false }
  let size = if b.version < bitstream(2, 2) { b.u32() } else { b.varint() }
  guard !b.failed else { return false }
  guard b.fits(size.reinterpret_as_uint().to_uint64()) else { return false }
  let base = b.head()
  guard size >= 1 else { return false }
  self.base = base
  let last = b.data[base + size - 1].to_int()
  match last >> 6 {
    0 => {
      self.offset = size - 1
      self.state = (last & 0x3f).reinterpret_as_uint()
    }
    1 => {
      guard size >= 2 else { return false }
      self.offset = size - 2
      self.state = ((b.data[base + size - 2].to_int() | (last << 8)) & 0x3fff).reinterpret_as_uint()
    }
    2 => {
      guard size >= 3 else { return false }
      self.offset = size - 3
      self.state = ((
        b.data[base + size - 3].to_int() |
        (b.data[base + size - 2].to_int() << 8) |
        (last << 16)
      ) &
      0x3fffff).reinterpret_as_uint()
    }
    _ => return false
  }
  self.state = self.state + ANS_L_BASE
  guard self.state < ANS_L_BASE * 256 else { return false }
  b.pos += size
  true
}

///|
fn BitDecoder::bit(self : BitDecoder) -> Bool {
  let p = ((256 - self.prob_zero) & 0xff).reinterpret_as_uint()
  if self.state < ANS_L_BASE && self.offset > 0 {
    self.offset -= 1
    self.state = self.state * 256 +
      self.data[self.base + self.offset].to_int().reinterpret_as_uint()
  }
  let x = self.state
  let quot = x >> 8
  let rem = x & 0xff
  let xn = quot * p
  if rem < p {
    self.state = xn + rem
    true
  } else {
    self.state = x - xn - p
    false
  }
}

///|
/// `RAnsSymbolDecoder<bits>`: a rANS table read by `create`, then a stream by `start`.
priv struct SymbolDecoder {
  data : FixedArray[Byte]
  precision_bits : Int32
  mut num_symbols : Int32
  mut probs : FixedArray[UInt32]
  mut cums : FixedArray[UInt32]
  mut lut : FixedArray[Int32]
  mut base : Int32
  mut offset : Int32
  mut state : UInt32
}

///|
/// `ComputeRAnsPrecisionFromUniqueSymbolsBitLength`.
fn SymbolDecoder::new(
  data : FixedArray[Byte],
  bit_length : Int32,
) -> SymbolDecoder {
  let unclamped = 3 * bit_length / 2
  let precision_bits = if unclamped < 12 {
    12
  } else if unclamped > 20 {
    20
  } else {
    unclamped
  }
  {
    data,
    precision_bits,
    num_symbols: 0,
    probs: [],
    cums: [],
    lut: [],
    base: 0,
    offset: 0,
    state: 0,
  }
}

///|
fn SymbolDecoder::create(self : SymbolDecoder, b : Buffer) -> Bool {
  guard b.version != 0 else { return false }
  let n = if b.version < bitstream(2, 0) { b.u32() } else { b.varint() }
  guard !b.failed else { return false }
  self.num_symbols = n
  guard b.fits((n.reinterpret_as_uint() / 64).to_uint64()) else { return false }
  guard !ult(MAX_SYMBOLS, n) else { return false }
  let probs = FixedArray::make(n, (0 : UInt32))
  self.probs = probs
  if n == 0 {
    return true
  }
  let mut i = 0
  while i < n {
    let prob_data = b.u8()
    guard !b.failed else { return false }
    let token = prob_data & 3
    if token == 3 {
      let offset = prob_data >> 2
      guard i + offset < n else { return false }
      i += offset
    } else {
      let mut prob = prob_data >> 2
      for k in 0..<token {
        let eb = b.u8()
        guard !b.failed else { return false }
        prob = prob | (eb << (8 * (k + 1) - 2))
      }
      probs[i] = prob.reinterpret_as_uint()
    }
    i += 1
  }
  let precision = 1 << self.precision_bits
  let lut = FixedArray::make(precision, 0)
  let cums = FixedArray::make(n, (0 : UInt32))
  let mut cum : UInt32 = 0
  let mut act : UInt32 = 0
  for s in 0..<n {
    cums[s] = cum
    cum = cum + probs[s]
    guard cum <= precision.reinterpret_as_uint() else { return false }
    for j in act.reinterpret_as_int()..<cum.reinterpret_as_int() {
      lut[j] = s
    }
    act = cum
  }
  guard cum == precision.reinterpret_as_uint() else { return false }
  self.lut = lut
  self.cums = cums
  true
}

///|
fn SymbolDecoder::start(self : SymbolDecoder, b : Buffer) -> Bool {
  let bytes = if b.version < bitstream(2, 0) { b.u64() } else { b.varint64() }
  guard !b.failed else { return false }
  guard b.fits(bytes) else { return false }
  let base = b.head()
  let size = bytes.to_int()
  b.pos += size
  guard size >= 1 else { return false }
  self.base = base
  let byte = fn(i : Int32) { b.data[base + i].to_int() }
  let last = byte(size - 1)
  match last >> 6 {
    0 => {
      self.offset = size - 1
      self.state = (last & 0x3f).reinterpret_as_uint()
    }
    1 => {
      guard size >= 2 else { return false }
      self.offset = size - 2
      self.state = ((byte(size - 2) | (last << 8)) & 0x3fff).reinterpret_as_uint()
    }
    2 => {
      guard size >= 3 else { return false }
      self.offset = size - 3
      self.state = ((byte(size - 3) | (byte(size - 2) << 8) | (last << 16)) &
      0x3fffff).reinterpret_as_uint()
    }
    _ => {
      // Draco reads the word even when fewer than four bytes were given, from the bytes before.
      guard base + size - 4 >= b.floor else { return false }
      self.offset = size - 4
      self.state = ((
        byte(size - 4) |
        (byte(size - 3) << 8) |
        (byte(size - 2) << 16) |
        (last << 24)
      ) &
      0x3fffffff).reinterpret_as_uint()
    }
  }
  let l_base = (4 << self.precision_bits).reinterpret_as_uint()
  self.state = self.state + l_base
  self.state < l_base * 256
}

///|
fn SymbolDecoder::symbol(self : SymbolDecoder) -> Int32 {
  let l_base = (4 << self.precision_bits).reinterpret_as_uint()
  while self.state < l_base && self.offset > 0 {
    self.offset -= 1
    self.state = self.state * 256 +
      self.data[self.base + self.offset].to_int().reinterpret_as_uint()
  }
  let quo = self.state >> self.precision_bits
  let rem = self.state & ((1 << self.precision_bits) - 1).reinterpret_as_uint()
  let s = self.lut[rem.reinterpret_as_int()]
  self.state = quo * self.probs[s] + rem - self.cums[s]
  s
}

///|
/// `DecodeSymbols`: `num_values` symbols into `out[0, num_values)`, written in order (a failure
/// leaves those decoded so far, which the valence traversal reads).
fn decode_symbols(
  num_values : Int32,
  num_components : Int32,
  b : Buffer,
  out : FixedArray[Int32],
) -> Bool {
  if num_values == 0 {
    return true
  }
  let scheme = b.u8()
  guard !b.failed else { return false }
  if scheme == 0 {
    let tags = SymbolDecoder::new(b.data, 5)
    guard tags.create(b) && tags.start(b) else { return false }
    guard tags.num_symbols != 0 else { return false }
    let _ = b.start_bits(false)
    let mut value_id = 0
    let mut i = 0
    while ult(i, num_values) {
      let bit_length = tags.symbol()
      guard ult(bit_length, 33) else { return false }
      for _ in 0..<num_components {
        guard value_id < out.length() else { return false }
        out[value_id] = b.bits(bit_length)
        value_id += 1
      }
      i += num_components
    }
    b.end_bits()
    true
  } else if scheme == 1 {
    let max_bit_length = b.u8()
    guard !b.failed else { return false }
    guard max_bit_length >= 1 && max_bit_length <= 18 else { return false }
    let d = SymbolDecoder::new(b.data, max_bit_length)
    guard d.create(b) else { return false }
    guard d.num_symbols != 0 else { return false }
    guard d.start(b) else { return false }
    guard num_values <= out.length() else { return false }
    for i in 0..<num_values {
      out[i] = d.symbol()
    }
    true
  } else {
    false
  }
}
