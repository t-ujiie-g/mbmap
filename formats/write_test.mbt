///|
fn int_text(x : Double) -> String {
  x.to_int().to_string()
}

///|
/// A point (a "x,y", n 1), a polygon with a hole (n 2, no a) and a row without geometry.
fn sample() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  b.point(1, 2)
  b.end_ring()
  b.end_part()
  b.prop("a", Str("x,y"))
  b.prop("n", Num(1))
  b.end_feature(Point)
  for ring in [[0, 0, 4, 0, 4, 4, 0, 0], [1, 1, 1, 2, 2, 2, 1, 1]] {
    for i in 0..<(ring.length() / 2) {
      b.point(ring[i * 2].to_double(), ring[i * 2 + 1].to_double())
    }
    b.end_ring()
  }
  b.end_part()
  b.prop("n", Num(2))
  b.end_feature(Polygon)
  b.prop("a", Bool(true))
  b.end_feature(NoGeometry)
  b.finish()
}

///|
test "write_csv writes WKT, quotes what needs it and leaves missing values empty" {
  let csv = @formats.write_csv(
    sample(),
    geometry=Wkt("wkt"),
    number_text=int_text,
  )
  assert_eq(
    csv, "a,n,wkt\r\n\"x,y\",1,POINT (1 2)\r\n,2,\"POLYGON ((0 0,4 0,4 4,0 0),(1 1,1 2,2 2,1 1))\"\r\ntrue,,",
  )
}

///|
test "write_csv writes points as two columns, a property's column in its place" {
  let b = @geom.TableBuilder::new()
  b.point(3, 4)
  b.end_ring()
  b.end_part()
  b.prop("latitude", Str("old"))
  b.prop("s", Str(" padded"))
  b.end_feature(Point)
  let csv = @formats.write_csv(
    b.finish(),
    delimiter=';',
    geometry=LonLat("longitude", "latitude"),
    number_text=int_text,
  )
  assert_eq(csv, "latitude;s;longitude\r\n4;\" padded\";3")
}

///|
test "write_csv refuses longitude and latitude for other geometries" {
  let e = try {
    @formats.write_csv(
      sample(),
      geometry=LonLat("x", "y"),
      number_text=int_text,
    )
    |> ignore
    ""
  } catch {
    Invalid(m, ..) => m
  }
  assert_eq(e, "a row is not a point: write the geometry as WKT")
}

///|
test "write_csv writes a row of no values without delimiters, and no rows as one" {
  let b = @geom.TableBuilder::new()
  b.prop("a", Num(1))
  b.end_feature(NoGeometry)
  b.end_feature(NoGeometry)
  let csv = @formats.write_csv(
    b.finish(),
    header=false,
    geometry=Omitted,
    number_text=int_text,
  )
  assert_eq(csv, "1\r\n")
  let empty = @formats.write_csv(
    @geom.Table::new(),
    geometry=Wkt("wkt"),
    number_text=int_text,
  )
  assert_eq(empty, "wkt\r\n")
}

///|
test "wkt_of writes every kind as betterknown does" {
  let b = @geom.TableBuilder::new()
  for k in 0..<2 {
    b.point(k.to_double(), 0)
    b.end_ring()
    b.end_part()
  }
  b.end_feature(MultiLineString)
  b.point(1, 1)
  b.point(2, 2)
  b.end_ring()
  b.end_part()
  b.end_feature(MultiPoint)
  for k in 0..<2 {
    b.point(k.to_double(), 0)
    b.point(k.to_double(), 1)
    b.point(0, 0)
    b.end_ring()
    b.end_part()
  }
  b.end_feature(MultiPolygon)
  b.end_feature(NoGeometry)
  let t = b.finish()
  assert_eq(
    @formats.wkt_of(t, 0, int_text),
    Some("MULTILINESTRING ((0 0),(1 0))"),
  )
  assert_eq(@formats.wkt_of(t, 1, int_text), Some("MULTIPOINT (1 1,2 2)"))
  assert_eq(
    @formats.wkt_of(t, 2, int_text),
    Some("MULTIPOLYGON (((0 0,0 1,0 0)),((1 0,1 1,0 0)))"),
  )
  assert_eq(@formats.wkt_of(t, 3, int_text), None)
}
