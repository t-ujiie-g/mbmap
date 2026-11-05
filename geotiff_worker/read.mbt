///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// The last file read: its images and byte order; the window being read; how many
/// bytes the last `parse` needed when the input ended too soon.
let images : Array[@tiff.Image] = []

///|
let little : Ref[Bool] = Ref(true)

///|
let window : Ref[@tiff.Window?] = Ref(None)

///|
let needed : Ref[Double] = Ref(0)

///|
/// Reads the image directories of the TIFF whose first bytes are the input and
/// writes them as docs/FORMATS.md "GeoTIFF images" lays them out; returns their
/// length, minus an error message's, or -3 when `need` bytes are needed.
#export_name("parse")
pub fn parse() -> Int32 {
  images.clear()
  window.val = None
  let (read, le) = @tiff.read_tiff(@wasmio.input_bytes()[:]) catch {
    Truncated(n) => {
      needed.val = n
      return -3
    }
    e => return @wasmio.fail_with(e.message())
  }
  images.append(read)
  little.val = le
  @wasmio.clear_input()
  let w = @core.ByteWriter::new()
  w.u32(if le { 1 } else { 0 })
  w.u32(read.length())
  let doubles = (a : Array[Double]) => {
    w.u32(a.length())
    for x in a {
      w.f64(x)
    }
  }
  for img in read {
    for
      v in [
        img.width,
        img.height,
        if img.tiled {
          1
        } else {
          0
        },
        img.block_width,
        img.block_height,
        img.samples,
        img.planar,
        img.compression,
        img.predictor,
        img.photometric,
        img.subfile,
        img.old_subfile,
        img.epsg,
        img.raster_type,
      ] {
      w.u32(v)
    }
    for i in 0..<img.samples {
      w.u32(img.bits[i])
      w.u32(img.formats[i])
    }
    doubles(img.pixel_scale)
    doubles(img.tiepoint)
    doubles(img.transform)
    doubles(img.offsets)
    doubles(img.counts)
    match img.nodata {
      Some(s) => {
        w.u8(1)
        w.utf8(s)
      }
      None => w.u8(0)
    }
    match img.jpeg_tables {
      Some(t) => {
        w.u32(t.length())
        for x in t {
          w.u8(x.to_int())
        }
      }
      None => w.u32(-1)
    }
    w.pad4()
  }
  @wasmio.write_bytes(w.to_bytes()[:])
}

///|
/// How many bytes from the start of the file the last `parse` that returned -3 needed.
#export_name("need")
pub fn need() -> Double {
  needed.val
}

///|
/// Starts reading pixels `x0`, `y0` to `x1`, `y1` of image `image` of the last
/// file parsed, for the samples given as input u32s, `fill` as `Window::new`
/// takes it; returns 0, or minus an error message's length.
#export_name("window")
pub fn start_window(
  image : Int32,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
  fill : Double,
) -> Int32 {
  let input = @wasmio.input_bytes()
  guard image >= 0 && image < images.length() && input.length() % 4 == 0 else {
    return @wasmio.fail_with("invalid arguments")
  }
  let r = @core.ByteReader::new(input[:])
  let samples = Array::makei(input.length() / 4, _ => r.u32())
  window.val = Some(
    @tiff.Window::new(images[image], little.val, x0, y0, x1, y1, samples, fill) catch {
      e => return @wasmio.fail_with(e.message())
    },
  )
  @wasmio.clear_input()
  0
}

///|
/// Copies block `index` (the input bytes; `decoded` 1 if the host already
/// decompressed them) into the window; returns 0, or minus an error's length.
#export_name("block")
pub fn add_block(index : Int32, decoded : Int32) -> Int32 {
  guard window.val is Some(w) else { return @wasmio.fail_with("no window") }
  w.block(index, @wasmio.input_bytes()[:], decoded == 1) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
  0
}

///|
/// Fills block `index`'s pixels of the window with `value` (a block of no bytes).
#export_name("empty")
pub fn empty_block(index : Int32, value : Double) -> Int32 {
  guard window.val is Some(w) else { return @wasmio.fail_with("no window") }
  w.empty(index, value) catch {
    e => return @wasmio.fail_with(e.message())
  }
  0
}

///|
/// Writes the window's bands one after another, each padded to 8 bytes, and
/// returns their length.
#export_name("bands")
pub fn bands() -> Int32 {
  guard window.val is Some(w) else { return @wasmio.fail_with("no window") }
  let mut total = 0
  for band in w.bands {
    total += (band.length() + 7) / 8 * 8
  }
  let out = FixedArray::make(total, b'\x00')
  let mut at = 0
  for band in w.bands {
    band.blit_to(out, len=band.length(), dst_offset=at)
    at += (band.length() + 7) / 8 * 8
  }
  window.val = None
  // Nothing else holds `out`, so the reinterpretation cannot be observed mutating.
  @wasmio.write_bytes(out.unsafe_reinterpret_as_bytes()[:])
}
