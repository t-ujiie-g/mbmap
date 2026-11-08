///|
test "lat_lng_order takes row and column order as they are and sorts the rest" {
  let rows : FixedArray[Double] = [0.0, 1.0, 2.0, 0.0, 1.0, 2.0]
  let lats : FixedArray[Double] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
  assert_eq(lat_lng_order(rows, lats), [0, 1, 2, 3, 4, 5])
  let xs : FixedArray[Double] = [0.0, 0.0, 1.0, 1.0, 2.0, 2.0]
  let ys : FixedArray[Double] = [0.0, 1.0, 0.0, 1.0, 0.0, 1.0]
  assert_eq(lat_lng_order(xs, ys), [0, 2, 4, 1, 3, 5])
  let xs : FixedArray[Double] = [1.0, 0.0, 1.0, 0.0, 0.0]
  let ys : FixedArray[Double] = [1.0, 1.0, 0.0, 0.0, 0.0]
  assert_eq(lat_lng_order(xs, ys), [3, 4, 2, 1, 0])
}
