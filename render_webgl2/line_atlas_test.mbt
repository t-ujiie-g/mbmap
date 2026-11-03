///|
test "LineAtlas writes MapLibre's dash rows" {
  let a = @render_webgl2.LineAtlas::new()
  // Hashes of the whole atlas after each pattern, from MapLibre 6.16's LineAtlas.
  let cases : Array[(Array[Double], Bool, Int32, Int32, Double, Int64)] = [
    ([2, 1], false, 0, 0, 3, 543034346),
    ([2, 1], true, 8, 14, 3, 367364456),
    ([1, 2, 3], false, 16, 0, 6, 509308320),
    ([0, 2], false, 17, 0, 2, 509308320),
    ([1, 0, 1, 2], false, 18, 0, 4, 830320620),
    ([3, 1, 0.5, 1], true, 26, 14, 5.5, 48187238),
    ([0, 0], false, 34, 0, 0, 48187238),
  ]
  for c in cases {
    let (d, round, y, height, width, hash) = c
    let e = a.dash(d, round).unwrap()
    assert_eq((e.y, e.height, e.width), (y, height, width))
    let mut h = 0L
    for b in a.data {
      h = (h * 31L + b.to_int64()) % 1000000007L
    }
    assert_eq(h, hash)
  }
  assert_true(a.take_dirty())
  assert_true(!a.take_dirty())
  // A pattern is written once.
  assert_eq(a.dash([2, 1], false).map(e => e.y), Some(0))
  assert_true(!a.take_dirty())
  assert_true(a.dash([], false) is None)
  let long = Array::make(@render_webgl2.MAX_DASH_PARTS + 1, 1.0)
  assert_true(a.dash(long, false) is None)
  assert_true(
    a.dash(long[:@render_webgl2.MAX_DASH_PARTS].to_owned(), false) is Some(_),
  )
}

///|
test "LineAtlas refuses patterns once full" {
  let a = @render_webgl2.LineAtlas::new()
  for i in 0..<(@render_webgl2.LINE_ATLAS_HEIGHT / 15) {
    assert_true(a.dash([i.to_double() + 1.0, 1], true) is Some(_))
  }
  assert_true(a.dash([100, 1], true) is None)
  assert_true(a.dash([100, 1], false) is Some(_))
}
