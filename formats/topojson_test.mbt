///|
fn topo(text : String, object? : String) -> (@geom.Table, Array[String]) raise {
  let b = @utf8.encode(text)
  @formats.read_topojson(b[:], object, slow_number=(s, e) => {
    @core.strconv_number(b[s:e])
  })
}

///|
fn topo_error(text : String, object? : String) -> String {
  try topo(text, object?) catch {
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
let quantized : String =
  #|{"type": "Topology",
  #| "arcs": [[[0, 0], [2, 0], [0, 2]], [[2, 2], [-2, 0]], [[1, 1]]],
  #| "objects": {
  #|  "first": {"type": "GeometryCollection", "geometries": [
  #|   {"type": "LineString", "arcs": [0, 1], "id": "a", "properties": {"n": 1, "o": {"x": [1, 2]}}},
  #|   {"type": "LineString", "arcs": [-2], "id": 2},
  #|   {"type": "Polygon", "arcs": [[2]], "id": null},
  #|   {"type": "Point", "coordinates": [4, 8]},
  #|   {"type": "MultiPoint", "coordinates": [[0, 0], [2, 4]]},
  #|   {"type": null, "properties": {"e": true}},
  #|   {"type": "GeometryCollection", "properties": {"g": "c"}, "geometries": [{"type": "Point", "coordinates": [1, 1]}, {"type": "LineString", "arcs": [2]}]}
  #|  ]},
  #|  "second": {"properties": {"k": "v"}, "arcs": [[[1]], [[0]]], "type": "MultiPolygon"}
  #| },
  #| "transform": {"scale": [0.5, 0.25], "translate": [100, 10]}}

///|
test "TopoJSON arcs decoded, stitched and reversed; features as topojson-client makes them" {
  let (t, names) = topo(quantized)
  assert_eq(names, ["first", "second"])
  assert_eq(t.kinds, [
    LineString,
    LineString,
    Polygon,
    Point,
    MultiPoint,
    NoGeometry,
    Point,
    LineString,
  ])
  assert_eq(t.ids, [
    Some(Str("a")),
    Some(Num(2.0)),
    None,
    None,
    None,
    None,
    None,
    None,
  ])
  // Arc 0 is (100, 10) (101, 10) (101, 10.5); arc 1 (101, 10.5) (100, 10.5); arc 2 (100.5, 10.25).
  let ring = (r : Int32) => {
    let (s, e) = t.points(r)
    t.coords[s * 2:e * 2].to_owned()
  }
  assert_eq(ring(0), [100.0, 10.0, 101.0, 10.0, 101.0, 10.5, 100.0, 10.5])
  assert_eq(ring(1), [100.0, 10.5, 101.0, 10.5])
  // A ring of too few points is padded with its first; a one-point line repeats it.
  assert_eq(ring(2), [100.5, 10.25, 100.5, 10.25, 100.5, 10.25, 100.5, 10.25])
  assert_eq(ring(3), [102.0, 12.0])
  assert_eq(ring(4), [100.0, 10.0, 101.0, 11.0])
  assert_eq(ring(6), [100.5, 10.25, 100.5, 10.25])
  let col = (name : String) => t.column(name).unwrap().values
  assert_eq(col("o"), [
    Some(Str("{\"x\":[1,2]}")),
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  ])
  assert_eq(col("g"), [
    None,
    None,
    None,
    None,
    None,
    None,
    Some(Str("c")),
    Some(Str("c")),
  ])
  let (second, _) = topo(quantized, object="second")
  assert_eq(second.kinds, [MultiPolygon])
  assert_eq(second.ring_ends, [1, 2])
  assert_eq(second.column("k").unwrap().values, [Some(Str("v"))])
}

///|
test "TopoJSON without a transform keeps positions as they are" {
  let (t, _) = topo(
    "{\"type\":\"Topology\",\"objects\":{\"o\":{\"type\":\"LineString\",\"arcs\":[0]},\"p\":{\"type\":\"Point\",\"coordinates\":[-0.5,1e2,7]}},\"arcs\":[[[139.5,35.5,9],[139.75,35.25]]]}",
  )
  assert_eq(t.coords, [139.5, 35.5, 139.75, 35.25])
  let (p, _) = topo(
    "{\"type\":\"Topology\",\"objects\":{\"p\":{\"type\":\"Point\",\"coordinates\":[-0.5,1e2,7]}},\"arcs\":[]}",
  )
  assert_eq(p.coords, [-0.5, 100.0])
  let (none, names) = topo("{\"type\":\"Topology\",\"objects\":{},\"arcs\":[]}")
  assert_eq((none.length(), names), (0, []))
}

///|
test "malformed TopoJSON is refused" {
  assert_eq(
    topo_error("{\"type\":\"FeatureCollection\",\"features\":[]}"),
    "malformed TopoJSON at 0: not a TopoJSON Topology",
  )
  assert_eq(
    topo_error("{\"type\":\"Topology\",\"objects\":{}} x"),
    "malformed TopoJSON at 33: unexpected data after the TopoJSON value",
  )
  let arcs = "{\"type\":\"Topology\",\"arcs\":[[[0,0],[1,1]]],\"objects\":{\"o\":{\"type\":\"LineString\",\"arcs\":ARCS}}}"
  assert_eq(
    topo_error(arcs.replace(old="ARCS", new="[1]")),
    "malformed TopoJSON at 86: invalid arc index",
  )
  assert_eq(
    topo_error(arcs.replace(old="ARCS", new="[0.5]")),
    "malformed TopoJSON at 86: invalid arc index",
  )
  assert_eq(
    topo_error(arcs.replace(old="ARCS", new="7")),
    "malformed TopoJSON at 85: expected arc indices",
  )
  assert_eq(
    topo_error(arcs.replace(old="ARCS", new="[x]")),
    "malformed TopoJSON at 86: invalid number",
  )
  assert_eq(
    topo_error(arcs.replace(old="ARCS", new="[0]"), object="p"),
    "malformed TopoJSON at 91: no object named \"p\"",
  )
  assert_eq(
    topo_error("{\"type\":\"Topology\",\"arcs\":[[[0]]],\"objects\":{}}"),
    "malformed TopoJSON at 31: a position needs two numbers",
  )
  let mut deep = "{\"type\":\"Point\",\"coordinates\":[0,0]}"
  for _ in 0..<40 {
    deep = "{\"type\":\"GeometryCollection\",\"geometries\":[\{deep}]}"
  }
  assert_true(
    topo_error(
      "{\"type\":\"Topology\",\"arcs\":[],\"objects\":{\"o\":{\"type\":\"GeometryCollection\",\"geometries\":[\{deep}]}}}",
    ).has_suffix("nested deeper than 64"),
  )
}
