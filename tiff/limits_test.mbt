///|
fn le16(a : Array[Byte], v : Int32) -> Unit {
  a.push(v.to_byte())
  a.push((v >> 8).to_byte())
}

///|
fn le32(a : Array[Byte], v : Int32) -> Unit {
  le16(a, v & 0xffff)
  le16(a, (v >> 16) & 0xffff)
}

///|
/// A little-endian TIFF of one IFD of `entries` (tag, type, count, value) and then `tail`.
fn ifd_tiff(
  entries : Array[(Int32, Int32, Int32, Int32)],
  tail : Array[Byte],
) -> Bytes {
  let a : Array[Byte] = [
    b'I', b'I', b'\x2a', b'\x00', b'\x08', b'\x00', b'\x00', b'\x00',
  ]
  le16(a, entries.length())
  for e in entries {
    le16(a, e.0)
    le16(a, e.1)
    le32(a, e.2)
    le32(a, e.3)
  }
  le32(a, 0)
  a.append(tail)
  Bytes::from_array(a)
}

///|
/// Where `ifd_tiff` puts its tail for `n` entries.
fn tail_at(n : Int32) -> Int32 {
  8 + 2 + n * 12 + 4
}

///|
/// The entries of a tiled image, its BitsPerSample entry given.
fn tiled(
  width : Int32,
  height : Int32,
  tile_width : Int32,
  tile_height : Int32,
  samples : Int32,
  bits : (Int32, Int32, Int32, Int32),
) -> Array[(Int32, Int32, Int32, Int32)] {
  [
    (256, 4, 1, width),
    (257, 4, 1, height),
    bits,
    (277, 3, 1, samples),
    (322, 4, 1, tile_width),
    (323, 4, 1, tile_height),
    (324, 4, 1, 0),
    (325, 4, 1, 0),
  ]
}

///|
fn read_error(b : Bytes) -> String {
  error_of(() => @tiff.read_tiff(b[:]) |> ignore)
}

///|
test "read_tiff refuses what is no TIFF or holds no image" {
  let need = try {
    @tiff.read_tiff(b"II"[:]) |> ignore
    0.0
  } catch {
    Truncated(n) => n
    _ => -1.0
  }
  assert_eq(need, 16)
  assert_eq(
    read_error(b"II\x2c\x00\x00\x00\x00\x00"),
    "malformed TIFF at 2: not a TIFF file",
  )
  assert_eq(
    read_error(b"II\x2a\x00\x00\x00\x00\x00"),
    "malformed TIFF at 4: no image directory",
  )
  assert_eq(
    read_error(b"II\x2a\x00\x08\x00\x00\x00\x01\x10"),
    "malformed TIFF at 8: too many entries",
  )
}

///|
test "read_tiff refuses tags and sizes out of range" {
  assert_true(
    read_error(strip_tiff([(33550, 12, @tiff.MAX_VALUES + 1, 0)])).has_suffix(
      "too many values",
    ),
  )
  assert_eq(
    read_error(strip_tiff([(277, 3, 1, 65)])),
    "malformed TIFF at 14: invalid samples per pixel",
  )
  assert_eq(
    read_error(strip_tiff([(284, 3, 1, 3)])),
    "malformed TIFF at 14: invalid planar configuration",
  )
  assert_eq(
    read_error(
      strip_tiff([(256, 4, 1, 65536), (257, 4, 1, 65536), (278, 4, 1, 65536)]),
    ),
    "malformed TIFF at 14: invalid tile size",
  )
  assert_eq(
    read_error(strip_tiff([(278, 3, 1, 1)])),
    "malformed TIFF at 14: fewer block offsets than blocks",
  )
}

///|
test "read_tiff refuses bits per sample out of range, not missing ones" {
  let tail : Array[Byte] = []
  le32(tail, -16)
  le32(tail, 8)
  let signed = tiled(64, 64, 64, 64, 2, (258, 9, 2, tail_at(8)))
  assert_eq(
    read_error(ifd_tiff(signed, tail)),
    "malformed TIFF at 8: invalid bits per sample",
  )
  assert_eq(
    read_error(strip_tiff([(258, 3, 1, 65)])),
    "malformed TIFF at 14: invalid bits per sample",
  )
  assert_eq(
    read_error(strip_tiff([(258, 3, 1, 0)])),
    "malformed TIFF at 14: invalid bits per sample",
  )
  let none = tiled(1, 1, 1, 1, 1, (317, 3, 1, 3))
  let (images, little) = @tiff.read_tiff(ifd_tiff(none, [])[:])
  assert_eq(
    error_of(() => {
      @tiff.Window::new(images[0], little, 0, 0, 1, 1, [0], 0) |> ignore
    }),
    "malformed TIFF at 0: unsupported data format/bitsPerSample",
  )
}

///|
test "blocks whose bytes pass the limit are refused, without wrapping" {
  let tail : Array[Byte] = []
  for _ in 0..<8 {
    le16(tail, 32)
  }
  let wide = tiled(8192, 8192, 8192, 8192, 8, (258, 3, 8, tail_at(8)))
  assert_eq(
    read_error(ifd_tiff(wide, tail)),
    "malformed TIFF at 8: a block too large",
  )
  let short : Array[Byte] = []
  for _ in 0..<32 {
    le16(short, 16)
  }
  let row = tiled(1 << 25, 1, 1 << 25, 1, 32, (258, 3, 32, tail_at(8)))
  assert_eq(
    read_error(ifd_tiff(row, short)),
    "malformed TIFF at 8: a block too large",
  )
  let fits = tiled(8192, 8192, 8192, 8192, 1, (258, 3, 1, 32))
  assert_true(@tiff.read_tiff(ifd_tiff(fits, [])[:]).0.length() == 1)
  let over = tiled(8192, 8192, 8192, 8192, 1, (258, 3, 1, 33))
  assert_eq(
    read_error(ifd_tiff(over, [])),
    "malformed TIFF at 8: a block too large",
  )
}

///|
test "images near 2^31 pixels count their blocks without wrapping" {
  let tail : Array[Byte] = []
  for _ in 0..<128 {
    le32(tail, 0)
  }
  let image = (width : Int32, height : Int32, tile : Int32, rows : Int32) => {
    let e = tiled(width, height, tile, rows, 1, (258, 3, 1, 8))
    e[6] = (324, 4, 64, tail_at(8))
    e[7] = (325, 4, 64, tail_at(8) + 256)
    @tiff.read_tiff(ifd_tiff(e, tail)[:]).0[0]
  }
  assert_eq(image(0x7fffffff, 1, 1 << 25, 1).across(), 64)
  assert_eq(image(1, 0x7fffffff, 1, 1 << 25).down(), 64)
  let strips = [
    (256, 4, 1, 1),
    (257, 4, 1, 0x7fffffff),
    (258, 3, 1, 8),
    (273, 4, 64, tail_at(6)),
    (278, 4, 1, 1 << 25),
    (279, 4, 64, tail_at(6) + 256),
  ]
  let img = @tiff.read_tiff(ifd_tiff(strips, tail)[:]).0[0]
  assert_eq(img.rows(62), 1 << 25)
  assert_eq(img.rows(63), (1 << 25) - 1)
  let tall = tiled(0x7fffffff, 1, 2, 1, 1, (258, 3, 1, 8))
  assert_eq(
    read_error(ifd_tiff(tall, [])),
    "malformed TIFF at 8: fewer block offsets than blocks",
  )
}

///|
test "a GeoKey directory's count is capped by its values" {
  let tail : Array[Byte] = []
  for v in [1, 1, 0, 0x7fffffff, 3072, 0, 1, 4326] {
    le32(tail, v)
  }
  let e = tiled(1, 1, 1, 1, 1, (258, 3, 1, 8))
  e.push((34735, 4, 8, tail_at(9)))
  let image = @tiff.read_tiff(ifd_tiff(e, tail)[:]).0[0]
  assert_eq(image.epsg, 4326)
  let short = tiled(1, 1, 1, 1, 1, (258, 3, 1, 8))
  short.push((34735, 4, 4, tail_at(9)))
  assert_eq(@tiff.read_tiff(ifd_tiff(short, tail)[:]).0[0].epsg, 0)
}

///|
/// The bits of `codes`, 9 each, in bytes.
fn nine_bit_codes(codes : Array[Int32]) -> Bytes {
  let bits = []
  for c in codes {
    for k in 0..<9 {
      bits.push((c >> (8 - k)) & 1)
    }
  }
  while bits.length() % 8 != 0 {
    bits.push(0)
  }
  Bytes::makei(bits.length() / 8, i => {
    let mut v = 0
    for k in 0..<8 {
      v = (v << 1) | bits[i * 8 + k]
    }
    v.to_byte()
  })
}

///|
test "lzw takes empty data and repeated clears and refuses an unknown first code" {
  assert_eq(arr(@tiff.lzw(b""[:], 10)), [])
  assert_eq(arr(@tiff.lzw(nine_bit_codes([256, 256, 256, 97, 257])[:], 10)), [
    b'a',
  ])
  assert_eq(
    error_of(() => @tiff.lzw(nine_bit_codes([300, 257])[:], 10) |> ignore),
    "malformed TIFF at 1: invalid LZW code 300",
  )
}

///|
test "unpack_bits refuses blocks shorter than their rows or past the limit" {
  assert_eq(
    error_of(() => {
      @tiff.unpack_bits(FixedArray::from_array([b'\x00']), 12, 2, 1, 1)
      |> ignore
    }),
    "malformed TIFF at 0: a block shorter than its rows",
  )
  assert_eq(
    error_of(() => {
      @tiff.unpack_bits(FixedArray::from_array([]), 1, 1 << 15, 1 << 15, 1)
      |> ignore
    }),
    "malformed TIFF at 0: a block too large",
  )
}

///|
test "unpredict refuses rows past a block, however wide" {
  let b = FixedArray::make(64, b'\x00')
  assert_eq(
    error_of(() => @tiff.unpredict(b, 2, 1 << 25, 1, 32, 2, true)),
    "malformed TIFF at 0: a block shorter than its rows",
  )
  assert_eq(error_of(() => @tiff.unpredict(b, 3, 4, 1, 1, 0, true)), "")
}

///|
test "band_bytes has no size for bits below one" {
  assert_eq(@tiff.band_bytes(1, 0), 0)
  assert_eq(@tiff.band_bytes(1, -1), 0)
}

///|
test "Window refuses windows, formats and compressions it cannot read" {
  let (images, little) = @tiff.read_tiff(strip_tiff([])[:])
  let image = images[0]
  assert_eq(
    error_of(() => {
      @tiff.Window::new(image, little, 1, 0, 0, 1, [0], 0) |> ignore
    }),
    "malformed TIFF at 0: invalid window",
  )
  assert_eq(
    error_of(() => {
      @tiff.Window::new(image, little, 0, 0, 20000, 20000, [0], 0) |> ignore
    }),
    "malformed TIFF at 0: a window too large",
  )
  assert_eq(
    error_of(() => {
      @tiff.Window::new(
        image,
        little,
        -2147483648,
        -2147483648,
        2147483647,
        2147483647,
        [0],
        0,
      )
      |> ignore
    }),
    "malformed TIFF at 0: a window too large",
  )
  let (floats, _) = @tiff.read_tiff(strip_tiff([(339, 3, 1, 3)])[:])
  assert_eq(
    error_of(() => {
      @tiff.Window::new(floats[0], little, 0, 0, 1, 1, [0], 0) |> ignore
    }),
    "malformed TIFF at 0: unsupported data format/bitsPerSample",
  )
  let block = (extra : Array[(Int32, Int32, Int32, Int32)]) => {
    error_of(() => {
      let (images, little) = @tiff.read_tiff(strip_tiff(extra)[:])
      let w = @tiff.Window::new(images[0], little, 0, 0, 1, 1, [0], 0)
      w.block(0, b"\x00\x00\x00\x00"[:], false)
    })
  }
  assert_eq(
    block([(259, 3, 1, 8)]),
    "malformed TIFF at 0: unsupported compression 8",
  )
  assert_eq(
    block([(258, 3, 1, 12), (317, 3, 1, 2)]),
    "malformed TIFF at 0: a predictor needs samples of whole bytes, all of one size",
  )
  assert_eq(
    block([(258, 3, 1, 64), (339, 3, 1, 3), (317, 3, 1, 2)]),
    "malformed TIFF at 0: predictor 2 with 64-bit samples",
  )
}
