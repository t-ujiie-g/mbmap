///|
fn put16(a : Array[Byte], v : Int32) -> Unit {
  a.push(v.to_byte())
  a.push((v >> 8).to_byte())
}

///|
fn put32(a : Array[Byte], v : Int32) -> Unit {
  put16(a, v & 0xffff)
  put16(a, (v >> 16) & 0xffff)
}

///|
fn set32(a : Array[Byte], at : Int32, v : Int32) -> Unit {
  for k in 0..<4 {
    a[at + k] = (v >> (k * 8)).to_byte()
  }
}

///|
fn put64(a : Array[Byte], v : Double) -> Unit {
  let bits = v.reinterpret_as_uint64()
  for k in 0..<8 {
    a.push((bits >> (k * 8)).to_byte())
  }
}

///|
fn no_number(_s : Int32, _e : Int32) -> Double {
  0.0
}

///|
/// A FlatGeobuf with a header of `count` features, an R-tree of `node_size` and,
/// from `columns` at header position 52, its columns vector.
fn fgb_with_header(
  count : Int32,
  node_size : Int32,
  columns : (Array[Byte]) -> Unit,
) -> Bytes {
  let a : Array[Byte] = []
  for c in fgb_magic {
    a.push(c)
  }
  for _ in 0..<5 {
    a.push(b'\x00')
  }
  put32(a, 0)
  let buffer = a.length()
  put32(a, 28)
  put16(a, 24)
  put16(a, 20)
  for field in 0..<10 {
    put16(a, if field < 7 { 0 } else { [4, 8, 16][field - 7] })
  }
  put32(a, 24)
  put32(a, 16)
  put32(a, count)
  put32(a, 0)
  put16(a, node_size)
  put16(a, 0)
  columns(a)
  set32(a, buffer - 4, a.length() - buffer)
  Bytes::from_array(a)
}

///|
/// `depth` collections of `k` parts all pointing at the next: a small file whose
/// geometry is a tree of `k` to the `depth` leaves.
fn fgb_aliased(depth : Int32, k : Int32) -> Bytes {
  let f : Array[Byte] = Array::make(4, b'\x00')
  put32(f, 0)
  put16(f, 6)
  put16(f, 8)
  put16(f, 4)
  put16(f, 0)
  let feature = f.length()
  put32(f, feature - 8)
  put32(f, 0)
  set32(f, 4, feature - 4)
  let vtable = f.length()
  put16(f, 20)
  put16(f, 12)
  for field in 0..<8 {
    put16(f, if field == 6 { 4 } else if field == 7 { 8 } else { 0 })
  }
  set32(f, feature + 4, f.length() - (feature + 4))
  for d in 0..<=depth {
    let g = f.length()
    put32(f, g - vtable)
    put32(f, if d == depth { 1 } else { 7 })
    put32(f, 0)
    let vector = f.length()
    set32(f, g + 8, vector - (g + 8))
    if d == depth {
      put32(f, 0)
    } else {
      put32(f, k)
      let next = vector + 4 + 4 * k
      for i in 0..<k {
        put32(f, next - (vector + 4 + 4 * i))
      }
    }
  }
  set32(f, 0, f.length() - 4)
  let head = fgb_with_header(1, 0, a => put32(a, 0)).to_array()
  head.append(f)
  Bytes::from_array(head)
}

///|
test "aliased FlatGeobuf parts cost no more visits than the file has bytes" {
  assert_eq(
    fgb_error(() => read_flatgeobuf(fgb_aliased(24, 2)[:])),
    Some("offsets reach the same data again and again"),
  )
  assert_eq(read_flatgeobuf(fgb_aliased(2, 2)[:]).length(), 1)
}

///|
test "Fgb::visit charges empty positions and stops at the first error" {
  let nan : Array[Byte] = []
  for _ in 0..<8 {
    put64(nan, @double.not_a_number)
  }
  let p = { ..fgb_over(Bytes::from_array(nan), [], []), max_visits: 3, }
  p.positions(0, 0, 4)
  assert_eq(p.visits, 4)
  assert_true(
    p.error is Some((48, "offsets reach the same data again and again")),
  )
  assert_eq(p.shapes.points(), 0)
  p.positions(0, 0, 4)
  assert_eq(p.visits, 5)
}

///|
/// A geometry table at 8 (vtable at 0) with ring ends `ends` and `points` x, y pairs.
fn fgb_geometry(ends : Array[Int32], points : Int32) -> Bytes {
  let a : Array[Byte] = []
  put16(a, 8)
  put16(a, 12)
  put16(a, 4)
  put16(a, 8)
  put32(a, 8)
  put32(a, 8)
  put32(a, 8 + 4 * ends.length())
  put32(a, ends.length())
  for e in ends {
    put32(a, e)
  }
  put32(a, points * 2)
  for i in 0..<(points * 2) {
    put64(a, i.to_double())
  }
  Bytes::from_array(a)
}

///|
test "Fgb::rings refuses ends that go back" {
  let ok = fgb_over(fgb_geometry([1, 3], 3), [], [])
  ok.rings(8, false)
  assert_eq(ok.error, None)
  assert_eq(ok.shapes.point_ends, [1, 3])
  let back = fgb_over(fgb_geometry([3, 1, 3], 3), [], [])
  back.rings(8, false)
  assert_true(back.error is Some((8, "ring ends out of order")))
  assert_eq(back.shapes.point_ends, [3])
  let past = fgb_over(fgb_geometry([9, -1], 3), [], [])
  past.rings(8, false)
  assert_true(past.error is Some((8, "ring ends out of order")))
}

///|
test "Fgb::indirect, text and string fail safely past the end" {
  let p = fgb_over(b"\x10\x00\x00\x00", [], [])
  assert_eq(p.indirect(0), -1)
  assert_true(p.error is Some((16, "offset past the end of the data")))
  let q = fgb_over(b"\xff\xff\xff\xff", [], [])
  assert_eq(q.indirect(0), -1)
  assert_true(q.error is Some((0, "offset past the end of the data")))
  let r = fgb_over(b"abc", [], [])
  assert_eq(r.text(1, 5), "")
  assert_true(r.error is Some((1, "offset past the end of the data")))
  let absent = fgb_over(b"\x04\x00\x04\x00\x04\x00\x00\x00", [], [])
  assert_eq(absent.string(4, 0), None)
  assert_eq(absent.error, None)
}

///|
test "Fgb::position leaves out empty points and refuses other non-finite values" {
  let a : Array[Byte] = []
  put64(a, @double.not_a_number)
  put64(a, @double.not_a_number)
  put64(a, @double.not_a_number)
  put64(a, 1)
  put64(a, @double.infinity)
  put64(a, 1)
  let b = Bytes::from_array(a)
  let p = fgb_over(b, [], [])
  p.position(0)
  assert_eq(p.error, None)
  assert_eq(p.shapes.points(), 0)
  p.position(16)
  assert_true(p.error is Some((16, "non-finite coordinate")))
  let q = fgb_over(b, [], [])
  q.position(32)
  assert_true(q.error is Some((32, "non-finite coordinate")))
}

///|
test "Fgb::geometry stops at a part past the end" {
  let a : Array[Byte] = []
  put16(a, 20)
  put16(a, 8)
  for field in 0..<8 {
    put16(a, if field == 7 { 4 } else { 0 })
  }
  put32(a, 20)
  put32(a, 4)
  put32(a, 2)
  put32(a, 0x7fffffff)
  put32(a, 0)
  let p = fgb_over(Bytes::from_array(a), [], [])
  p.geometry(20, 7, 0)
  assert_true(p.error is Some((_, "offset past the end of the data")))
  assert_eq(p.visits, 1)
}

///|
test "read_flatgeobuf refuses malformed headers" {
  let columns = (n : Int32, items : (Array[Byte]) -> Unit) => {
    fgb_with_header(0, 0, a => {
      put32(a, n)
      items(a)
    })
  }
  assert_eq(
    fgb_error(() => read_flatgeobuf(columns(1000, _ => ())[:])),
    Some("vector past the end of the data"),
  )
  assert_eq(
    fgb_error(() => read_flatgeobuf(columns(1, a => put32(a, 0x7fff))[:])),
    Some("offset past the end of the data"),
  )
  let nameless = columns(1, a => {
    put32(a, 8)
    put16(a, 4)
    put16(a, 4)
    put32(a, 4)
  })
  assert_eq(
    fgb_error(() => read_flatgeobuf(nameless[:])),
    Some("a column without a name"),
  )
  let wide = columns(MAX_FGB_COLUMNS + 1, a => {
    for _ in 0..<=MAX_FGB_COLUMNS {
      put32(a, 0)
    }
  })
  assert_eq(
    fgb_error(() => read_flatgeobuf(wide[:])),
    Some("more than 4096 columns"),
  )
  let no_index = fgb_with_header(5, 16, a => put32(a, 0))
  assert_eq(
    fgb_error(() => read_flatgeobuf(no_index[:])),
    Some("index past the end of the data"),
  )
}

///|
test "read_flatgeobuf stops at its cell limit" {
  assert_eq(fgb_table(two_features[:], None, 100, 6).length(), 2)
  assert_eq(
    fgb_error(() => fgb_table(two_features[:], None, 100, 5)),
    Some("too many property cells"),
  )
}

///|
test "Shapes::emit stops at the member past the cell limit" {
  let s = Shapes::new()
  for i in 0..<5 {
    s.point(i.to_double(), 0)
    s.end_ring()
    s.end_part()
    s.end_member(Point)
  }
  let props = [("a", @geom.Num(1)), ("b", @geom.Num(2))]
  let out = @geom.TableBuilder::new()
  s.emit(out, props, None, max_cells=3)
  assert_eq(out.table.length(), 2)
  assert_eq(out.cells(), 4)
}

///|
test "a CSV geometry of many members stops at the cell limit" {
  let csv = b"geom,a\n\"GEOMETRYCOLLECTION(POINT(0 0),POINT(1 1),POINT(2 2))\",1\n"
  let options = CsvOptions::new(geometry="geom")
  let read = (cells : Int32) => {
    csv_table(csv[:], options, slow_of(csv), 100, cells, None)
  }
  assert_eq(read(3).length(), 3)
  assert_true(limit_error(() => read(2)).has_suffix("too many property cells"))
}

///|
test "TopoJSON stops at its key and cell limits" {
  let sb = StringBuilder()
  sb.write_string(
    "{\"type\":\"Topology\",\"arcs\":[],\"objects\":{\"a\":{\"type\":\"GeometryCollection\",\"geometries\":[",
  )
  for i in 0..<=MAX_GEOJSON_KEYS {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"properties\":{\"k\{i}\":0}}")
  }
  sb.write_string("]}}}")
  let many = @utf8.encode(sb.to_string())
  let error = limit_error(() => {
    topojson_table(many[:], None, no_number, 100, @geom.MAX_TABLE_CELLS).0
  })
  assert_true(error.has_suffix("more than 4096 property keys"))
  let two = b"{\"type\":\"Topology\",\"arcs\":[],\"objects\":{\"a\":{\"type\":\"GeometryCollection\",\"geometries\":[{\"properties\":{\"a\":0}},{\"properties\":{\"b\":0}}]}}}"
  let read = (cells : Int32) => {
    topojson_table(two[:], None, slow_of(two), 100, cells).0
  }
  assert_eq(read(4).length(), 2)
  assert_true(limit_error(() => read(3)).has_suffix("property cells"))
}

///|
test "TopoJSON lines without arcs and with arcs that are no numbers are safe" {
  let none = b"{\"type\":\"Topology\",\"objects\":{\"a\":{\"type\":\"LineString\"}},\"arcs\":[]}"
  let (t, _) = read_topojson(none[:], None, slow_number=no_number)
  assert_eq(t.kinds, [NoGeometry])
  let text = b"{\"type\":\"Topology\",\"objects\":{\"a\":{\"type\":\"LineString\",\"arcs\":[\"x\"]}},\"arcs\":[]}"
  let error = limit_error(() => {
    read_topojson(text[:], None, slow_number=no_number).0
  })
  assert_true(error.has_suffix("invalid number"))
}

///|
test "a long chain of SRID prefixes takes no stack and the last one counts" {
  let sb = StringBuilder()
  for i in 0..<200000 {
    sb.write_string("SRID=\{i};")
  }
  sb.write_string("POINT(0 0)")
  let b = @utf8.encode(sb.to_string())
  let srids = []
  assert_eq(wkt_table(b[:], no_number, 10, Some(srids)).length(), 1)
  assert_eq(srids, [199999])
}

///|
/// The content of a polygon record of `rings` (x, y pairs).
fn polygon_record(rings : Array[Array[Double]]) -> Bytes {
  let a : Array[Byte] = []
  put32(a, 5)
  for _ in 0..<4 {
    put64(a, 0)
  }
  put32(a, rings.length())
  put32(a, rings.fold(init=0, (n, r) => n + r.length() / 2))
  let mut first = 0
  for r in rings {
    put32(a, first)
    first += r.length() / 2
  }
  for r in rings {
    for v in r {
      put64(a, v)
    }
  }
  Bytes::from_array(a)
}

///|
/// A square of side `s` at `x`, clockwise or not.
fn square(x : Double, s : Double, cw : Bool) -> Array[Double] {
  if cw {
    [x, 0, x, s, x + s, s, x + s, 0, x, 0]
  } else {
    [x, 0, x + s, 0, x + s, s, x, s, x, 0]
  }
}

///|
test "polygons take their holes in ring order, each once" {
  let c = polygon_record([
    square(0, 10, true),
    square(21, 1, false),
    square(20, 10, true),
    square(1, 1, false),
    square(23, 1, false),
  ])
  let out = @geom.TableBuilder::new()
  assert_true(shape(c[:], 0, out, Rings::new(1000), 100) is MultiPolygon)
  let t = out.table
  assert_eq(t.ring_ends, [2, 5])
  assert_eq(t.point_ends.map(e => t.coords[(e - 5) * 2]), [0, 1, 20, 21, 23])
}

///|
test "a shapefile of many one-point rings takes no comparisons" {
  let n = 30000
  let c = polygon_record(Array::makei(n, i => [i.to_double(), 0]))
  let rings = Rings::new(MAX_RING_STEPS)
  let out = @geom.TableBuilder::new()
  assert_true(shape(c[:], 0, out, rings, n) is MultiPolygon)
  assert_eq(rings.steps, 0)
  assert_eq(out.table.ring_ends.length(), n)
}

///|
test "telling holes from outer rings stops at its budget" {
  let c = polygon_record([square(0, 10, true), square(1, 1, false)])
  let rings = Rings::new(16)
  assert_true(shape(c[:], 0, @geom.TableBuilder::new(), rings, 100) is Polygon)
  assert_eq(rings.steps, 16)
  let e = try
    shape(c[:], 7, @geom.TableBuilder::new(), Rings::new(15), 100)
  catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(e, "malformed shapefile at 7: too many rings to tell apart")
}

///|
test "TopoJSON stops at its point limit" {
  let line = b"{\"type\":\"Topology\",\"arcs\":[[[0,0],[1,1]]],\"objects\":{\"a\":{\"type\":\"LineString\",\"arcs\":[0]}}}"
  let read = (points : Int32) => {
    topojson_table(line[:], None, slow_of(line), points, @geom.MAX_TABLE_CELLS).0
  }
  assert_eq(read(2).length(), 1)
  assert_true(limit_error(() => read(1)).has_suffix("too many points"))
  let lines = b"{\"type\":\"Topology\",\"arcs\":[[[0,0],[1,1]]],\"objects\":{\"a\":{\"type\":\"GeometryCollection\",\"geometries\":[{\"type\":\"LineString\",\"arcs\":[0]},{\"type\":\"LineString\",\"arcs\":[0]}]}}}"
  let read = (points : Int32) => {
    topojson_table(
      lines[:],
      None,
      slow_of(lines),
      points,
      @geom.MAX_TABLE_CELLS,
    ).0
  }
  assert_eq(read(4).length(), 2)
  assert_true(limit_error(() => read(3)).has_suffix("too many points"))
}

///|
test "a hole in an outer ring's box but out of the ring becomes an outer ring" {
  let c = polygon_record([[5, 0, 0, 5, 5, 10, 10, 5, 5, 0], square(0, 1, false)])
  let out = @geom.TableBuilder::new()
  assert_true(shape(c[:], 0, out, Rings::new(1000), 100) is MultiPolygon)
  assert_eq(out.table.ring_ends, [1, 2])
}

///|
test "Esri JSON stops at its point, key and cell limits" {
  let two = b"{\"features\":[{\"geometry\":{\"x\":1,\"y\":2}},{\"attributes\":{\"a\":1},\"geometry\":{\"points\":[[1,2],[3,4]]}}]}"
  let read = (points : Int32, cells : Int32) => {
    esri_json_table(two[:], slow_of(two), points, cells).0
  }
  assert_eq(read(3, 2).length(), 2)
  assert_true(limit_error(() => read(2, 2)).has_suffix("too many points"))
  assert_true(limit_error(() => read(3, 1)).has_suffix("property cells"))
  let sb = StringBuilder()
  sb.write_string("{\"features\":[{\"attributes\":{")
  for i in 0..<=MAX_GEOJSON_KEYS {
    sb.write_string(if i > 0 { ",\"k\{i}\":0" } else { "\"k0\":0" })
  }
  sb.write_string("}}]}")
  let many = @utf8.encode(sb.to_string())
  let error = limit_error(() => {
    esri_json_table(many[:], slow_of(many), 100, @geom.MAX_TABLE_CELLS).0
  })
  assert_true(error.has_suffix("more than 4096 property keys"))
}

///|
/// A PBF query result of points with `fields` field names, each feature
/// `attributes` sint values and the point (1, 2).
fn esri_points(fields : Int32, features : Int32, attributes : Int32) -> Bytes {
  let len = (w : @pbf.Writer, field : Int32, inner : @pbf.Writer) => {
    w.write_tag(field, @pbf.WIRE_LEN)
    w.write_bytes(inner.to_bytes()[:])
  }
  let result = @pbf.Writer::new()
  result.write_tag(7, @pbf.WIRE_VARINT)
  result.write_varint32(0)
  for i in 0..<fields {
    let f = @pbf.Writer::new()
    f.write_tag(1, @pbf.WIRE_LEN)
    f.write_string("k\{i}")
    len(result, 13, f)
  }
  for _ in 0..<features {
    let feature = @pbf.Writer::new()
    for _ in 0..<attributes {
      let v = @pbf.Writer::new()
      v.write_tag(4, @pbf.WIRE_VARINT)
      v.write_svarint32(1)
      len(feature, 1, v)
    }
    let g = @pbf.Writer::new()
    g.write_tag(3, @pbf.WIRE_VARINT)
    g.write_sint64(1L)
    g.write_tag(3, @pbf.WIRE_VARINT)
    g.write_sint64(2L)
    len(feature, 2, g)
    len(result, 15, feature)
  }
  let query = @pbf.Writer::new()
  len(query, 1, result)
  let top = @pbf.Writer::new()
  len(top, 2, query)
  top.to_bytes()
}

///|
test "Esri PBF stops at its point, key and cell limits" {
  let two = esri_points(1, 2, 1)
  let read = (points : Int32, cells : Int32) => {
    esri_pbf_table(two[:], points, cells).0
  }
  let t = read(2, 2)
  assert_eq((t.length(), t.coords), (2, [1.0, 2.0, 1.0, 2.0]))
  assert_true(limit_error(() => read(1, 2)).has_suffix("too many points"))
  assert_true(limit_error(() => read(2, 1)).has_suffix("property cells"))
  let many = esri_points(MAX_GEOJSON_KEYS + 1, 1, MAX_GEOJSON_KEYS + 1)
  let error = limit_error(() => {
    esri_pbf_table(many[:], 100, @geom.MAX_TABLE_CELLS).0
  })
  assert_true(error.has_suffix("more than 4096 property keys"))
}

///|
test "esri_rings stops past its step budget, and rings whose boxes are apart cost nothing" {
  let outer = [0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 10.0, 0.0, 0.0, 0.0]
  let hole = [2.0, 2.0, 4.0, 2.0, 4.0, 4.0, 2.0, 4.0, 2.0, 2.0]
  let far = [50.0, 50.0, 52.0, 50.0, 52.0, 52.0, 50.0, 52.0, 50.0, 50.0]
  let steps = Ref(0L)
  assert_true(esri_rings([outer, hole], Shapes::new(), steps))
  assert_true(steps.val > 0L)
  let spent = Ref(MAX_RING_STEPS)
  assert_false(esri_rings([outer, hole], Shapes::new(), spent))
  let apart = Ref(MAX_RING_STEPS)
  let s = Shapes::new()
  assert_true(esri_rings([outer, far], s, apart))
  assert_eq(apart.val, MAX_RING_STEPS)
  assert_eq(s.kinds, [MultiPolygon])
}
