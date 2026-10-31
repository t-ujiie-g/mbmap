///|
/// Places `ints` then `doubles` as the input, as JS does.
fn put_input(ints : Array[Int32], doubles : Array[Double]) -> Unit {
  let at = prepare_input(ints.length() * 4 + doubles.length() * 8)
  for i, v in ints {
    store_i32(at + i * 4, v)
  }
  for i, v in doubles {
    store_f64(at + ints.length() * 4 + i * 8, v)
  }
}

///|
test "analyze writes per-polygon results, the top list and the cell count" {
  // One 1° square: ring ends [4], polygon ends [1].
  put_input([4, 1], [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
  let n = analyze(1, 1, 4)
  assert_eq(n, 40 + 44)
  let out = output_addr()
  assert_eq(load_f64(out + 8), 0.0)
  assert_eq(load_f64(out + 32), 1.0)
  assert_eq((load_i32(out + 40), load_i32(out + 44)), (0, -1))
  assert_eq(load_i32(out + 80), 1)
}

///|
test "analyze rejects counts that do not match the input" {
  put_input([4, 1], [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0])
  assert_eq(analyze(1, 1, 5), -1)
  assert_eq(analyze(-1, 1, 4), -1)
  // Counts whose sizes wrap around in 32-bit arithmetic to the input length.
  assert_eq(analyze(1, 1, 4 + 268435456), -1)
  assert_eq(analyze(1073741824 + 1, 1, 4), -1)
}
