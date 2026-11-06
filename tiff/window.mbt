// Ported from geotiff 3.0.5: MIT License, Copyright (c) 2015 EOX IT Services GmbH. See NOTICE.

///|
/// Most bytes of one window's bands.
const MAX_WINDOW_BYTES : Int32 = 256 * 1024 * 1024

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
