///|
/// A feature of `kind` with `rings` of points in `@style.GEOMETRY_EXTENT` units in
/// tile 0/0/0, where (4096, 4096) is longitude 0, latitude 0.
struct Placed {
  kind : String
  place : @style.TileGeometry
}

///|
impl @style.FeatureContext for Placed with fn property(_, _) {
  None
}

///|
impl @style.FeatureContext for Placed with fn geometry_type(self) {
  self.kind
}

///|
impl @style.FeatureContext for Placed with fn within(self, polygons) {
  @style.geometry_within(polygons, self.kind, self.place, @core.Trig::moonbit())
}

///|
impl @style.FeatureContext for Placed with fn distance(self, shapes) {
  @style.geometry_distance(shapes, self.kind, self.place, @core.Trig::moonbit())
}

///|
fn placed(kind : String, rings : Array[Array[(Int32, Int32)]]) -> Placed {
  let place = @style.TileGeometry::new()
  for ring in rings {
    for p in ring {
      place.coords.push(p.0)
      place.coords.push(p.1)
    }
    place.ring_ends.push(place.coords.length() / 2)
  }
  { kind, place, }
}

///|
fn json(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("not JSON: \{text}")
  }
}

///|
fn geo(text : String) -> @style.Expr {
  @style.compile(json(text)) catch {
    e => abort(e.message())
  }
}

///|
let square : String =
  #|{"type": "Polygon", "coordinates": [[[-10, -10], [10, -10], [10, 10], [-10, 10], [-10, -10]]]}

///|
test "within holds for points and lines inside the polygon, never for polygons" {
  let within = geo("[\"within\", \{square}]")
  let inside = placed("Point", [[(4096, 4096)], [(4100, 4000)]])
  let outside = placed("Point", [[(4096, 4096)], [(8000, 4096)]])
  let line = placed("LineString", [[(4000, 4096), (4200, 4096)]])
  let crossing = placed("LineString", [[(4000, 4096), (6000, 4096)]])
  let polygon = placed("Polygon", [[(4000, 4000), (4200, 4000), (4000, 4200)]])
  assert_eq(within.eval(0.0, inside), Bool(true))
  assert_eq(within.eval(0.0, outside), Bool(false))
  assert_eq(within.eval(0.0, line), Bool(true))
  assert_eq(within.eval(0.0, crossing), Bool(false))
  assert_eq(within.eval(0.0, polygon), Bool(false))
  // Without a geometry (the main thread), as MapLibre without a canonical tile.
  assert_eq(within.eval(0.0, @style.NoFeature::{ }), Bool(false))
}

///|
test "within takes features, collections and multipolygons" {
  let point = placed("Point", [[(4096, 4096)]])
  for
    arg in [
      "{\"type\": \"Feature\", \"geometry\": \{square}}",
      "{\"type\": \"FeatureCollection\", \"features\": [{\"type\": \"Feature\", \"geometry\": {\"type\": \"Point\", \"coordinates\": [0, 0]}}, {\"type\": \"Feature\", \"geometry\": \{square}}]}",
      "{\"type\": \"MultiPolygon\", \"coordinates\": [[[[50, 50], [60, 50], [60, 60], [50, 50]]], [[[-1, -1], [1, -1], [1, 1], [-1, 1], [-1, -1]]]]}",
    ] {
    assert_eq(geo("[\"within\", \{arg}]").eval(0.0, point), Bool(true))
  }
  // A hole around the point.
  let holed =
    #|{"type": "Polygon", "coordinates": [[[-10, -10], [10, -10], [10, 10], [-10, 10], [-10, -10]],
    #|  [[-1, -1], [-1, 1], [1, 1], [1, -1], [-1, -1]]]}
  assert_eq(geo("[\"within\", \{holed}]").eval(0.0, point), Bool(false))
}

///|
test "within and distance refuse arguments that are not GeoJSON geometries" {
  for
    bad in [
      "[\"within\", {\"type\": \"Point\", \"coordinates\": [0, 0]}]", "[\"within\", {\"type\": \"FeatureCollection\", \"features\": []}]",
      "[\"within\", {\"type\": \"Polygon\", \"coordinates\": [[[0, \"a\"]]]}]", "[\"within\", {\"type\": \"Polygon\", \"coordinates\": [[[1e7, 0]]]}]",
      "[\"within\", [\"literal\", 1]]", "[\"within\"]", "[\"distance\", {\"type\": \"LineString\", \"coordinates\": []}]",
      "[\"distance\", {\"type\": \"Feature\"}]", "[\"distance\", {\"coordinates\": [0, 0]}]",
      "[\"distance\", 3]",
    ] {
    try @style.compile(json(bad)) catch {
      Invalid(_) => ()
      e => fail("unexpected \{e.message()}")
    } noraise {
      _ => fail("compiled \{bad}")
    }
  }
}

///|
test "distance measures in meters to points, lines and polygons" {
  let origin = placed("Point", [[(4096, 4096)]])
  let meters_per_degree = 3.141592653589793 / 180.0 * 6378137.0
  let near = (v : @style.Value, want : Double) => {
    guard v is Num(x) else { return false }
    (x - want).abs() < 1.0e-6 * want.abs() + 1.0e-9
  }
  let to_point = geo(
    "[\"distance\", {\"type\": \"Point\", \"coordinates\": [1, 0]}]",
  )
  assert_true(near(to_point.eval(0.0, origin), meters_per_degree))
  let to_line = geo(
    "[\"distance\", {\"type\": \"LineString\", \"coordinates\": [[2, -5], [2, 5]]}]",
  )
  assert_true(near(to_line.eval(0.0, origin), 2.0 * meters_per_degree))
  assert_eq(geo("[\"distance\", \{square}]").eval(0.0, origin), Num(0.0))
  let polygon = placed("Polygon", [
    [(4000, 4000), (4200, 4000), (4200, 4200), (4000, 4200), (4000, 4000)],
  ])
  assert_eq(
    geo("[\"distance\", {\"type\": \"Point\", \"coordinates\": [0, 0]}]").eval(
      0.0, polygon,
    ),
    Num(0.0),
  )
  // The point lies on the line, and 2° short of a shorter one.
  let line = placed("LineString", [[(4096, 4096), (4196, 4096)]])
  assert_true(to_point.eval(0.0, line) is Num(x) && x.abs() < 1.0e-3)
  let short = placed("LineString", [[(4096 - 100, 4096), (4096 - 45, 4096)]])
  let short_end = (4096.0 - 45.0) / 8192.0 * 360.0 - 180.0
  assert_true(
    near(to_point.eval(0.0, short), (1.0 - short_end) * meters_per_degree),
  )
  // Many points go through the divide-and-conquer queue.
  let many = placed("Point", [Array::makei(300, i => (4096 + i, 4096))])
  let d = to_point.eval(0.0, many)
  guard d is Num(x) else { fail("not a number") }
  assert_true(x > 0.0 && x < meters_per_degree)
  let empty = placed("Polygon", [[]])
  assert_true(to_point.eval(0.0, empty) is Num(x) && x.is_nan())
  assert_true(to_point.eval(0.0, @style.NoFeature::{ }) is Num(x) && x.is_nan())
  let unknown = placed("Unknown", [[(4096, 4096)]])
  assert_true(to_point.eval(0.0, unknown) is Num(x) && x.is_nan())
}

///|
test "within and distance count as reading the feature's geometry" {
  let e = geo("[\"case\", [\"within\", \{square}], 1, 0]")
  assert_true(e.reads_geometry())
  assert_eq(e.feature_inputs(), ([], true))
  assert_true(!geo("[\"get\", \"a\"]").reads_geometry())
}

///|
test "paint drawn by groups may not use within or distance" {
  let style = (layer : String) => {
    "{\"version\": 8, \"sources\": {\"v\": {\"type\": \"vector\", \"tiles\": [\"https://x/{z}/{x}/{y}\"]}}, \"layers\": [\{layer}]}"
  }
  let d = "[\"distance\", {\"type\": \"Point\", \"coordinates\": [0, 0]}]"
  let text = style(
    "{\"id\": \"t\", \"type\": \"symbol\", \"source\": \"v\", \"source-layer\": \"a\", \"layout\": {\"text-field\": \"x\"}, \"paint\": {\"text-halo-width\": \{d}}}",
  )
  try @style.Style::parse(text, strict=true) catch {
    Unsupported(path~, _) => assert_eq(path, "layers[0].paint.text-halo-width")
    e => fail("unexpected \{e.message()}")
  } noraise {
    _ => fail("parsed")
  }
  let lenient = @style.Style::parse(text, strict=false)
  assert_eq(lenient.layers.length(), 1)
  assert_eq(lenient.warnings.length(), 1)
  // Per-vertex paint and filters may.
  let line = style(
    "{\"id\": \"l\", \"type\": \"line\", \"source\": \"v\", \"source-layer\": \"a\", \"filter\": [\"<\", \{d}, 10], \"paint\": {\"line-width\": \{d}}}",
  )
  assert_eq(@style.Style::parse(line, strict=true).layers.length(), 1)
  let stated = style(
    "{\"id\": \"l\", \"type\": \"line\", \"source\": \"v\", \"source-layer\": \"a\", \"paint\": {\"line-width\": \{d}, \"line-opacity\": [\"feature-state\", \"o\"]}}",
  )
  try @style.Style::parse(stated, strict=true) catch {
    Unsupported(path~, _) => assert_eq(path, "layers[0].paint.line-width")
    e => fail("unexpected \{e.message()}")
  } noraise {
    _ => fail("parsed")
  }
}
