///|
fn three_points() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for x in [0.0, 1.0, 2.0] {
    b.point(x, 0.0)
    b.end_ring()
    b.end_part()
    b.end_feature(Point)
  }
  b.finish()
}

///|
test "pairs are found within the caps and refused past them" {
  let t = three_points()
  assert_true(pairs(t, t, 0, None) is Ok([0, 0, 1, 1, 2, 2]))
  assert_true(pairs(t, t, 0, None, max_candidates=2) is Err(_))
  assert_true(pairs(t, t, 0, None, max_points=5) is Err(_))
  assert_true(pairs(t, t, 0, None, max_points=6) is Ok(_))
}
