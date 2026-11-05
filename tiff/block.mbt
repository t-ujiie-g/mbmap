// Ported from geotiff 3.0.5: MIT License, Copyright (c) 2015 EOX IT Services GmbH. See NOTICE.

///|
/// Most bytes of one window's bands.
const MAX_WINDOW_BYTES : Int32 = 256 * 1024 * 1024

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

///|
/// A window of an image being read: `x0`, `y0` to `x1`, `y1` (pixels, end excluded; it may reach
/// past the image), the `samples` read, one band of little-endian values per sample.
pub struct Window {
  image : Image
  little : Bool
  x0 : Int32
  y0 : Int32
  x1 : Int32
  y1 : Int32
  samples : Array[Int32]
  bands : Array[FixedArray[Byte]]
}

///|
/// Stores `v` at value `i` of a band of `format` in `size` bytes as a JavaScript typed array
/// does (integers wrapped, float32 rounded).
fn store(
  band : FixedArray[Byte],
  i : Int32,
  format : Int32,
  size : Int32,
  v : Double,
) -> Unit {
  let bits = if format == 3 && size == 8 {
    v.reinterpret_as_int64()
  } else if format == 3 {
    Float::from_double(v).reinterpret_as_uint().to_int64()
  } else if v.is_nan() || v.is_inf() {
    0L
  } else {
    let t = if v < 0.0 { -(-v).floor() } else { v.floor() }
    let m = t % 4294967296.0
    (if m < 0.0 { m + 4294967296.0 } else { m }).to_int64()
  }
  for k in 0..<size {
    band[i * size + k] = ((bits >> (k * 8)) & 0xffL).to_byte()
  }
}

///|
/// A window of `image` (of a file `little`-endian or not) over the pixels `x0`, `y0` to `x1`,
/// `y1`, for `samples`; bands start as `fill` when it is truthy (geotiff's `fillValue`), else 0.
pub fn Window::new(
  image : Image,
  little : Bool,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  samples : Array[Int32],
  fill : Double,
) -> Window raise TiffError {
  if x0 > x1 || y0 > y1 {
    raise Invalid(0, "invalid window")
  }
  let width = x1.to_int64() - x0.to_int64()
  let height = y1.to_int64() - y0.to_int64()
  if width > MAX_WINDOW_BYTES.to_int64() || height > MAX_WINDOW_BYTES.to_int64() {
    raise Invalid(0, "a window too large")
  }
  let pixels = width * height
  let mut total = 0L
  let bands = []
  for s in samples {
    if s < 0 || s >= image.samples {
      raise Invalid(0, "invalid sample index \{s}")
    }
    let size = band_bytes(image.formats[s], image.bits[s])
    if size == 0 {
      raise Invalid(0, "unsupported data format/bitsPerSample")
    }
    total += pixels * size.to_int64()
    if total > MAX_WINDOW_BYTES.to_int64() {
      raise Invalid(0, "a window too large")
    }
    let band = FixedArray::make(pixels.to_int() * size, b'\x00')
    if fill != 0.0 && !fill.is_nan() {
      for i in 0..<pixels.to_int() {
        store(band, i, image.formats[s], size, fill)
      }
    }
    bands.push(band)
  }
  { image, little, x0, y0, x1, y1, samples, bands, }
}

///|
/// Decodes block `index` (in the order of the image's offsets) from `data`, compressed as the
/// image says unless `decoded` (the host inflated it), and copies its pixels into the window.
pub fn Window::block(
  self : Window,
  index : Int32,
  data : BytesView,
  decoded : Bool,
) -> Unit raise TiffError {
  let img = self.image
  let (bx, by, sample) = self.place(index)
  let rows = img.rows(by)
  let bits_per_pixel = if img.planar == 2 {
    img.bits[sample]
  } else {
    img.bits.fold(init=0, (a, b) => a + b)
  }
  let raw = (row_bytes(img.block_width.to_int64(), bits_per_pixel) *
  img.block_height.to_int64()).to_int()
  let mut b = match (decoded, img.compression) {
    (true, _) | (false, COMPRESSION_NONE) => {
      let copy = FixedArray::make(data.length(), b'\x00')
      for i in 0..<data.length() {
        copy[i] = data[i]
      }
      copy
    }
    (false, COMPRESSION_LZW) => lzw(data, raw)
    (false, COMPRESSION_PACKBITS) => packbits(data, raw)
    (false, c) => raise Invalid(0, "unsupported compression \{c}")
  }
  let mut little = self.little
  if img.predictor == 2 || img.predictor == 3 {
    let bits = img.bits[0]
    if bits % 8 != 0 || img.bits.iter().any(x => x != bits) {
      raise Invalid(
        0, "a predictor needs samples of whole bytes, all of one size",
      )
    }
    if img.predictor == 2 && bits == 64 {
      raise Invalid(0, "predictor 2 with 64-bit samples")
    }
    let stride = if img.planar == 2 { 1 } else { img.samples }
    unpredict(
      b,
      img.predictor,
      img.block_width,
      img.block_height,
      stride,
      bits / 8,
      little,
    )
    if img.predictor == 3 {
      little = true
    }
  }
  let bits0 = img.bits[0]
  if img.formats[0] == 1 && bits0 % 8 != 0 && bits0 <= 32 {
    let count = if img.planar == 2 { 1 } else { img.samples }
    b = unpack_bits(b, bits0, img.block_width, rows, count)
    little = true
  }
  self.copy(b, bx, by, sample, little, None)
}

///|
/// Fills block `index`'s pixels of the window with `value` (a block of byte count 0, which
/// geotiff fills with the GDAL no-data value when it is truthy, else 0).
pub fn Window::empty(
  self : Window,
  index : Int32,
  value : Double,
) -> Unit raise TiffError {
  let (bx, by, sample) = self.place(index)
  let v = if value.is_nan() { 0.0 } else { value }
  self.copy(FixedArray::make(0, b'\x00'), bx, by, sample, true, Some(v))
}

///|
/// Block `index`'s column, row and sample (0 for a block of every sample).
fn Window::place(
  self : Window,
  index : Int32,
) -> (Int32, Int32, Int32) raise TiffError {
  let img = self.image
  let per = img.across() * img.down()
  if index < 0 || index >= per * (if img.planar == 2 { img.samples } else { 1 }) {
    raise Invalid(0, "invalid block index \{index}")
  }
  let i = index % per
  (i % img.across(), i / img.across(), index / per)
}

///|
/// Copies the decoded block `b` at block column `bx`, row `by` (of `sample` with planar 2) into
/// the window's bands as geotiff's `_readRaster` does, or `value` for each pixel when given.
fn Window::copy(
  self : Window,
  b : FixedArray[Byte],
  bx : Int32,
  by : Int32,
  sample : Int32,
  little : Bool,
  value : Double?,
) -> Unit raise TiffError {
  let img = self.image
  let first_line = by * img.block_height
  let first_col = bx * img.block_width
  let rows = img.rows(by)
  let ymax = @cmp.minimum(
    @cmp.minimum(rows, rows - (first_line + rows - self.y1)),
    img.height - first_line,
  )
  let xmax = @cmp.minimum(
    @cmp.minimum(
      img.block_width,
      img.block_width - (first_col + img.block_width - self.x1),
    ),
    img.width - first_col,
  )
  let width = self.x1 - self.x0
  let pixel = img.pixel_bytes(sample)
  for si, s in self.samples {
    if img.planar == 2 && s != sample {
      continue
    }
    let mut offset = 0
    if img.planar == 1 {
      for k in 0..<s {
        offset += img.sample_bytes(k)
      }
    }
    let format = img.formats[s]
    let bits = img.bits[s]
    let size = band_bytes(format, bits)
    let src = img.sample_bytes(s)
    let band = self.bands[si]
    for y in @cmp.maximum(0, self.y0 - first_line)..<ymax {
      for x in @cmp.maximum(0, self.x0 - first_col)..<xmax {
        let out = (y + first_line - self.y0) * width + x + first_col - self.x0
        if value is Some(v) {
          store(band, out, format, size, v)
          continue
        }
        let at = (y * img.block_width + x) * pixel + offset
        if at + src > b.length() {
          raise Invalid(at, "a block shorter than its pixels")
        }
        if format == 3 && bits == 16 {
          let h = if little {
            b[at].to_int() | (b[at + 1].to_int() << 8)
          } else {
            (b[at].to_int() << 8) | b[at + 1].to_int()
          }
          let f = half_to_float(h)
          for k in 0..<4 {
            band[out * 4 + k] = ((f >> (k * 8)) & 0xffU).to_byte()
          }
        } else {
          for k in 0..<size {
            band[out * size + k] = if k >= src {
              b'\x00'
            } else if little {
              b[at + k]
            } else {
              b[at + src - 1 - k]
            }
          }
        }
      }
    }
  }
}
