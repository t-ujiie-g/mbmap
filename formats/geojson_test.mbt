///|
fn read(text : String) -> @geom.Table raise {
  @formats.read_geojson(@utf8.encode(text)[:])
}

///|
fn coords_of(t : @geom.Table, f : Int32) -> Array[Array[Array[Double]]] {
  let (p0, p1) = t.parts(f)
  let out = []
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    let rings = []
    for r in r0..<r1 {
      let (a, b) = t.points(r)
      rings.push(t.coords[a * 2:b * 2].to_owned())
    }
    out.push(rings)
  }
  out
}

///|
test "every geometry kind lands in the nested offsets" {
  let t = read(
    (
      #|{"type": "FeatureCollection", "features": [
      #| {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1, 2, 99]}, "properties": null},
      #| {"type": "Feature", "geometry": {"type": "MultiPoint", "coordinates": [[1, 2], [3, 4]]}},
      #| {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[0, 0], [1, 1]]}},
      #| {"type": "Feature", "geometry": {"type": "MultiLineString", "coordinates": [[[0, 0], [1, 1]], [[2, 2], [3, 3]]]}},
      #| {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [2, 1], [2, 2], [1, 1]]]}},
      #| {"type": "Feature", "geometry": {"type": "MultiPolygon", "coordinates": [[[[0, 0], [1, 0], [1, 1], [0, 0]]], [[[5, 5], [6, 5], [6, 6], [5, 5]]]]}}
      #|]}
    ),
  )
  assert_eq(t.kinds, [
    Point,
    MultiPoint,
    LineString,
    MultiLineString,
    Polygon,
    MultiPolygon,
  ])
  assert_eq(coords_of(t, 0), [[[1.0, 2.0]]])
  assert_eq(coords_of(t, 1), [[[1.0, 2.0, 3.0, 4.0]]])
  assert_eq(coords_of(t, 3), [[[0.0, 0.0, 1.0, 1.0]], [[2.0, 2.0, 3.0, 3.0]]])
  assert_eq(coords_of(t, 4).length(), 1)
  assert_eq(coords_of(t, 4)[0].length(), 2)
  assert_eq(coords_of(t, 5).map(p => p.length()), [1, 1])
  assert_eq(coords_of(t, 5)[1][0][0:2].to_owned(), [5.0, 5.0])
}

///|
test "members may come in any order; bare geometries and collections" {
  let t = read(
    (
      #|{"properties": {"n": 1}, "geometry": {"coordinates": [[0, 0], [2, 2]], "type": "LineString"}, "type": "Feature"}
    ),
  )
  assert_eq(
    (t.kinds, t.column("n").unwrap().values),
    ([LineString], [Some(Num(1.0))]),
  )
  let bare = read("{\"coordinates\": [3, 4], \"type\": \"Point\"}")
  assert_eq((bare.kinds, coords_of(bare, 0)), ([Point], [[[3.0, 4.0]]]))
  // A GeometryCollection becomes one row per member, each with the properties.
  let gc = read(
    (
      #|{"type": "Feature", "id": "x", "properties": {"k": true}, "geometry": {"type": "GeometryCollection", "geometries": [
      #|  {"type": "Point", "coordinates": [1, 1]},
      #|  {"type": "GeometryCollection", "geometries": [{"type": "LineString", "coordinates": [[0, 0], [1, 0]]}]}]}}
    ),
  )
  assert_eq(gc.kinds, [Point, LineString])
  assert_eq(gc.ids, [Some(Str("x")), Some(Str("x"))])
  assert_eq(gc.column("k").unwrap().values, [Some(Bool(true)), Some(Bool(true))])
}

///|
test "properties keep their types; objects and arrays become compact JSON" {
  let t = read(
    (
      #|{"type": "Feature", "geometry": null, "id": 3, "properties": {
      #|  "s": "a\"b\\néあ", "n": -1.5e2, "t": true, "f": false, "z": null,
      #|  "o": {"a": [1, 2], "b": "x y"}, "u": "日本"}}
    ),
  )
  assert_eq(t.kinds, [NoGeometry])
  assert_eq(t.ids, [Some(Num(3.0))])
  let v = (k : String) => t.column(k).unwrap().values[0]
  assert_eq(v("s"), Some(Str("a\"b\\néあ")))
  assert_eq(v("n"), Some(Num(-150.0)))
  assert_eq(
    (v("t"), v("f"), v("z")),
    (Some(Bool(true)), Some(Bool(false)), Some(Null)),
  )
  assert_eq(v("o"), Some(Str("{\"a\":[1,2],\"b\":\"x y\"}")))
  assert_eq(v("u"), Some(Str("日本")))
}

///|
test "numbers parse to the nearest double, as JSON.parse does" {
  let t = read(
    (
      #|{"type": "MultiPoint", "coordinates": [[139.7671234, 35.6812], [0.1, -0.0], [1e300, 123456789012345678], [-2.5E-3, 7]]}
    ),
  )
  assert_eq(t.coords, [
    139.7671234, 35.6812, 0.1, -0.0, 1.0e300, 123456789012345678.0, -0.0025, 7.0,
  ])
}

///|
test "coordinates that do not fit the type give no geometry" {
  let t = read(
    (
      #|{"type": "FeatureCollection", "features": [
      #| {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [[0, 0], [1, 1]]}},
      #| {"type": "Feature", "geometry": {"type": "Point", "coordinates": [1]}},
      #| {"type": "Feature", "geometry": {"type": "LineString", "coordinates": []}},
      #| {"type": "Feature", "geometry": {"type": "Circle", "coordinates": [1, 2]}},
      #| {"type": "Feature", "geometry": {"type": "Point", "coordinates": [5, 6]}}
      #|]}
    ),
  )
  assert_eq(t.kinds, [NoGeometry, NoGeometry, NoGeometry, NoGeometry, Point])
  assert_eq(t.coords, [5.0, 6.0])
}

///|
test "malformed input raises once with the position" {
  let deep = "{\"type\": \"Feature\", \"properties\": {\"a\": " +
    "[".repeat(100) +
    "]".repeat(100) +
    "}}"
  for
    c in [
      ("{\"type\": \"Feature\" \"x\": 1}", 19),
      ("[1, 2]", 0),
      ("{\"a\": tru}", 6),
      ("{\"type\": \"Point\", \"coordinates\": [1, 2]} x", 41),
      ("{\"a\": \"x", 8),
      ("{\"a\": 1.}", 6),
      ("{\"a\": .5}", 6),
      (deep, 102),
    ] {
    try read(c.0) catch {
      @formats.Malformed(pos~, _) as e => {
        assert_eq(pos, c.1)
        assert_true(e.message().has_prefix("malformed GeoJSON at"))
      }
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected an error for \{c.0}")
    }
  }
}

///|
test "input with more than MAX_GEOJSON_KEYS distinct keys is rejected" {
  let features = (n : Int32) => {
    let parts = Array::makei(n, i => {
      "{\"type\": \"Feature\", \"geometry\": null, \"properties\": {\"k\{i}\": 1}}"
    })
    "{\"type\": \"FeatureCollection\", \"features\": [" + parts.join(",") + "]}"
  }
  assert_eq(
    read(features(@formats.MAX_GEOJSON_KEYS)).length(),
    @formats.MAX_GEOJSON_KEYS,
  )
  try read(features(@formats.MAX_GEOJSON_KEYS + 1)) catch {
    @formats.Malformed(_) as e =>
      assert_true(e.message().has_suffix("property keys"))
    e => fail("unexpected \{Repr(e)}")
  } noraise {
    _ => fail("expected the key limit to apply")
  }
}

///|
test "long numbers go to slow_number with their offsets; NaN rejects them" {
  let text = "{\"type\": \"Point\", \"coordinates\": [139.76712345678901, 1.5]}"
  let bytes = @utf8.encode(text)
  let seen = []
  let t = @formats.read_geojson(bytes[:], slow_number=(s, e) => {
    seen.push(@utf8.decode_lossy(bytes[s:e]))
    @formats.strconv_number(bytes[s:e])
  })
  assert_eq(seen, ["139.76712345678901"])
  assert_eq(t.coords, [139.76712345678901, 1.5])
  try
    @formats.read_geojson(bytes[:], slow_number=(_, _) => @double.not_a_number)
  catch {
    @formats.Malformed(pos~, m) => assert_eq((pos, m), (34, "invalid number"))
  } noraise {
    _ => fail("expected NaN to reject the number")
  }
}

///|
test "strconv_number parses JSON numbers and gives NaN otherwise" {
  assert_eq(@formats.strconv_number(b"-1.25e-3"[:]), -0.00125)
  assert_eq(
    @formats.strconv_number(b"0.30000000000000004"[:]),
    0.30000000000000004,
  )
  assert_true(@formats.strconv_number(b"x"[:]).is_nan())
}
