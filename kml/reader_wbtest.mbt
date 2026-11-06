///|
fn reader(cells : Int64, points : Int32) -> Reader raise @xml.XmlError {
  let r = Reader::new(@xml.Document::parse(b"<kml/>"), _ => 0.0, x => {
    x.to_string()
  })
  { ..r, max_cells: cells, max_points: points, }
}

///|
fn point(r : Reader, x : Double) -> Shapes {
  let s = Shapes::new(r)
  s.point(x, x)
  s.end_ring()
  s.end_part()
  s.end_member(Point)
  s
}

///|
test "tables past their cell and point limits stop the reader" {
  let wide = reader(3, 100)
  for i in 0..<2 {
    let p = Props::new()
    p.set("a\{i}", Num(1.0))
    wide.emit(point(wide, 1.0), p, None)
  }
  assert_eq(wide.limit, Some("more than \{MAX_KML_CELLS} property cells"))
  let long = reader(100, 1)
  long.emit(point(long, 1.0), Props::new(), None)
  assert_true(!long.stopped())
  long.emit(point(long, 2.0), Props::new(), None)
  assert_true(long.stopped())
  let msg = try long.finish() catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(msg, "too large: more than \{MAX_KML_POINTS} points")
}

///|
test "Reader::emit stops at the member past the cell limit" {
  let r = reader(2, 100)
  let s = Shapes::new(r)
  for x in 0..<5 {
    s.point(x.to_double(), 0)
    s.end_ring()
    s.end_part()
    s.end_member(Point)
  }
  let p = Props::new()
  p.set("a", Num(1.0))
  r.emit(s, p, None)
  assert_eq(r.out.table.length(), 3)
  assert_true(r.stopped())
}

///|
fn parsed(xml : String) -> @xml.Document raise @xml.XmlError {
  @xml.Document::parse(@utf8.encode(xml))
}

///|
test "the point limit stops rings read again through nesting" {
  let rings = "<LinearRing>".repeat(50)
  let ends = "</LinearRing>".repeat(50)
  let d = parsed(
    "<kml><Placemark><Polygon>\{rings}<coordinates>" +
    "0,0 1,0 1,1 0,0 ".repeat(5) +
    "</coordinates>\{ends}</Polygon></Placemark></kml>",
  )
  let r = {
    ..Reader::new(d, _ => 1.0, x => x.to_string()),
    max_cells: 100,
    max_points: 45,
  }
  let shapes = Shapes::new(r)
  r.geometry(d.first(0, "Placemark").unwrap(), shapes, [])
  assert_true(r.stopped())
  assert_eq(r.points, 45)
}

///|
test "tuples and tracks stop at the point limit" {
  let d = parsed("<kml/>")
  let r = { ..reader(100, 3), doc: d, }
  let t = r.tuples("0,0 ".repeat(1000), false)
  assert_eq(t.length() / 4, 4)
  assert_true(r.stopped())
  let track = parsed(
    "<Track><coord>1 2</coord><coord>3 4</coord><coord>5 6</coord></Track>",
  )
  let q = { ..reader(100, 1), doc: track, }
  let shapes = Shapes::new(q)
  q.track(track.first(0, "Track").unwrap(), shapes, [])
  assert_true(q.stopped())
  assert_eq(q.points, 1)
}

///|
fn gpx_with(
  segments : String,
  cells : Int64,
  points : Int32,
) -> Reader raise @xml.XmlError {
  let d = parsed("<gpx><trk>\{segments}</trk></gpx>")
  let r = { ..reader(cells, points), doc: d, }
  r.track_feature([], d.first(0, "trk").unwrap())
  r
}

///|
fn trkpt(extension : String) -> String {
  "<trkpt lat=\"1\" lon=\"2\"><extensions><\{extension}/></extensions></trkpt>"
}

///|
test "GPX extensions are charged as cells by names times points" {
  let distinct = "<trkseg>" +
    Array::makei(10, i => trkpt("e\{i}")).fold(init="", (a, b) => a + b) +
    "</trkseg>"
  assert_true(!gpx_with(distinct, 100, 100).stopped())
  let r = gpx_with(distinct, 99, 100)
  assert_eq(r.limit, Some("more than \{MAX_KML_CELLS} property cells"))
  assert_eq(r.out.table.length(), 0)
  let segment = "<trkseg>" + trkpt("a") + trkpt("a") + "</trkseg>"
  let segments = segment +
    segment +
    "<trkseg>" +
    trkpt("b") +
    trkpt("b") +
    "</trkseg>"
  assert_true(!gpx_with(segments, 6 + 2 * 9, 100).stopped())
  assert_true(gpx_with(segments, 6 + 2 * 9 - 1, 100).stopped())
}

///|
test "a GPX track stops at the extension names and points it may have" {
  let many = "<trkseg>" +
    Array::makei(MAX_KML_KEYS + 1, i => trkpt("e\{i}")).fold(init="", (a, b) => {
      a + b
    }) +
    "</trkseg>"
  let r = gpx_with(many, 1_000_000_000, 1_000_000)
  assert_eq(r.limit, Some("more than \{MAX_KML_KEYS} extensions"))
  let two = "<trkseg>" + trkpt("a") + trkpt("a") + trkpt("a") + "</trkseg>"
  let q = gpx_with(two, 100, 2)
  assert_eq(q.limit, Some("more than \{MAX_KML_POINTS} points"))
}
