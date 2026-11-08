// The blobs below were encoded by Esri's LEPCC (commit 63a30e2, bench/lepcc/cli.cpp) and their
// values decoded by its C API.

///|
fn hex(s : String) -> FixedArray[Byte] {
  let out = FixedArray::make(s.length() / 2, b'\x00')
  fn digit(c : Int32) -> Int32 {
    if c >= '0'.to_int() && c <= '9'.to_int() {
      c - '0'.to_int()
    } else {
      c - 'a'.to_int() + 10
    }
  }

  for i in 0..<out.length() {
    let hi = digit(s.code_unit_at(2 * i).to_int())
    let lo = digit(s.code_unit_at(2 * i + 1).to_int())
    out[i] = (hi * 16 + lo).to_byte()
  }
  out
}

///|
let xyz_blob : String = "4c455043432020202020010049f5657882000000000000006666666666766140cdcccccccccc41400000000000002440ef1b5f7b6676614014799274cdcc4140000000000000284048afbc9af2d77a3e48afbc9af2d77a3e7b14ae47e17a843f03000000000000008001870200328101018102018001860300200380018703800c19"

///|
let rgb_raw_blob : String = "436c7573746572524742010014453e6729000000000000000300000000000000010203040506070809"

///|
let rgb_const_blob : String = "436c757374657252474201006629ce6323000000000000000a00000001000101c86432"

///|
let rgb_map_blob : String = "436c757374657252474201001d35963730000000000000000a00000002000100faf0e60a141e00010100010100010100"

///|
fn bytes_of(a : FixedArray[Byte]) -> Array[Int32] {
  Array::makei(a.length(), fn(i) { a[i].to_int() })
}

///|
fn ints_of(a : FixedArray[Int32]) -> Array[Int32] {
  Array::makei(a.length(), fn(i) { a[i] })
}

///|
test "decode_xyz gives the C API's doubles in the blob's order" {
  let b = hex(xyz_blob)
  guard @lepcc.decode_xyz(b, 0, b.length()) is Some(xyz) else {
    fail("refused")
  }
  let want = [139.7, 35.6, 10.0, 139.7, 35.6, 10.5, 139.70001, 35.60002, 12.0]
  assert_eq(xyz.length(), 9)
  for i, v in want {
    assert_eq(xyz[i], v)
  }
}

///|
test "decode_xyz reads a blob at an offset in a longer buffer" {
  let b = hex(xyz_blob)
  let padded = FixedArray::make(b.length() + 9, b'\x00')
  for i, v in b {
    padded[5 + i] = v
  }
  guard @lepcc.decode_xyz(padded, 5, b.length() + 4) is Some(xyz) else {
    fail("refused")
  }
  assert_eq(xyz[8], 12.0)
}

///|
test "decode_xyz refuses truncated blobs, other kinds and a wrong checksum" {
  let b = hex(xyz_blob)
  assert_true(@lepcc.decode_xyz(b, 0, b.length() - 1) is None)
  assert_true(@lepcc.decode_xyz(b, 0, 104) is None)
  assert_true(@lepcc.decode_xyz(b, 1, b.length()) is None)
  assert_true(@lepcc.decode_xyz(b, -1, 10) is None)
  let r = hex(rgb_raw_blob)
  assert_true(@lepcc.decode_xyz(r, 0, r.length()) is None)
  b[120] = (b[120].to_int() ^ 1).to_byte()
  assert_true(@lepcc.decode_xyz(b, 0, b.length()) is None)
}

///|
test "decode_rgb reads raw colors, a constant colormap and indexes" {
  let raw = hex(rgb_raw_blob)
  guard @lepcc.decode_rgb(raw, 0, raw.length()) is Some(rgb) else {
    fail("refused")
  }
  assert_eq(bytes_of(rgb), [1, 2, 3, 4, 5, 6, 7, 8, 9])
  let same = hex(rgb_const_blob)
  guard @lepcc.decode_rgb(same, 0, same.length()) is Some(rgb) else {
    fail("refused")
  }
  assert_eq(rgb.length(), 30)
  assert_eq(bytes_of(rgb)[27:].to_owned(), [200, 100, 50])
  let map = hex(rgb_map_blob)
  guard @lepcc.decode_rgb(map, 0, map.length()) is Some(rgb) else {
    fail("refused")
  }
  assert_eq(bytes_of(rgb)[:9].to_owned(), [
    250, 240, 230, 10, 20, 30, 10, 20, 30,
  ])
  assert_eq(bytes_of(rgb)[27:].to_owned(), [250, 240, 230])
}

///|
test "decode_rgb refuses truncated blobs and other kinds" {
  let raw = hex(rgb_raw_blob)
  assert_true(@lepcc.decode_rgb(raw, 0, raw.length() - 1) is None)
  let b = hex(xyz_blob)
  assert_true(@lepcc.decode_rgb(b, 0, b.length()) is None)
}

///|
test "decode_intensity reads bit-stuffed, 8-bit, 16-bit and upscaled values" {
  let cases = [
    (
      "496e74656e73697479200100aee83ca526000000000000000500000001000600860500813028",
      [0, 4, 8, 12, 40],
    ),
    (
      "496e74656e7369747920010002fa082d24000000000000000400000001000800c80300ff",
      [200, 3, 0, 255],
    ),
    (
      "496e74656e736974792001000042020526000000000000000300000001001000ffff01000700",
      [65535, 1, 7],
    ),
    (
      "496e74656e7369747920010003b4089023000000000000000300000005000100810307",
      [5, 5, 5],
    ),
    (
      "496e74656e7369747920010002a503bf220000000000000002000000010000008002",
      [0, 0],
    ),
  ]
  for c in cases {
    let b = hex(c.0)
    guard @lepcc.decode_intensity(b, 0, b.length()) is Some(values) else {
      fail("refused \{c.0}")
    }
    assert_eq(ints_of(values), c.1)
    assert_true(@lepcc.decode_intensity(b, 0, b.length() - 1) is None)
  }
  let r = hex(rgb_raw_blob)
  assert_true(@lepcc.decode_intensity(r, 0, r.length()) is None)
}

///|
test "blob_info names each blob's type and size" {
  let b = hex(xyz_blob)
  assert_true(@lepcc.blob_info(b, 0, b.length()) is Some((Xyz, 130)))
  assert_true(@lepcc.blob_info(b, 0, 24) is Some((Xyz, 130)))
  assert_true(@lepcc.blob_info(b, 0, 23) is None)
  let r = hex(rgb_raw_blob)
  assert_true(@lepcc.blob_info(r, 0, r.length()) is Some((Rgb, 41)))
  let i = hex(
    "496e74656e7369747920010003b4089023000000000000000300000005000100810307",
  )
  assert_true(@lepcc.blob_info(i, 0, i.length()) is Some((Intensity, 35)))
  let flags = hex("466c616742797465732001000000000030000000000000000000")
  assert_true(
    @lepcc.blob_info(flags, 0, flags.length()) is Some((FlagBytes, 48)),
  )
  let padded = FixedArray::make(b.length() + 1, b'\x00')
  for k, v in b {
    padded[k] = v
  }
  assert_true(@lepcc.blob_info(padded, 0, padded.length()) is None)
  assert_true(@lepcc.blob_info(padded, 1, 30) is None)
}

///|
test "decode lays the values out as docs/FORMATS.md LEPCC output" {
  let b = hex(xyz_blob)
  guard @lepcc.decode(Xyz, b, 0, b.length()) is Some(out) else {
    fail("refused")
  }
  assert_eq(out.length(), 8 + 72)
  assert_eq(bytes_of(out)[:8].to_owned(), [3, 0, 0, 0, 0, 0, 0, 0])
  // 12.0 is 0x4028000000000000.
  assert_eq(bytes_of(out)[72:].to_owned(), [0, 0, 0, 0, 0, 0, 0x28, 0x40])
  let r = hex(rgb_raw_blob)
  guard @lepcc.decode(Rgb, r, 0, r.length()) is Some(out) else {
    fail("refused")
  }
  assert_eq(bytes_of(out), [3, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
  let i = hex(
    "496e74656e736974792001000042020526000000000000000300000001001000ffff01000700",
  )
  guard @lepcc.decode(Intensity, i, 0, i.length()) is Some(out) else {
    fail("refused")
  }
  assert_eq(bytes_of(out), [3, 0, 0, 0, 0, 0, 0, 0, 255, 255, 1, 0, 7, 0])
  assert_true(@lepcc.decode(Rgb, b, 0, b.length()) is None)
  assert_true(@lepcc.decode(FlagBytes, b, 0, b.length()) is None)
}
