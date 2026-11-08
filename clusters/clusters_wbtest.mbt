///|
fn line_of_points(n : Int32) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i in 0..<n {
    b.point(i.to_double() * 0.001, 0.0)
    b.end_ring()
    b.end_part()
    b.end_feature(Point)
  }
  b.finish()
}

///|
test "kmeans gives None once its distances pass the cap" {
  let t = line_of_points(10)
  let mut cap = 0L
  while kmeans_within(t, 2, cap) is None {
    cap += 1L
  }
  assert_true(cap > 20L && cap % 20L == 0L)
  assert_true(kmeans_within(t, 2, cap - 1L) is None)
  assert_eq(kmeans_within(t, 2, cap), kmeans(t, 2))
}

///|
test "dbscan gives None once its candidates pass the cap" {
  let t = line_of_points(10)
  let trig = @core.Trig::moonbit()
  let mut cap = 0L
  while dbscan_within(t, 1.0, 3, trig, cap) is None {
    cap += 1L
  }
  assert_true(cap >= 10L)
  assert_eq(dbscan_within(t, 1.0, 3, trig, cap), dbscan(t, 1.0, 3))
}
