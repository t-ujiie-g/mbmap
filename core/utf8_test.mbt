///|
fn same_as_core(bytes : Bytes) -> Bool {
  @core.utf8_lossy(bytes[:]) == @utf8.decode_lossy(bytes[:])
}

///|
test "utf8_lossy decodes text, keeps a BOM and replaces malformed subparts" {
  assert_eq(@core.utf8_lossy(b"abc"[:]), "abc")
  assert_eq(@core.utf8_lossy(@utf8.encode("東京駅🚉")[:]), "東京駅🚉")
  assert_eq(@core.utf8_lossy(b"\xef\xbb\xbfa"[:]), "\u{feff}a")
  // A truncated sequence is one U+FFFD; a bad continuation byte starts anew.
  assert_eq(@core.utf8_lossy(b"\xe6\x9d"[:]), "\u{fffd}")
  assert_eq(@core.utf8_lossy(b"\xe6\x41"[:]), "\u{fffd}A")
  assert_eq(@core.utf8_lossy(b"\xed\xa0\x80"[:]), "\u{fffd}\u{fffd}\u{fffd}")
  assert_eq(
    @core.utf8_lossy(b"\xf4\x90\x80\x80"[:]),
    "\u{fffd}\u{fffd}\u{fffd}\u{fffd}",
  )
  assert_eq(@core.utf8_lossy(b""[:]), "")
}

///|
test "utf8_lossy matches @utf8.decode_lossy on every two-byte input and on sequences" {
  for a in 0..<256 {
    for b in 0..<256 {
      assert_true(same_as_core(Bytes::from_array([a.to_byte(), b.to_byte()])))
    }
  }
  let edges = [
    0x00, 0x41, 0x7f, 0x80, 0x8f, 0x90, 0x9f, 0xa0, 0xbf, 0xc0, 0xc1, 0xc2, 0xdf,
    0xe0, 0xe1, 0xec, 0xed, 0xee, 0xef, 0xf0, 0xf1, 0xf3, 0xf4, 0xf5, 0xff,
  ]
  for a in edges {
    for b in edges {
      for c in edges {
        for d in [0x41, 0x80, 0xbf, 0xc2] {
          assert_true(
            same_as_core(Bytes::from_array([a, b, c, d].map(x => x.to_byte()))),
          )
        }
      }
    }
  }
  // Pseudo-random runs of mostly valid text with stray bytes.
  let mut seed = 12345
  for _ in 0..<2000 {
    let bytes = []
    for _ in 0..<12 {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff
      bytes.push(((seed >> 8) & 0xff).to_byte())
    }
    assert_true(same_as_core(Bytes::from_array(bytes)))
  }
}
