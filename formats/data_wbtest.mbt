///|
fn slow_of(b : Bytes) -> (Int32, Int32) -> Double {
  (s, e) => @core.strconv_number(b[s:e])
}

///|
fn limit_error(f : () -> @geom.Table raise ReadError) -> String {
  try f() catch {
    e => e.message()
  } noraise {
    _ => "read"
  }
}

///|
test "readers stop at their point and cell limits" {
  let wkt = b"POINT (1 2) MULTIPOINT (1 2, 3 4)"
  assert_eq(wkt_table(wkt[:], slow_of(wkt), 3, None).length(), 2)
  assert_eq(
    limit_error(() => wkt_table(wkt[:], slow_of(wkt), 2, None)),
    "malformed WKT at 32: too many points",
  )
  let wkb = b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\xf0\x3f\x00\x00\x00\x00\x00\x00\x00\x40"
  let twice = Bytes::from_array([..wkb, ..wkb])
  assert_eq(wkb_table(twice[:], 2, None).length(), 2)
  assert_eq(
    limit_error(() => wkb_table(twice[:], 1, None)),
    "malformed WKB at 42: too many points",
  )
  let csv = b"lat,lon\n1,2\n3,4\n"
  let options = CsvOptions::new()
  assert_eq(csv_table(csv[:], options, slow_of(csv), 2, 4, None).length(), 2)
  assert_eq(
    limit_error(() => csv_table(csv[:], options, slow_of(csv), 1, 4, None)),
    "malformed CSV at 16: too many points",
  )
  assert_eq(
    limit_error(() => csv_table(csv[:], options, slow_of(csv), 2, 3, None)),
    "malformed CSV at 16: too many property cells",
  )
  let wide = Bytes::from_array(
    [..b"a\n\"", ..FixedArray::make(MAX_CSV_FIELD_BYTES + 1, b'x'), ..b"\"\n"],
  )
  assert_eq(
    limit_error(() => csv_table(wide[:], options, slow_of(wide), 2, 4, None)),
    "malformed CSV at 3: a field longer than 16777216 bytes",
  )
}

///|
test "space_at knows every white space and line terminator of JavaScript" {
  let spaces = [
    "\t", "\n", "\u{b}", "\u{c}", "\r", " ", "\u{a0}", "\u{1680}", "\u{2000}", "\u{200a}",
    "\u{2028}", "\u{2029}", "\u{202f}", "\u{205f}", "\u{3000}", "\u{feff}",
  ]
  for s in spaces {
    let b = @utf8.encode(s)
    assert_eq(space_at(b[:], 0, b.length()), b.length())
    assert_eq(space_before(b[:], 0, b.length()), b.length())
  }
  for s in ["x", "\u{200b}", "\u{85}", "\u{3001}"] {
    let b = @utf8.encode(s + "x")
    assert_eq(space_at(b[:], 0, b.length()), 0)
  }
  // A space cut by the end of the range does not count.
  let cut = @utf8.encode("\u{3000}")
  assert_eq(space_at(cut[:], 0, 2), 0)
}

///|
test "read_decimal takes the fast path or hands the number to slow" {
  let calls = []
  let read = (text : Bytes, plus : Bool) => {
    read_decimal(text[:], 0, text.length(), plus, (s, e) => {
      calls.push((s, e))
      @core.strconv_number(text[s:e])
    })
  }
  assert_eq(read(b"12.5e-1,", false), (1.25, 7))
  assert_eq(read(b"1e", false), (1.0, 1))
  assert_eq(read(b"+1", false).1, 0)
  assert_eq(read(b"+1", true), (1.0, 2))
  assert_eq(read(b"-", false).1, 0)
  assert_eq(read(b".", false).1, 0)
  assert_eq(calls, [])
  assert_eq(read(b"0.1234567890123456789", false), (0.1234567890123456789, 21))
  assert_eq(read(b"1e23", false), (1.0e23, 4))
  assert_eq(calls, [(0, 21), (0, 4)])
  assert_eq(exact_ten(22), 1.0e22)
}

///|
test "typed_number trims white space and keeps to papaparse's range" {
  let typed = (s : String) => {
    let b = @utf8.encode(s)
    typed_number(b[:], 0, b.length(), slow_of(b))
  }
  assert_eq(typed("\u{3000} 42 \u{feff}"), Some(42.0))
  assert_eq(typed("9007199254740991"), Some(9007199254740991.0))
  assert_eq(typed("-9007199254740992"), None)
  assert_eq(typed("1 2"), None)
  assert_eq(typed(" "), None)
}

///|
test "shapefiles and TopoJSON stop at their point and cell limits" {
  // Two points, and a DBF of two records of one field.
  let shp = Bytes::from_array(
    [
      ..b"\x00\x00\x27\x0a",
      ..FixedArray::make(28, b'\x00'),
      ..b"\x01\x00\x00\x00",
      ..FixedArray::make(64, b'\x00'),
      ..b"\x00\x00\x00\x01\x00\x00\x00\x0a\x01\x00\x00\x00",
      ..FixedArray::make(16, b'\x00'),
      ..b"\x00\x00\x00\x02\x00\x00\x00\x0a\x01\x00\x00\x00",
      ..FixedArray::make(16, b'\x00'),
    ],
  )
  let dbf = Bytes::from_array(
    [
      ..b"\x03\x7c\x01\x01\x02\x00\x00\x00\x41\x00\x03\x00",
      ..FixedArray::make(20, b'\x00'),
      ..b"a\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00C\x00\x00\x00\x00\x02",
      ..FixedArray::make(15, b'\x00'),
      ..b"\x0d x1 x2",
    ],
  )
  let text = (_ : Int32, _ : Int32) => ""
  let read = (points : Int32, cells : Int32) => {
    shapefile_table(shp[:], Some(dbf[:]), text, slow_of(dbf), points, cells)
  }
  assert_eq(read(2, 2).length(), 2)
  assert_eq(
    limit_error(() => read(1, 2)),
    "malformed shapefile at 136: too many points",
  )
  assert_eq(limit_error(() => read(2, 1)), "malformed DBF at 0: too many cells")
  let topo = b"{\"type\":\"Topology\",\"arcs\":[[[0,0],[1,1]]],\"objects\":{\"o\":{\"type\":\"MultiLineString\",\"arcs\":[[0],[0]]}}}"
  let topo_read = (points : Int32) => {
    topojson_table(topo[:], None, slow_of(topo), points).0
  }
  assert_eq(topo_read(4).length(), 1)
  assert_true(limit_error(() => topo_read(3)).has_suffix("too many points"))
  assert_true(limit_error(() => topo_read(1)).has_suffix("too many points"))
}
