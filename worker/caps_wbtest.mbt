///|
test "an entry names at most MAX_FONTS fonts; labels past them take the map's" {
  let l = Labels::new()
  for i in 0..<MAX_FONTS {
    assert_eq(l.font("Font \{i}"), i + 1)
  }
  assert_eq(l.font("One more"), 0)
  assert_eq(l.font("Font 3"), 4)
  assert_eq(l.font(""), 0)
}

///|
test "features past MAX_FEATURE_DASHES patterns, or with longer ones, draw solid" {
  let p = TileProcessor::new(
    @style.Style::parse(
      "{\"sources\": {\"a\": {\"type\": \"vector\", \"tiles\": [\"t\"]}}, \"layers\": []}",
    ),
  )
  // A tile with one empty layer "l".
  guard p.read_tile("a", b"\x1a\x05\x0a\x01l\x78\x02"[:]) is Some(of) &&
    of("l") is Some(layer) else {
    fail("expected the layer")
  }
  let feature = p.feature_ref(layer)
  let d = Dashes::new()
  let dashes = (ns : Array[Double]) => {
    @style.Expr::Lit(List(ns.map(n => Num(n))))
  }
  let long = Array::make(MAX_FEATURE_DASH_PARTS + 1, 1.0)
  assert_eq(d.index(dashes(long), 14.0, feature), NO_DASH)
  for k in 0..<(MAX_FEATURE_DASHES - 1) {
    d.patterns.push([k.to_double(), 1.0])
  }
  assert_eq(d.index(dashes([2.0, 2.0]), 14.0, feature), MAX_FEATURE_DASHES - 1)
  assert_eq(d.index(dashes([3.0, 3.0]), 14.0, feature), NO_DASH)
  assert_eq(d.index(dashes([2.0, 2.0]), 14.0, feature), MAX_FEATURE_DASHES - 1)
  assert_eq(d.index(dashes([5.0, 1.0]), 14.0, feature), 5)
}
