///|
fn reader(cells : Int64, points : Int32) -> Reader raise @xml.XmlError {
  let r = Reader::new(@xml.Document::parse(b"<kml/>"), _ => 0.0, x => {
    x.to_string()
  })
  { ..r, max_cells: cells, max_points: points, }
}

///|
fn point(x : Double) -> Shapes {
  let s = Shapes::new()
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
    wide.emit(point(1.0), p, None)
  }
  assert_eq(wide.limit, Some("more than \{MAX_KML_CELLS} property cells"))
  let long = reader(100, 1)
  long.emit(point(1.0), Props::new(), None)
  assert_true(!long.stopped())
  long.emit(point(2.0), Props::new(), None)
  assert_true(long.stopped())
  let msg = try long.finish() catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(msg, "too large: more than \{MAX_KML_POINTS} points")
}
