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
test "tables -1 gives the kept tables until forgotten" {
  forget_tables()
  assert_true(tables(-1) is None)
  let t = three_points()
  kept.val = Some({ a: t, b: t, index: None, })
  guard tables(-1) is Some(k) else { fail("no kept tables") }
  assert_eq(k.a.length(), 3)
  let found = []
  k.index().search(0.5, -1.0, 2.5, 1.0, found)
  found.sort()
  assert_eq(found, [1, 2])
  assert_true(physical_equal(k.index(), k.index()))
  forget_tables()
  assert_true(tables(-1) is None)
}

///|
test "pairs are found within the caps and refused past them" {
  let t = three_points()
  assert_true(pairs(t, t, 0, None) is Ok([0, 0, 1, 1, 2, 2]))
  assert_true(pairs(t, t, 0, None, max_candidates=2) is Err(_))
  assert_true(pairs(t, t, 0, None, max_points=5) is Err(_))
  assert_true(pairs(t, t, 0, None, max_points=6) is Ok(_))
}
