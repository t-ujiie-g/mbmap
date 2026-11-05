///|
/// flatgeobuf 4.6.1's `geojson.serialize` of a point (n 1.5, s "あ", b true) and a
/// triangle (n -2, s "", b false), without an index.
let two_features : Bytes = unhex_text(
  (
    #|6667620366676200940000001c00000018001c00040000000000000000000000
    #|0000080010000e0018000000180000001c000000000000000200000000000000
    #|00000000020000004c310000030000003c0000001c00000004000000d8ffffff
    #|00000002040000000100000062000000ecffffff0000000b0400000001000000
    #|7300000008000c0008000700080000000000000a04000000010000006e000000
    #|6c0000000c00000008000e000800040008000000400000001800000000001200
    #|0c00000008000000000000000000070012000000000000010400000002000000
    #|00000000007061400000000000a0414000000000160000000000000000000000
    #|f83f010003000000e381820200010000940000000c00000008000e0008000400
    #|080000006c00000018000000000012000c000000080000000000000000000700
    #|1200000000000003040000000800000000000000000000000000000000000000
    #|0000000000000040000000000000000000000000000000400000000000000040
    #|0000000000000000000000000000000013000000000000000000000000c00100
    #|0000000002000000
  ),
)

///|
fn unhex_text(s : String) -> Bytes {
  let ascii = Bytes::from_array(
    s.iter().map(c => c.to_int().to_byte()).to_array(),
  )
  unhex(ascii[:], 0, ascii.length()).unwrap()
}

///|
/// The message `f` raises, or None.
fn fgb_error(f : () -> @geom.Table raise ReadError) -> String? {
  try {
    f() |> ignore
    None
  } catch {
    Invalid(m, ..) => Some(m)
  }
}

///|
test "read_flatgeobuf reads flatgeobuf's own file" {
  let t = read_flatgeobuf(two_features[:])
  assert_eq(t.kinds, [Point, Polygon])
  assert_eq(t.ids, [Some(Num(0)), Some(Num(1))])
  assert_eq(t.coords, [139.5, 35.25, 0, 0, 2, 0, 2, 2, 0, 0])
  assert_eq(t.point_ends, [1, 5])
  assert_eq(
    t.column("n").map(c => c.values),
    Some([Some(Num(1.5)), Some(Num(-2))]),
  )
  assert_eq(
    t.column("s").map(c => c.values),
    Some([Some(Str("あ")), Some(Str(""))]),
  )
  assert_eq(
    t.column("b").map(c => c.values),
    Some([Some(Bool(true)), Some(Bool(false))]),
  )
}

///|
test "read_flatgeobuf numbers features by the ids given" {
  let t = read_flatgeobuf(two_features[:], ids=[5, 9])
  assert_eq(t.ids, [Some(Num(5)), Some(Num(9))])
  assert_eq(
    fgb_error(() => read_flatgeobuf(two_features[:], ids=[5])),
    Some("more features than ids"),
  )
}

///|
test "read_flatgeobuf refuses what is not a whole FlatGeobuf file" {
  let bad = two_features.to_array()
  bad[0] = b'g'
  assert_true(
    fgb_error(() => read_flatgeobuf(Bytes::from_array(bad)[:])) ==
    Some("not a FlatGeobuf file"),
  )
  let small = two_features.to_array()
  small[8] = b'\x00'
  small[9] = b'\x00'
  assert_true(
    fgb_error(() => read_flatgeobuf(Bytes::from_array(small)[:])) ==
    Some("invalid header size"),
  )
  assert_true(
    fgb_error(() => read_flatgeobuf(two_features[:two_features.length() - 8])) ==
    Some("feature past the end of the data"),
  )
  assert_eq(
    fgb_error(() => read_flatgeobuf(two_features[:3])),
    Some("not a FlatGeobuf file"),
  )
}

///|
test "read_flatgeobuf caps its points" {
  assert_true(
    fgb_error(() => fgb_table(two_features[:], None, 2)) ==
    Some("too many points"),
  )
}

///|
test "fgb_tree_bytes counts flatgeobuf's packed R-tree" {
  assert_eq(fgb_tree_bytes(1, 16, 1000), 80)
  assert_eq(fgb_tree_bytes(16, 16, 1000), 680)
  assert_eq(fgb_tree_bytes(17, 16, 1000), 800)
  assert_eq(fgb_tree_bytes(10, 1, 1000), (10 + 5 + 3 + 2 + 1) * 40)
  assert_eq(fgb_tree_bytes(0, 16, 1000), 0)
  assert_eq(fgb_tree_bytes(17, 16, 799), -1)
  assert_eq(fgb_tree_bytes(1L << 40, 16, 0x7fffffff), -1)
}

///|
test "base64 pads as RFC 4648 does" {
  assert_eq(base64(b""[:]), "")
  assert_eq(base64(b"f"[:]), "Zg==")
  assert_eq(base64(b"fo"[:]), "Zm8=")
  assert_eq(base64(b"foo"[:]), "Zm9v")
  assert_eq(base64(b"\xfb\xff"[:]), "+/8=")
}

///|
fn fgb_over(b : Bytes, names : Array[String], types : Array[Int32]) -> Fgb {
  {
    b: b[:],
    base: 0,
    error: None,
    names,
    types,
    shapes: Shapes::new(),
    props: [],
    max_points: 10,
    used: 0,
  }
}

///|
test "Fgb::properties reads each column type and refuses others" {
  let p = fgb_over(
    b"\x00\x00\xff\x01\x00\xfe\xff\x02\x00\x02\x00\x00\x00\xc3\xa9",
    ["byte", "short", "text"],
    [0, 3, 11],
  )
  p.properties(0, 15)
  assert_eq(p.error, None)
  assert_eq(p.props, [
    ("byte", Num(-1)),
    ("short", Num(-2)),
    ("text", Str("é")),
  ])
  let q = fgb_over(b"\x01\x00\x00", ["a"], [5])
  q.properties(0, 3)
  assert_true(q.error is Some((0, "a property of no column")))
  let r = fgb_over(b"\x00\x00\x00", ["a"], [99])
  r.properties(0, 3)
  assert_true(r.error is Some((2, "unknown column type 99")))
  let s = fgb_over(b"\x00\x00\x01\x00", ["a"], [5])
  s.properties(0, 4)
  assert_true(s.error is Some((2, "offset past the end of the data")))
  let t = fgb_over(b"\x00\x00\x09\x00\x00\x00ab", ["a"], [11])
  t.properties(0, 8)
  assert_true(t.error is Some((2, "a value past the end of the data")))
}

///|
test "Fgb::geometry refuses curves and deep collections" {
  let p = fgb_over(b"", [], [])
  p.geometry(0, 8, 0)
  assert_true(p.error is Some((0, "unsupported geometry type 8")))
  let q = fgb_over(b"", [], [])
  q.geometry(0, 7, MAX_GEOMETRY_DEPTH + 1)
  assert_true(q.error is Some((0, "collections nested too deep")))
}

///|
test "Fgb::text drops a leading BOM as TextDecoder does" {
  let p = fgb_over(b"\xef\xbb\xbfab", [], [])
  assert_eq(p.text(0, 5), "ab")
  assert_eq(p.text(1, 4), "\u{fffd}\u{fffd}ab")
}
