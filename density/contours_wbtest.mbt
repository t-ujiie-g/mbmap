///|
/// A `n` x `n` grid with every other value 1: a ring around each of them.
fn checkerboard(n : Int32) -> FixedArray[Double] {
  FixedArray::makei(n * n, i => ((i % n + i / n) % 2).to_double())
}

///|
test "contour_levels stop once the segments or nesting tests run out" {
  let grid = checkerboard(8)
  guard contour_levels(grid, 8, 8, [0.5], false) is Some([polygons]) else {
    fail("no contours")
  }
  assert_eq(polygons.length(), 32)
  let segments = Budget::new()
  assert_true(
    contour_levels(grid, 8, 8, [0.5], false, budget=segments) is Some(_),
  )
  let used = segments.segments
  let over = Budget::new(max_segments=used - 1L)
  assert_true(contour_levels(grid, 8, 8, [0.5], false, budget=over) is None)
  let enough = Budget::new(max_segments=used)
  assert_true(
    contour_levels(grid, 8, 8, [0.5], false, budget=enough) is Some(_),
  )
  let rings = FixedArray::make(64, 1.0)
  for i in [18, 21, 42, 45] {
    rings[i] = 0.0
  }
  let tests = Budget::new()
  guard contour_levels(rings, 8, 8, [0.5], false, budget=tests)
    is Some([[[_, _, _, _, _]]]) else {
    fail("expected one polygon with four holes")
  }
  let few = Budget::new(max_tests=tests.tests - 1L)
  assert_true(contour_levels(rings, 8, 8, [0.5], false, budget=few) is None)
}

///|
test "the contour caps" {
  assert_eq(MAX_CONTOUR_SEGMENTS, 4_000_000L)
  assert_eq(MAX_CONTOUR_NESTING_TESTS, 100_000_000L)
}
