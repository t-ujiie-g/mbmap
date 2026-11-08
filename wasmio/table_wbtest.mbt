///|
fn sample_table() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for p in [(0.0, 0.0), (1.5, 0.0), (1.5, -2.25)] {
    b.point(p.0, p.1)
  }
  b.end_ring()
  b.end_part()
  b.prop("name", Str("日本"))
  b.prop("n", Num(-0.5))
  b.end_feature(LineString)
  b.prop("t", Bool(true))
  b.end_feature(Point)
  b.finish()
}

///|
test "write_table writes to_bytes' bytes and input_table reads them in place" {
  let bytes = sample_table().to_bytes()
  clear_input()
  assert_eq(write_table(sample_table()), bytes.length())
  let at = output_addr()
  for i, x in bytes {
    assert_eq(load_u8(at + i), x.to_int())
  }
  // Two bytes before the table, as an entry's input of several parts has.
  assert_eq(prepare_input(bytes.length() + 2, MAX_INPUT_BYTES), PAGE)
  for i, x in bytes {
    store_u8(PAGE + 2 + i, x.to_int())
  }
  let t = input_table(2, bytes.length()).unwrap()
  assert_eq(t.to_bytes(), bytes)
  assert_eq(t.column("name").unwrap().values, [Some(Str("日本")), None])
  assert_true(input_table(2, bytes.length() - 1) is None)
  assert_true(input_table(0, bytes.length()) is None)
  assert_true(input_table(3, bytes.length()) is None)
  assert_true(input_table(-1, 4) is None)
  clear_input()
}

///|
test "input_slice takes a range of the input, empty outside it" {
  assert_eq(prepare_input(18, MAX_INPUT_BYTES), PAGE)
  for i in 0..<2 {
    store_u8(PAGE + i, 65 + i)
  }
  assert_eq(input_slice(0, 2), b"AB")
  assert_eq(input_slice(1, 18), b"")
  clear_input()
}
