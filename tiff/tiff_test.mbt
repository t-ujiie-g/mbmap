///|
fn arr(f : FixedArray[Byte]) -> Array[Byte] {
  Array::makei(f.length(), i => f[i])
}

///|
/// A little-endian TIFF of one 3 x 2 strip image of 8-bit samples 1 to 6, with
/// `extra` IFD entries (tag, type, count, value) added to its own.
fn strip_tiff(extra : Array[(Int32, Int32, Int32, Int32)]) -> Bytes {
  let entries = [
    (256, 3, 1, 3),
    (257, 3, 1, 2),
    (258, 3, 1, 8),
    (259, 3, 1, 1),
    (273, 4, 1, 8),
    (277, 3, 1, 1),
    (278, 3, 1, 2),
    (279, 4, 1, 6),
  ]
  entries.append(extra)
  tiff_of(entries)
}

///|
/// A little-endian TIFF of six data bytes and one IFD of `entries` (tag, type, count, value).
fn tiff_of(entries : Array[(Int32, Int32, Int32, Int32)]) -> Bytes {
  entries.sort_by_key(e => e.0)
  let b : Array[Byte] = [
    b'I', b'I', b'\x2a', b'\x00', b'\x0e', b'\x00', b'\x00', b'\x00',
  ]
  for v in 1..<=6 {
    b.push(v.to_byte())
  }
  let le = (v : Int32, n : Int32) => {
    for k in 0..<n {
      b.push((v >> (k * 8)).to_byte())
    }
  }
  le(entries.length(), 2)
  for e in entries {
    le(e.0, 2)
    le(e.1, 2)
    le(e.2, 4)
    le(e.3, 4)
  }
  le(0, 4)
  Bytes::from_array(b)
}

///|
fn error_of(f : () -> Unit raise @tiff.TiffError) -> String {
  try {
    f()
    ""
  } catch {
    e => e.message()
  }
}

///|
/// The directory of a 1 x 1 image in one `tile` x `tile` tile.
fn tile_entries(tile : Int32) -> Array[(Int32, Int32, Int32, Int32)] {
  [
    (256, 3, 1, 1),
    (257, 3, 1, 1),
    (258, 3, 1, 8),
    (259, 3, 1, 1),
    (277, 3, 1, 1),
    (322, 3, 1, tile),
    (323, 3, 1, tile),
    (324, 4, 1, 8),
    (325, 4, 1, 6),
  ]
}

///|
test "read_tiff refuses a tile far larger than its image" {
  let (images, _) = @tiff.read_tiff(tiff_of(tile_entries(4096))[:])
  assert_eq(images[0].block_width, 4096)
  assert_true(
    error_of(() => @tiff.read_tiff(tiff_of(tile_entries(4098))[:]) |> ignore).contains(
      "invalid tile size",
    ),
  )
}

///|
test "read_tiff reads a strip image's directory" {
  let (images, little) = @tiff.read_tiff(strip_tiff([])[:])
  assert_true(little)
  assert_eq(images.length(), 1)
  let img = images[0]
  assert_eq(
    (img.width, img.height, img.tiled, img.block_width, img.block_height),
    (3, 2, false, 3, 2),
  )
  assert_eq((img.across(), img.down(), img.rows(0)), (1, 1, 2))
  assert_eq((img.samples, img.bits, img.formats, img.planar), (1, [8], [1], 1))
  assert_eq((img.offsets, img.counts), ([8], [6]))
  assert_eq((img.sample_bytes(0), img.pixel_bytes(0)), (1, 1))
  assert_eq((img.epsg, img.nodata), (0, None))
}

///|
test "read_tiff reports what it needs past truncated bytes" {
  let t = strip_tiff([])
  let need = try {
    @tiff.read_tiff(t[:20]) |> ignore
    0.0
  } catch {
    Truncated(n) => n
    _ => -1.0
  }
  assert_true(need > 20.0 && need <= t.length().to_double())
  assert_eq(
    error_of(() => @tiff.read_tiff(b"GIF89a.."[:]) |> ignore),
    "malformed TIFF at 0: not a TIFF file",
  )
  assert_eq(
    error_of(() => {
      @tiff.read_tiff(
        b"II\x2b\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"[:],
      )
      |> ignore
    }),
    "malformed TIFF at 4: unsupported BigTIFF offset size",
  )
}

///|
test "read_tiff refuses directories that loop and images without size" {
  let t = strip_tiff([]).to_array()
  let at = t.length() - 4
  t[at] = b'\x0e'
  assert_eq(
    error_of(() => @tiff.read_tiff(Bytes::from_array(t)[:]) |> ignore),
    "malformed TIFF at 0: too many image directories, or a loop of them",
  )
  let none = strip_tiff([]).to_array()
  none[0x0e + 2 + 8] = b'\x00'
  assert_eq(
    error_of(() => @tiff.read_tiff(Bytes::from_array(none)[:]) |> ignore),
    "malformed TIFF at 14: invalid image size",
  )
}

///|
test "Window copies a block's pixels, filling what lies outside the image" {
  let (images, little) = @tiff.read_tiff(strip_tiff([])[:])
  let w = @tiff.Window::new(images[0], little, -1, 0, 3, 2, [0], 9)
  w.block(0, b"\x01\x02\x03\x04\x05\x06"[:], false)
  assert_eq(arr(w.bands[0]), [
    b'\x09', b'\x01', b'\x02', b'\x03', b'\x09', b'\x04', b'\x05', b'\x06',
  ])
  let e = @tiff.Window::new(images[0], little, 0, 0, 2, 1, [0], 0)
  e.empty(0, 300)
  assert_eq(arr(e.bands[0]), [b'\x2c', b'\x2c'])
  assert_eq(
    error_of(() => {
      @tiff.Window::new(images[0], little, 0, 0, 1, 1, [1], 0) |> ignore
    }),
    "malformed TIFF at 0: invalid sample index 1",
  )
  assert_eq(
    error_of(() => e.block(1, b""[:], false)),
    "malformed TIFF at 0: invalid block index 1",
  )
  assert_eq(
    error_of(() => e.block(0, b"\x01"[:], false)),
    "malformed TIFF at 1: a block shorter than its pixels",
  )
}

///|
test "Window reads 16-bit samples, predictor 2 and half floats" {
  let (images, little) = @tiff.read_tiff(
    strip_tiff([(258, 3, 1, 16), (317, 3, 1, 2), (279, 4, 1, 12)])[:],
  )
  let w = @tiff.Window::new(images[0], little, 0, 0, 3, 1, [0], 0)
  w.block(0, b"\x01\x00\x01\x00\xff\xff\x00\x00\x00\x00\x00\x00"[:], true)
  assert_eq(arr(w.bands[0]), [
    b'\x01', b'\x00', b'\x02', b'\x00', b'\x01', b'\x00',
  ])
  let (half, _) = @tiff.read_tiff(
    strip_tiff([(258, 3, 1, 16), (339, 3, 1, 3), (279, 4, 1, 12)])[:],
  )
  let h = @tiff.Window::new(half[0], true, 0, 0, 3, 1, [0], 0)
  h.block(0, b"\x00\x3c\x01\x00\x00\xfc\x00\x00\x00\x00\x00\x00"[:], true)
  let f = (i : Int32) => {
    let b = h.bands[0]
    Float::reinterpret_from_uint(
      b[i * 4].to_uint() |
      (b[i * 4 + 1].to_uint() << 8) |
      (b[i * 4 + 2].to_uint() << 16) |
      (b[i * 4 + 3].to_uint() << 24),
    ).to_double()
  }
  assert_eq((f(0), f(1), f(2)), (1.0, 5.960464477539063e-8, -@double.infinity))
}

///|
test "lzw decodes early-change codes and stops at the size asked" {
  // CLEAR, 'a', 'b', 258 ("ab"), EOI in 9 bits.
  let codes = [256, 97, 98, 258, 257]
  let bits = []
  for c in codes {
    for k in 0..<9 {
      bits.push((c >> (8 - k)) & 1)
    }
  }
  while bits.length() % 8 != 0 {
    bits.push(0)
  }
  let bytes = Bytes::makei(bits.length() / 8, i => {
    let mut v = 0
    for k in 0..<8 {
      v = (v << 1) | bits[i * 8 + k]
    }
    v.to_byte()
  })
  assert_eq(arr(@tiff.lzw(bytes[:], 100)), [b'a', b'b', b'a', b'b'])
  assert_eq(arr(@tiff.lzw(bytes[:], 3)), [b'a', b'b', b'a'])
  let bad = try {
    @tiff.lzw(b"\x80\x40\x80"[:], 10) |> ignore
    ""
  } catch {
    e => e.message()
  }
  assert_eq(bad, "malformed TIFF at 2: corrupted LZW code 258")
}

///|
test "packbits decodes literal and repeated runs, -128 doing nothing" {
  assert_eq(arr(@tiff.packbits(b"\x02abc\xfdz\x80\x00q"[:], 100)), [
    b'a', b'b', b'c', b'z', b'z', b'z', b'z', b'q',
  ])
  assert_eq(arr(@tiff.packbits(b"\xfdz"[:], 2)), [b'z', b'z'])
}

///|
test "unpredict undoes horizontal and floating-point differencing" {
  let b = FixedArray::from_array([
    b'\x01', b'\x01', b'\x01', b'\x05', b'\x01', b'\x01',
  ])
  @tiff.unpredict(b, 2, 3, 2, 1, 1, true)
  assert_eq(arr(b), [b'\x01', b'\x02', b'\x03', b'\x05', b'\x06', b'\x07'])
  // Two 16-bit samples 0x0102 and 0x0304 as byte planes (high bytes first), differenced.
  let f = FixedArray::from_array([b'\x01', b'\x02', b'\xff', b'\x02'])
  @tiff.unpredict(f, 3, 2, 1, 1, 2, false)
  assert_eq(arr(f), [b'\x02', b'\x01', b'\x04', b'\x03'])
  let short = FixedArray::from_array([b'\x01', b'\x02', b'\x03'])
  let e = try {
    @tiff.unpredict(short, 2, 2, 2, 1, 1, true)
    ""
  } catch {
    e => e.message()
  }
  assert_eq(e, "malformed TIFF at 2: a block shorter than its rows")
}

///|
test "unpack_bits reads samples narrower than a byte, rows on byte boundaries" {
  let out = @tiff.unpack_bits(
    FixedArray::from_array([b'\xa0', b'\x40']),
    1,
    3,
    2,
    1,
  )
  assert_eq(arr(out), [b'\x01', b'\x00', b'\x01', b'\x00', b'\x01', b'\x00'])
  let twelve = @tiff.unpack_bits(
    FixedArray::from_array([b'\xab', b'\xcd', b'\xef']),
    12,
    2,
    1,
    1,
  )
  assert_eq(arr(twelve), [b'\xbc', b'\x0a', b'\xef', b'\x0d'])
}

///|
test "band_bytes follows geotiff's typed arrays" {
  assert_eq(
    [
      (1, 1),
      (1, 8),
      (1, 12),
      (1, 16),
      (1, 24),
      (1, 32),
      (2, 8),
      (2, 12),
      (2, 32),
      (3, 16),
      (3, 32),
      (3, 64),
      (3, 8),
      (4, 8),
    ].map(p => @tiff.band_bytes(p.0, p.1)),
    [1, 1, 2, 2, 0, 4, 1, 0, 4, 4, 4, 8, 0, 0],
  )
}
