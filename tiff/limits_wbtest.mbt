///|
/// Two IFDs of a 1 x 1 strip image, the second also a `34735` of 4 LONGs at 8.
fn two_images() -> Bytes {
  let a : Array[Byte] = [
    b'I', b'I', b'\x2a', b'\x00', b'\x18', b'\x00', b'\x00', b'\x00',
  ]
  let le = (v : Int32, n : Int32) => {
    for k in 0..<n {
      a.push((v >> (k * 8)).to_byte())
    }
  }
  for _ in 0..<4 {
    le(0, 4)
  }
  let directory = (next : Int32, extra : Bool) => {
    le(if extra { 6 } else { 5 }, 2)
    let entries = [
      (256, 3, 1, 1),
      (257, 3, 1, 1),
      (258, 3, 1, 8),
      (273, 4, 1, 8),
      (279, 4, 1, 1),
    ]
    if extra {
      entries.push((34735, 4, 4, 8))
    }
    for e in entries {
      le(e.0, 2)
      le(e.1, 2)
      le(e.2, 4)
      le(e.3, 4)
    }
    le(next, 4)
  }
  directory(0x18 + 2 + 5 * 12 + 4, false)
  directory(0, true)
  Bytes::from_array(a)
}

///|
test "values read as lists count over all of a file's IFDs" {
  assert_eq(read_images(two_images()[:], 10).0.length(), 2)
  let e = try read_images(two_images()[:], 9) catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(e, "malformed TIFF at 8: too many values in the file")
}

///|
test "geo_keys reads only the keys its directory holds" {
  assert_eq(geo_keys([1, 1, 0, 2147483647]), (0, 0))
  assert_eq(geo_keys([1, 1, 0, 9, 2048, 0, 1, 4612, 1025, 0, 1]), (4612, 0))
  assert_eq(geo_keys([1, 1, 0, -1, 2048, 0, 1, 4612]), (0, 0))
}
