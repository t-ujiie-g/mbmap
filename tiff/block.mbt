// Ported from geotiff 3.0.5: MIT License, Copyright (c) 2015 EOX IT Services GmbH. See NOTICE.

///|
/// TIFF's Compression values read here (JPEG and Deflate arrive already decoded).
const COMPRESSION_NONE : Int32 = 1

///|
const COMPRESSION_LZW : Int32 = 5

///|
const COMPRESSION_PACKBITS : Int32 = 32773

///|
/// LZW's clear code, end code, first free code and table size.
const LZW_CLEAR : Int32 = 256

///|
const LZW_END : Int32 = 257

///|
const LZW_FIRST : Int32 = 258

///|
const LZW_MAX : Int32 = 4096

///|
/// The LZW data of a block as geotiff's `LZWDecoder` decodes it (TIFF's early change, codes
/// up to 12 bits; past the end of the data codes read as zeros, or as EOI from the byte after
/// the last), stopping after `max` bytes.
pub fn lzw(data : BytesView, max : Int32) -> FixedArray[Byte] raise TiffError {
  let index = FixedArray::make(LZW_MAX, LZW_MAX)
  let chars = FixedArray::make(LZW_MAX, b'\x00')
  for i in 0..<LZW_CLEAR {
    chars[i] = i.to_byte()
  }
  let out = FixedArray::make(max, b'\x00')
  let mut n = 0
  let mut size = LZW_FIRST
  let mut width = 9
  // A byte and a bit in it: one bit index would wrap at 256 MB of data.
  let mut pos = 0
  let mut bit = 0
  let next = () => {
    if pos >= data.length() {
      return LZW_END
    }
    let mut v = 0
    for i in 0..<width {
      let p = bit + i
      let at = pos + (p >> 3)
      let byte = if at < data.length() { data[at].to_int() } else { 0 }
      v = (v << 1) | ((byte >> (7 - (p & 7))) & 1)
    }
    pos += (bit + width) >> 3
    bit = (bit + width) & 7
    v
  }
  // Appends entry `code`'s bytes; gives its first one.
  let emit = (code : Int32) => {
    let mut len = 0
    let mut c = code
    while c != LZW_MAX && len < LZW_MAX {
      len += 1
      c = index[c]
    }
    let start = n
    n = @cmp.minimum(n + len, max)
    c = code
    for k in 0..<len {
      if start + len - 1 - k < max {
        out[start + len - 1 - k] = chars[c]
      }
      c = index[c]
    }
    out[start]
  }
  let add = (prev : Int32, c : Byte) => {
    if size < LZW_MAX {
      index[size] = prev
      chars[size] = c
    }
    size += 1
  }
  let mut old = -1
  let mut code = next()
  while code != LZW_END && n < max {
    if code == LZW_CLEAR {
      size = LZW_FIRST
      width = 9
      code = next()
      while code == LZW_CLEAR {
        code = next()
      }
      if code == LZW_END {
        break
      }
      if code > LZW_CLEAR {
        raise Invalid(pos, "corrupted LZW code \{code}")
      }
      emit(code) |> ignore
      old = code
    } else if code < size {
      let first = emit(code)
      if old >= 0 {
        add(old, first)
      }
      old = code
    } else {
      if old < 0 {
        raise Invalid(pos, "invalid LZW code \{code}")
      }
      let first = emit(old)
      if n < max {
        out[n] = first
        n += 1
      }
      add(old, first)
      old = code
    }
    if size + 1 >= 1 << width {
      if width == 12 {
        old = -1
      } else {
        width += 1
      }
    }
    code = next()
  }
  if n == max {
    out
  } else {
    FixedArray::makei(n, i => out[i])
  }
}

///|
/// PackBits data as TIFF 6.0 §9 decodes it (a header of -128 is a no-op), at most `max` bytes.
pub fn packbits(data : BytesView, max : Int32) -> FixedArray[Byte] {
  let out = Array(capacity=@cmp.minimum(max, data.length() * 2))
  let mut i = 0
  while i < data.length() && out.length() < max {
    let h = data[i].to_int()
    i += 1
    if h < 128 {
      for k in 0..<=h {
        if i + k < data.length() {
          out.push(data[i + k])
        }
      }
      i += h + 1
    } else if h > 128 && i < data.length() {
      for _ in 0..<=(256 - h) {
        out.push(data[i])
      }
      i += 1
    }
  }
  FixedArray::makei(@cmp.minimum(out.length(), max), k => out[k])
}

///|
/// The bytes of one row of block data: `width` pixels of `bits` each (a row starts on a byte).
fn row_bytes(width : Int64, bits : Int32) -> Int64 {
  (width * bits.to_int64() + 7L) / 8L
}

///|
/// Undoes predictor 2 (horizontal differencing, in the file's byte order) or 3 (floating point:
/// byte planes, giving little-endian samples) over the rows of `b`, as geotiff's
/// `applyPredictor` does with `width` x `height` blocks of `stride` samples per pixel.
pub fn unpredict(
  b : FixedArray[Byte],
  predictor : Int32,
  width : Int32,
  height : Int32,
  stride : Int32,
  bytes : Int32,
  little : Bool,
) -> Unit raise TiffError {
  let size = width.to_int64() * stride.to_int64() * bytes.to_int64()
  if size <= 0L || b.length() == 0 {
    return
  }
  if size > b.length().to_int64() {
    raise Invalid(0, "a block shorter than its rows")
  }
  let row = size.to_int()
  let mut start = -row
  for _ in 0..<height {
    start += row
    if start >= b.length() {
      break
    }
    if row > b.length() - start {
      raise Invalid(start, "a block shorter than its rows")
    }
    if predictor == 2 {
      let get = (at : Int32) => {
        let mut v = 0L
        for k in 0..<bytes {
          let byte = b[at + (if little { bytes - 1 - k } else { k })]
          v = (v << 8) | byte.to_int64()
        }
        v
      }
      let set = (at : Int32, v : Int64) => {
        for k in 0..<bytes {
          let shift = (if little { k } else { bytes - 1 - k }) * 8
          b[at + k] = ((v >> shift) & 0xffL).to_byte()
        }
      }
      for i in stride..<(width * stride) {
        let at = start + i * bytes
        set(at, get(at) + get(at - stride * bytes))
      }
    } else {
      for i in stride..<row {
        b[start + i] = (b[start + i].to_int() + b[start + i - stride].to_int()).to_byte()
      }
      let copy = FixedArray::makei(row, i => b[start + i])
      let count = row / bytes
      for i in 0..<count {
        for k in 0..<bytes {
          b[start + bytes * i + k] = copy[(bytes - k - 1) * count + i]
        }
      }
    }
  }
}

///|
/// Samples of `bits` (not a whole number of bytes) unpacked, most significant bit first and each
/// row starting on a byte, into little-endian samples of 1, 2 or 4 bytes as geotiff's
/// `normalizeArray` does: `width` x `rows` pixels of `count` samples each.
pub fn unpack_bits(
  b : FixedArray[Byte],
  bits : Int32,
  width : Int32,
  rows : Int32,
  count : Int32,
) -> FixedArray[Byte] raise TiffError {
  let size = if bits <= 8 { 1 } else if bits <= 16 { 2 } else { 4 }
  let samples = width.to_int64() * count.to_int64()
  let bytes = samples * rows.to_int64() * size.to_int64()
  if bytes > MAX_BLOCK_BYTES.to_int64() {
    raise Invalid(0, "a block too large")
  }
  let line = row_bytes(samples, bits) * 8L
  let out = FixedArray::make(bytes.to_int(), b'\x00')
  for y in 0..<rows {
    for x in 0..<samples.to_int() {
      let at = y.to_int64() * line + x.to_int64() * bits.to_int64()
      if (at + bits.to_int64() + 7L) / 8L > b.length().to_int64() {
        raise Invalid((at / 8L).to_int(), "a block shorter than its rows")
      }
      let mut v = 0L
      for k in 0..<bits {
        let p = at + k.to_int64()
        let shift = 7 - (p & 7L).to_int()
        v = (v << 1) | ((b[(p >> 3).to_int()].to_int64() >> shift) & 1L)
      }
      let o = (y * width * count + x) * size
      for k in 0..<size {
        out[o + k] = ((v >> (k * 8)) & 0xffL).to_byte()
      }
    }
  }
  out
}

///|
/// The bits of a float32 equal to the IEEE half `h`.
fn half_to_float(h : Int32) -> UInt32 {
  let sign = (h & 0x8000) << 16
  let e = (h >> 10) & 0x1f
  let m = h & 0x3ff
  let bits = if e == 0x1f {
    sign | 0x7f800000 | (m << 13)
  } else if e != 0 {
    sign | ((e + 112) << 23) | (m << 13)
  } else if m == 0 {
    sign
  } else {
    // A subnormal half is a normal float.
    let mut e = 113
    let mut m = m
    while (m & 0x400) == 0 {
      m = m << 1
      e -= 1
    }
    sign | (e << 23) | ((m & 0x3ff) << 13)
  }
  bits.reinterpret_as_uint()
}

///|
/// Bytes of one value of a band of sample format `format` and `bits` (geotiff's `arrayForType`),
/// or 0 when geotiff reads no such samples.
pub fn band_bytes(format : Int32, bits : Int32) -> Int32 {
  match format {
    1 if bits >= 1 && bits <= 8 => 1
    1 if bits >= 1 && bits <= 16 => 2
    1 if bits == 32 => 4
    2 if bits == 8 => 1
    2 if bits == 16 => 2
    2 if bits == 32 => 4
    3 if bits == 16 || bits == 32 => 4
    3 if bits == 64 => 8
    _ => 0
  }
}
