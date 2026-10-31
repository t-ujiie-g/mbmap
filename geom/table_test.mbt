///|
test "the builder fills nested offsets and one column per key" {
  let b = @geom.TableBuilder::new()
  // A polygon with a hole.
  for p in [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 0.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  for p in [(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 1.0)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.prop("name", Str("a"))
  b.end_feature(Polygon, id=Some(Num(7.0)))
  // Two points, no properties beyond "k".
  b.point(5.0, 6.0)
  b.point(7.0, 8.0)
  b.end_ring()
  b.end_part()
  b.prop("k", Num(1.0))
  b.prop("k", Bool(true))
  b.end_feature(MultiPoint)
  let t = b.finish()
  assert_eq(t.length(), 2)
  assert_eq(t.kinds, [Polygon, MultiPoint])
  assert_eq(t.ids, [Some(Num(7.0)), None])
  assert_eq((t.parts(0), t.rings(0), t.points(1)), ((0, 1), (0, 2), (4, 8)))
  assert_eq((t.parts(1), t.rings(1), t.points(2)), ((1, 2), (2, 3), (8, 10)))
  assert_eq(t.coords[16:].to_owned(), [5.0, 6.0, 7.0, 8.0])
  assert_eq(t.column("name").unwrap().values, [Some(Str("a")), None])
  // A repeated key keeps its last value.
  assert_eq(t.column("k").unwrap().values, [None, Some(Bool(true))])
  assert_eq(t.column("missing").map(c => c.name), None)
}

///|
test "features without geometry keep their row; discard drops a partial one" {
  let b = @geom.TableBuilder::new()
  b.end_ring()
  b.end_part()
  b.prop("a", Null)
  b.end_feature(LineString)
  b.point(1.0, 2.0)
  b.point(3.0, 4.0)
  b.end_ring()
  b.prop("dropped", Num(1.0))
  b.discard_feature()
  b.point(9.0, 9.0)
  b.end_ring()
  b.end_part()
  b.end_feature(Point)
  let t = b.finish()
  assert_eq(t.kinds, [NoGeometry, Point])
  assert_eq((t.parts(0), t.parts(1)), ((0, 0), (0, 1)))
  assert_eq(t.coords, [9.0, 9.0])
  assert_eq(t.column("a").unwrap().values, [Some(Null), None])
  assert_eq(t.column("dropped").map(c => c.name), None)
}

///|
test "end_ring_at closes rings over coordinates appended directly" {
  let b = @geom.TableBuilder::new()
  b.table.coords.append([0.0, 0.0, 1.0, 0.0, 1.0, 1.0])
  b.end_ring_at(2)
  b.end_ring_at(2)
  b.end_ring_at(3)
  b.end_part()
  b.end_feature(MultiLineString)
  assert_eq((b.table.points(0), b.table.points(1)), ((0, 2), (2, 3)))
  assert_eq(b.table.rings(0), (0, 2))
}

///|
test "to_bytes and from_bytes round-trip a table; malformed bytes are None" {
  let b = @geom.TableBuilder::new()
  for p in [(0.0, 0.0), (1.5, 0.0), (1.5, -2.25)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.prop("name", Str("日本"))
  b.prop("n", Num(-0.5))
  b.end_feature(LineString)
  b.prop("t", Bool(true))
  b.prop("z", Null)
  b.end_feature(Point)
  let t = b.finish()
  let bytes = t.to_bytes()
  let u = @geom.Table::from_bytes(bytes[:]).unwrap()
  assert_eq(u.kinds, [LineString, NoGeometry])
  assert_eq(u.coords, t.coords)
  assert_eq((u.parts(0), u.rings(0), u.points(0)), ((0, 1), (0, 1), (0, 3)))
  for name in ["name", "n", "t", "z"] {
    assert_eq(u.column(name).unwrap().values, t.column(name).unwrap().values)
  }
  // Every truncation fails, as do a bad kind and ends that go backwards.
  for len in 0..<bytes.length() {
    assert_eq(@geom.Table::from_bytes(bytes[0:len]).map(t => t.length()), None)
  }
  let bad_kind = bytes.to_array()
  bad_kind[20] = b'\x09'
  assert_eq(
    @geom.Table::from_bytes(Bytes::from_array(bad_kind)[:]).map(t => t.length()),
    None,
  )
  let backwards = bytes.to_array()
  // The first feature's part end (after 20 bytes of counts and 4 of kinds).
  backwards[24] = b'\x07'
  assert_eq(
    @geom.Table::from_bytes(Bytes::from_array(backwards)[:]).map(t => t.length()),
    None,
  )
}
