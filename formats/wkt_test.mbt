///|
fn wkt(text : String) -> @geom.Table raise {
  @formats.read_wkt(@utf8.encode(text)[:])
}

///|
fn wkt_error(text : String) -> String {
  try wkt(text) catch {
    e =>
      match e {
        @formats.ReadError::Invalid(_) as e => e.message()
        _ => "other error"
      }
  } noraise {
    _ => "read"
  }
}

///|
test "every WKT type lands in the nested offsets" {
  let t = wkt(
    (
      #|POINT (1 2)
      #|LINESTRING (0 0, 1 1)
      #|POLYGON ((0 0, 4 0, 4 4, 0 0), (1 1, 2 1, 2 2, 1 1))
      #|MULTIPOINT (1 2, 3 4)
      #|MULTIPOINT ((5 6), (7 8))
      #|MULTILINESTRING ((0 0, 1 1), (2 2, 3 3))
      #|MULTIPOLYGON (((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5)))
    ),
  )
  assert_eq(t.kinds, [
    Point,
    LineString,
    Polygon,
    MultiPoint,
    MultiPoint,
    MultiLineString,
    MultiPolygon,
  ])
  assert_eq(coords_of(t, 0), [[[1.0, 2.0]]])
  assert_eq(coords_of(t, 1), [[[0.0, 0.0, 1.0, 1.0]]])
  assert_eq(coords_of(t, 2)[0].length(), 2)
  assert_eq(coords_of(t, 3), [[[1.0, 2.0, 3.0, 4.0]]])
  assert_eq(coords_of(t, 4), [[[5.0, 6.0, 7.0, 8.0]]])
  assert_eq(coords_of(t, 5), [[[0.0, 0.0, 1.0, 1.0]], [[2.0, 2.0, 3.0, 3.0]]])
  assert_eq(coords_of(t, 6).map(p => p.length()), [1, 1])
  assert_eq(coords_of(t, 6)[1][0][0:2].to_owned(), [5.0, 5.0])
}

///|
test "WKT keywords in any case, dimensions attached or apart, Z and M dropped" {
  let t = wkt(
    "point z (1 2 3) PointZM(4 5 6 7) LINESTRING M (0 0 9, 1 1 9) POINT(1 2 3)",
  )
  assert_eq(t.kinds, [Point, Point, LineString, Point])
  assert_eq(t.coords, [1.0, 2.0, 4.0, 5.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0])
}

///|
test "EMPTY geometries make rows without geometry; collections are flattened" {
  let t = wkt(
    (
      #|POINT EMPTY
      #|GEOMETRYCOLLECTION (POINT (1 2), GEOMETRYCOLLECTION (LINESTRING (0 0, 1 1)), POINT EMPTY)
      #|GEOMETRYCOLLECTION EMPTY
      #|POLYGON Z EMPTY
    ),
  )
  assert_eq(t.kinds, [NoGeometry, Point, LineString, NoGeometry, NoGeometry])
  assert_eq(t.coords, [1.0, 2.0, 0.0, 0.0, 1.0, 1.0])
}

///|
test "EWKT gives each row its SRID, 0 without one" {
  let srids = []
  let t = @formats.read_wkt(
    b"SRID=6677;GEOMETRYCOLLECTION(POINT(1 2),POINT(3 4)) srid=0;POINT(1 2) POINT(5 6) SRID=4326;POINT(7 8)",
    srids~,
  )
  assert_eq(t.length(), 5)
  assert_eq(srids, [6677, 6677, 0, 0, 4326])
  assert_eq(wkt_error("SRID=;POINT(1 2)"), "malformed WKT at 5: invalid SRID")
  assert_eq(
    wkt_error("SRID=1234567890;POINT(1 2)"),
    "malformed WKT at 14: expected ';'",
  )
}

///|
test "WKT numbers: signs, exponents, points on either side, long ones" {
  let t = wkt("POINT (+1.5e2 -.25) POINT (1. 0.12345678901234567)")
  assert_eq(t.coords, [150.0, -0.25, 1.0, 0.12345678901234567])
}

///|
test "malformed WKT is refused with where it went wrong" {
  assert_eq(wkt_error("POINT (1)"), "malformed WKT at 8: expected a number")
  assert_eq(wkt_error("POINT (1 2"), "malformed WKT at 10: expected ')'")
  assert_eq(wkt_error("POINT (a b)"), "malformed WKT at 7: expected a number")
  assert_eq(wkt_error("POINT (1x 2)"), "malformed WKT at 8: expected a number")
  assert_eq(
    wkt_error("POINT Z (1 2)"),
    "malformed WKT at 12: expected 3 ordinates",
  )
  assert_eq(wkt_error("POINT Z (1 2 3 4)"), "malformed WKT at 15: expected ')'")
  assert_eq(
    wkt_error("POINT (1e400 2)"),
    "malformed WKT at 14: coordinates must be finite",
  )
  assert_eq(
    wkt_error("CIRCLE (1 2)"),
    "malformed WKT at 0: expected a geometry type",
  )
  assert_eq(
    wkt_error("POINTY (1 2)"),
    "malformed WKT at 0: expected a geometry type",
  )
  assert_eq(wkt_error("POLYGON (1 2)"), "malformed WKT at 9: expected '('")
  assert_eq(
    wkt_error("MULTIPOINT (EMPTY)"),
    "malformed WKT at 12: expected a number",
  )
  assert_eq(
    wkt_error("POINT (1 2) )"),
    "malformed WKT at 12: expected a geometry type",
  )
  let deep = "GEOMETRYCOLLECTION (".repeat(40) + "POINT (1 2)" + ")".repeat(40)
  assert_eq(
    wkt_error(deep),
    "malformed WKT at 660: collections nested too deep",
  )
}

///|
test "empty WKT input makes an empty table" {
  assert_eq(wkt(" \n").length(), 0)
}
