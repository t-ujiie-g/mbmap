///|
test "PairIndex keeps its keys through growth and removals" {
  let index = PairIndex::new(0)
  for i in 0..<5000 {
    index.set(i.to_int64(), (i % 3).to_int64(), i)
  }
  index.set(7L, 1L, 70)
  for i in 0..<5000 {
    if i % 2 == 1 {
      index.remove(i.to_int64(), (i % 3).to_int64())
    }
  }
  index.remove(7L, 1L)
  index.remove(9999L, 0L)
  assert_eq(index.count, 2500)
  for i in 0..<5000 {
    let want = if i % 2 == 1 { -1 } else { i }
    assert_eq(index.get(i.to_int64(), (i % 3).to_int64()), want)
  }
}

///|
test "js_round rounds halves up" {
  assert_eq(js_round(2.5), 3.0)
  assert_eq(js_round(-2.5), -2.0)
  assert_eq(js_round(-0.5), 0.0)
  assert_eq(js_round(0.49999999999999994), 0.0)
  assert_eq(js_round(4503599627370497.0), 4503599627370497.0)
  assert_eq(js_round(-1.0e300), -1.0e300)
  assert_true(js_round(@double.not_a_number).is_nan())
  assert_eq(js_round(@double.infinity), @double.infinity)
}

///|
test "key_bits merges 0 with -0 and every NaN" {
  assert_eq(key_bits(-0.000001, 1.0e-5), key_bits(0.0, 1.0e-5))
  assert_eq(key_bits(-0.0, 1.0e-5), 0L)
  assert_eq(key_bits(@double.not_a_number, 1.0e-5), key_bits(1.0, 0.0))
  assert_eq(key_bits(139.700004, 1.0e-5), key_bits(139.7, 1.0e-5))
  assert_true(key_bits(139.700006, 1.0e-5) != key_bits(139.7, 1.0e-5))
}
