// Ported from geotiff 3.0.5: MIT License, Copyright (c) 2015 EOX IT Services GmbH. See NOTICE.

///|
/// Most images (IFDs) read from one file.
pub const MAX_IMAGES : Int32 = 256

///|
/// Most pixels a tile may reach past its image: a small overview keeps its file's tile size,
/// but a tile far larger than its image only makes one tiny file decode a large block.
let max_tile_overhang : Double = 4096.0

///|
/// Most entries in one IFD, and most values in one entry.
pub const MAX_ENTRIES : Int32 = 4096

///|
/// Most values of one tag (a tile offset per block, at most).
pub const MAX_VALUES : Int32 = 16 * 1024 * 1024

///|
/// Most values of all tags of one file read as lists, over its IFDs: a block table
/// at `MAX_VALUES` and its overviews fit, the same bytes named by every IFD do not.
pub const MAX_FILE_VALUES : Int32 = 4 * MAX_VALUES

///|
/// Most bytes of one decoded block.
pub const MAX_BLOCK_BYTES : Int32 = 256 * 1024 * 1024

///|
/// TIFF 6.0, GeoTIFF and GDAL tags this reader takes from an IFD.
const TAG_NEW_SUBFILE_TYPE : Int32 = 254

///|
const TAG_SUBFILE_TYPE : Int32 = 255

///|
const TAG_IMAGE_WIDTH : Int32 = 256

///|
const TAG_IMAGE_LENGTH : Int32 = 257

///|
const TAG_BITS_PER_SAMPLE : Int32 = 258

///|
const TAG_COMPRESSION : Int32 = 259

///|
const TAG_PHOTOMETRIC : Int32 = 262

///|
const TAG_STRIP_OFFSETS : Int32 = 273

///|
const TAG_SAMPLES_PER_PIXEL : Int32 = 277

///|
const TAG_ROWS_PER_STRIP : Int32 = 278

///|
const TAG_STRIP_BYTE_COUNTS : Int32 = 279

///|
const TAG_PLANAR_CONFIGURATION : Int32 = 284

///|
const TAG_PREDICTOR : Int32 = 317

///|
const TAG_TILE_WIDTH : Int32 = 322

///|
const TAG_TILE_LENGTH : Int32 = 323

///|
const TAG_TILE_OFFSETS : Int32 = 324

///|
const TAG_TILE_BYTE_COUNTS : Int32 = 325

///|
const TAG_SAMPLE_FORMAT : Int32 = 339

///|
const TAG_JPEG_TABLES : Int32 = 347

///|
const TAG_MODEL_PIXEL_SCALE : Int32 = 33550

///|
const TAG_MODEL_TIEPOINT : Int32 = 33922

///|
const TAG_MODEL_TRANSFORMATION : Int32 = 34264

///|
const TAG_GEO_KEY_DIRECTORY : Int32 = 34735

///|
const TAG_GDAL_NODATA : Int32 = 42113

///|
/// Errors reading a TIFF: `Invalid(pos, message)`, or `Truncated(need)` when the bytes end
/// before the IFDs do and `need` bytes from the start would hold what is missing.
pub(all) suberror TiffError {
  Invalid(Int32, String)
  Truncated(Double)
}

///|
pub fn TiffError::message(self : TiffError) -> String {
  match self {
    Invalid(pos, m) => "malformed TIFF at \{pos}: \{m}"
    Truncated(_) => "the TIFF ends before its image directories do"
  }
}

///|
/// One image (IFD) as geotiff's `GeoTIFFImage` sees it: `blocks` across and down, each
/// `block_width` x `block_height` pixels (a strip is as wide as the image); per sample `bits` and
/// `formats` (1 unsigned, 2 signed, 3 float); `offsets` and `counts` per block (per sample too
/// with `planar` 2); the geo tags' values (empty when absent), the GeoKeys' EPSG code (0 for
/// none) and raster type, and `nodata` (GDAL_NODATA's text).
pub struct Image {
  width : Int32
  height : Int32
  tiled : Bool
  block_width : Int32
  block_height : Int32
  samples : Int32
  bits : Array[Int32]
  formats : Array[Int32]
  planar : Int32
  compression : Int32
  predictor : Int32
  photometric : Int32
  subfile : Int32
  old_subfile : Int32
  offsets : Array[Double]
  counts : Array[Double]
  pixel_scale : Array[Double]
  tiepoint : Array[Double]
  transform : Array[Double]
  epsg : Int32
  raster_type : Int32
  nodata : String?
  jpeg_tables : Bytes?
}

///|
/// Blocks across the image.
pub fn Image::across(self : Image) -> Int32 {
  blocks_over(self.width, self.block_width)
}

///|
/// Blocks down the image.
pub fn Image::down(self : Image) -> Int32 {
  blocks_over(self.height, self.block_height)
}

///|
/// Blocks of `block` pixels over `size` pixels.
fn blocks_over(size : Int32, block : Int32) -> Int32 {
  ((size.to_int64() + block.to_int64() - 1L) / block.to_int64()).to_int()
}

///|
/// Rows of block row `y`: a strip at the bottom may be shorter, a tile never is.
pub fn Image::rows(self : Image, y : Int32) -> Int32 {
  if self.tiled ||
    (y + 1).to_int64() * self.block_height.to_int64() <= self.height.to_int64() {
    self.block_height
  } else {
    self.height - y * self.block_height
  }
}

///|
/// Bytes of one decoded sample of sample `i` (after unpacking bits narrower than a byte).
pub fn Image::sample_bytes(self : Image, i : Int32) -> Int32 {
  (self.bits[i] + 7) / 8
}

///|
/// Bytes of one decoded pixel of a block: every sample's, or with `planar` 2 one sample's.
pub fn Image::pixel_bytes(self : Image, sample : Int32) -> Int32 {
  if self.planar == 2 {
    return self.sample_bytes(sample)
  }
  let mut n = 0
  for i in 0..<self.samples {
    n += self.sample_bytes(i)
  }
  n
}

///|
/// Reading state over a file's first bytes: byte order, BigTIFF, the values read
/// as lists so far and how many a file may have.
priv struct Tiff {
  b : BytesView
  little : Bool
  big : Bool
  mut values : Int64
  max_values : Int32
}

///|
fn Tiff::need(self : Tiff, at : Double, n : Double) -> Unit raise TiffError {
  if at < 0.0 || n < 0.0 || at + n > self.b.length().to_double() {
    raise Truncated(at + n)
  }
}

///|
fn Tiff::uint(self : Tiff, at : Int32, n : Int32) -> Double {
  let mut v = 0.0
  for i in 0..<n {
    let byte = self.b[if self.little { at + n - 1 - i } else { at + i }]
    v = v * 256.0 + byte.to_double()
  }
  v
}

///|
fn Tiff::u16(self : Tiff, at : Int32) -> Int32 {
  self.uint(at, 2).to_int()
}

///|
/// The number at `at` of TIFF field type `t` (BYTE … IFD8), as a double.
fn Tiff::value(self : Tiff, t : Int32, at : Int32) -> Double {
  // `half` is 2 to the power of the bits minus one.
  let signed = (v : Double, half : Double) => {
    if v >= half {
      v - half * 2.0
    } else {
      v
    }
  }
  match t {
    1 | 2 | 7 => self.uint(at, 1)
    6 => signed(self.uint(at, 1), 128)
    3 => self.uint(at, 2)
    8 => signed(self.uint(at, 2), 32768)
    4 | 13 => self.uint(at, 4)
    9 => signed(self.uint(at, 4), 2147483648)
    16 | 18 => self.uint(at, 8)
    17 => signed(self.uint(at, 8), 9223372036854775808)
    5 => self.uint(at, 4) / self.uint(at + 4, 4)
    10 =>
      signed(self.uint(at, 4), 2147483648) /
      signed(self.uint(at + 4, 4), 2147483648)
    11 => {
      let bits = self.uint(at, 4).to_int64().to_int().reinterpret_as_uint()
      Float::reinterpret_from_uint(bits).to_double()
    }
    12 => {
      let hi = self.uint(if self.little { at + 4 } else { at }, 4)
      let lo = self.uint(if self.little { at } else { at + 4 }, 4)
      ((hi.to_int64() << 32) | lo.to_int64()).reinterpret_as_double()
    }
    _ => 0.0
  }
}

///|
/// Bytes of one value of field type `t`, 0 for an unknown type.
fn type_size(t : Int32) -> Int32 {
  match t {
    1 | 2 | 6 | 7 => 1
    3 | 8 => 2
    4 | 9 | 11 | 13 => 4
    5 | 10 | 12 | 16 | 17 | 18 => 8
    _ => 0
  }
}

///|
/// One IFD entry: its type, count and where its values start.
priv struct Entry {
  t : Int32
  count : Int32
  at : Int32
}

///|
/// Counts entry `e`'s values against the file's.
fn Tiff::charge(self : Tiff, e : Entry) -> Unit raise TiffError {
  self.values += e.count.to_int64()
  if self.values > self.max_values.to_int64() {
    raise Invalid(e.at, "too many values in the file")
  }
}

///|
fn Tiff::list(self : Tiff, e : Entry) -> Array[Double] raise TiffError {
  self.charge(e)
  let size = type_size(e.t)
  Array::makei(e.count, i => self.value(e.t, e.at + i * size))
}

///|
/// Reads the IFDs of the TIFF or BigTIFF in `b` (its first bytes at least) as geotiff's
/// `GeoTIFF.fromSource` and `getImage` read them; gives the images and whether the file is
/// little-endian. Raises `Truncated` when an IFD or a tag's values lie past `b`.
pub fn read_tiff(b : BytesView) -> (Array[Image], Bool) raise TiffError {
  read_images(b, MAX_FILE_VALUES)
}

///|
/// `read_tiff` taking at most `max_values` values.
fn read_images(
  b : BytesView,
  max_values : Int32,
) -> (Array[Image], Bool) raise TiffError {
  if b.length() < 8 {
    raise Truncated(16)
  }
  let little = match (b[0], b[1]) {
    (b'I', b'I') => true
    (b'M', b'M') => false
    _ => raise Invalid(0, "not a TIFF file")
  }
  let t0 : Tiff = { b, little, big: false, values: 0, max_values, }
  let version = t0.u16(2)
  let big = match version {
    42 => false
    43 => true
    _ => raise Invalid(2, "not a TIFF file")
  }
  let t : Tiff = { b, little, big, values: 0, max_values, }
  if big {
    t.need(0, 16)
    if t.u16(4) != 8 || t.u16(6) != 0 {
      raise Invalid(4, "unsupported BigTIFF offset size")
    }
  }
  let mut next = if big { t.uint(8, 8) } else { t.uint(4, 4) }
  let seen : Array[Double] = []
  let images = []
  while next != 0.0 {
    if images.length() >= MAX_IMAGES || seen.contains(next) {
      raise Invalid(0, "too many image directories, or a loop of them")
    }
    seen.push(next)
    let (image, after) = t.ifd(next)
    images.push(image)
    next = after
  }
  if images.is_empty() {
    raise Invalid(4, "no image directory")
  }
  (images, little)
}

///|
/// The IFD at `at`, and the offset of the next one (0 for none).
fn Tiff::ifd(self : Tiff, at : Double) -> (Image, Double) raise TiffError {
  let count_size = if self.big { 8 } else { 2 }
  let entry_size = if self.big { 20 } else { 12 }
  let inline = if self.big { 8 } else { 4 }
  self.need(at, count_size.to_double())
  let pos = at.to_int()
  let n = self.uint(pos, count_size)
  if n > MAX_ENTRIES.to_double() {
    raise Invalid(pos, "too many entries")
  }
  let n = n.to_int()
  self.need(at, (count_size + n * entry_size + inline).to_double())
  let entries : Map[Int32, Entry] = Map([])
  for i in 0..<n {
    let e = pos + count_size + i * entry_size
    let tag = self.u16(e)
    let ty = self.u16(e + 2)
    let count = self.uint(e + 4, inline)
    let size = type_size(ty)
    if size == 0 {
      continue
    }
    if count > MAX_VALUES.to_double() {
      raise Invalid(e, "too many values")
    }
    let bytes = count * size.to_double()
    let start = if bytes <= inline.to_double() {
      (e + 4 + inline).to_double()
    } else {
      self.uint(e + 4 + inline, inline)
    }
    if tag
      is (TAG_NEW_SUBFILE_TYPE
      | TAG_SUBFILE_TYPE
      | TAG_IMAGE_WIDTH
      | TAG_IMAGE_LENGTH
      | TAG_BITS_PER_SAMPLE
      | TAG_COMPRESSION
      | TAG_PHOTOMETRIC
      | TAG_STRIP_OFFSETS
      | TAG_SAMPLES_PER_PIXEL
      | TAG_ROWS_PER_STRIP
      | TAG_STRIP_BYTE_COUNTS
      | TAG_PLANAR_CONFIGURATION
      | TAG_PREDICTOR
      | TAG_TILE_WIDTH
      | TAG_TILE_LENGTH
      | TAG_TILE_OFFSETS
      | TAG_TILE_BYTE_COUNTS
      | TAG_SAMPLE_FORMAT
      | TAG_JPEG_TABLES
      | TAG_MODEL_PIXEL_SCALE
      | TAG_MODEL_TIEPOINT
      | TAG_MODEL_TRANSFORMATION
      | TAG_GEO_KEY_DIRECTORY
      | TAG_GDAL_NODATA) {
      self.need(start, bytes)
      entries[tag] = { t: ty, count: count.to_int(), at: start.to_int(), }
    }
  }
  let next = self.uint(pos + count_size + n * entry_size, inline)
  (self.image(entries, pos), next)
}

///|
/// The image an IFD's `entries` describe, checked as far as reading its blocks needs.
fn Tiff::image(
  self : Tiff,
  entries : Map[Int32, Entry],
  pos : Int32,
) -> Image raise TiffError {
  let all = (tag : Int32) => {
    match entries.get(tag) {
      Some(e) => self.list(e)
      None => []
    }
  }
  let one = (tag : Int32, default : Double) => {
    match entries.get(tag) {
      Some(e) if e.count > 0 => self.value(e.t, e.at)
      _ => default
    }
  }
  let fail = (m : String) => raise Invalid(pos, m)
  let width = one(TAG_IMAGE_WIDTH, 0)
  let height = one(TAG_IMAGE_LENGTH, 0)
  if !(width >= 1.0 &&
    height >= 1.0 &&
    width < 2147483648.0 &&
    height < 2147483648.0) {
    fail("invalid image size")
  }
  let width = width.to_int()
  let height = height.to_int()
  let samples = one(TAG_SAMPLES_PER_PIXEL, 1).to_int()
  if samples < 1 || samples > 64 {
    fail("invalid samples per pixel")
  }
  let bits = all(TAG_BITS_PER_SAMPLE).map(x => x.to_int())
  let formats = all(TAG_SAMPLE_FORMAT).map(x => x.to_int())
  for i, n in bits {
    if i < samples && (n < 1 || n > 64) {
      fail("invalid bits per sample")
    }
  }
  // geotiff reads a sample without a SampleFormat as unsigned, without BitsPerSample as 0 bits.
  let bits = Array::makei(samples, i => {
    if i < bits.length() {
      bits[i]
    } else {
      0
    }
  })
  let formats = Array::makei(samples, i => {
    if i < formats.length() {
      formats[i]
    } else {
      1
    }
  })
  let planar = one(TAG_PLANAR_CONFIGURATION, 1).to_int()
  if planar != 1 && planar != 2 {
    fail("invalid planar configuration")
  }
  let tiled = !entries.contains(TAG_STRIP_OFFSETS)
  let (block_width, block_height) = if tiled {
    (one(TAG_TILE_WIDTH, 0), one(TAG_TILE_LENGTH, 0))
  } else {
    let rows = one(TAG_ROWS_PER_STRIP, 0)
    (
      width.to_double(),
      if rows > 0.0 {
        @cmp.minimum(rows, height.to_double())
      } else {
        height.to_double()
      },
    )
  }
  if !(block_width >= 1.0 && block_height >= 1.0) ||
    block_width * block_height > 64.0 * 1024.0 * 1024.0 ||
    block_width > width.to_double() + max_tile_overhang ||
    block_height > height.to_double() + max_tile_overhang {
    fail("invalid tile size")
  }
  let mut pixel = 0
  for n in bits {
    let bytes = (n + 7) / 8
    pixel = if planar == 2 { @cmp.maximum(pixel, bytes) } else { pixel + bytes }
  }
  if block_width.to_int().to_int64() *
    block_height.to_int().to_int64() *
    pixel.to_int64() >
    MAX_BLOCK_BYTES.to_int64() {
    fail("a block too large")
  }
  let offsets = all(if tiled { TAG_TILE_OFFSETS } else { TAG_STRIP_OFFSETS })
  let counts = all(
    if tiled {
      TAG_TILE_BYTE_COUNTS
    } else {
      TAG_STRIP_BYTE_COUNTS
    },
  )
  let tables = match entries.get(TAG_JPEG_TABLES) {
    Some(e) => {
      self.charge(e)
      Some(Bytes::makei(e.count, i => self.b[e.at + i]))
    }
    None => None
  }
  let nodata = match entries.get(TAG_GDAL_NODATA) {
    Some(e) => {
      self.charge(e)
      let sb = StringBuilder()
      for i in 0..<e.count {
        sb.write_char(self.b[e.at + i].to_int().unsafe_to_char())
      }
      Some(sb.to_string())
    }
    None => None
  }
  let (epsg, raster_type) = geo_keys(all(TAG_GEO_KEY_DIRECTORY))
  let image : Image = {
    width,
    height,
    tiled,
    block_width: block_width.to_int(),
    block_height: block_height.to_int(),
    samples,
    bits,
    formats,
    planar,
    compression: one(TAG_COMPRESSION, COMPRESSION_NONE.to_double()).to_int(),
    predictor: one(TAG_PREDICTOR, 1).to_int(),
    photometric: one(TAG_PHOTOMETRIC, -1).to_int(),
    subfile: one(TAG_NEW_SUBFILE_TYPE, 0).to_int(),
    old_subfile: one(TAG_SUBFILE_TYPE, 0).to_int(),
    offsets,
    counts,
    pixel_scale: all(TAG_MODEL_PIXEL_SCALE),
    tiepoint: all(TAG_MODEL_TIEPOINT),
    transform: all(TAG_MODEL_TRANSFORMATION),
    epsg,
    raster_type,
    nodata,
    jpeg_tables: tables,
  }
  let blocks = image.across().to_double() *
    image.down().to_double() *
    (if planar == 2 { samples } else { 1 }).to_double()
  if offsets.length().to_double() < blocks ||
    counts.length().to_double() < blocks {
    fail("fewer block offsets than blocks")
  }
  image
}

///|
/// The EPSG code and raster type of a GeoKeyDirectory's values: ProjectedCSTypeGeoKey (3072),
/// else GeographicTypeGeoKey (2048), when in 1 to 32766 (32767 is user-defined); 0 otherwise.
fn geo_keys(dir : Array[Double]) -> (Int32, Int32) {
  if dir.length() < 4 {
    return (0, 0)
  }
  let n = @cmp.minimum(dir[3].to_int(), (dir.length() - 4) / 4)
  let mut projected = 0
  let mut geographic = 0
  let mut raster = 0
  for k in 0..<n {
    let at = 4 + k * 4
    if dir[at + 1] != 0.0 {
      continue
    }
    let v = dir[at + 3].to_int()
    match dir[at].to_int() {
      3072 => projected = v
      2048 => geographic = v
      1025 => raster = v
      _ => ()
    }
  }
  let code = if projected >= 1 && projected <= 32766 {
    projected
  } else if geographic >= 1 && geographic <= 32766 && projected == 0 {
    geographic
  } else {
    0
  }
  (code, raster)
}
