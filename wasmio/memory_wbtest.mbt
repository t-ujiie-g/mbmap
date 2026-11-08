///|
test "input is read back four bytes at a time, output follows it aligned" {
  assert_eq(prepare_input(-1, 10), -1)
  assert_eq(prepare_input(11, 10), -1)
  assert_eq(prepare_input(6, 10), PAGE)
  for i in 0..<6 {
    store_u8(PAGE + i, i + 1)
  }
  assert_eq(input_bytes(), b"\x01\x02\x03\x04\x05\x06")
  assert_eq(output_addr(), PAGE + 8)
  assert_eq(write_bytes(b"ab"[:]), 2)
  assert_eq((load_u8(PAGE + 8), load_u8(PAGE + 9)), (97, 98))
  assert_eq(write_i32s([-2, 7][:]), 2)
  assert_eq((load_i32(PAGE + 8), load_i32(PAGE + 12)), (-2, 7))
  assert_eq(write_f64s([1.5]), 1)
  assert_eq(load_i32(PAGE + 12), 0x3FF80000)
  assert_eq(fail_with("é"), -2)
  clear_input()
  assert_eq(output_addr(), PAGE)
}

///|
test "input_f64s reads whole f64s and leaves out a trailing part" {
  assert_eq(prepare_input(20, MAX_INPUT_BYTES), PAGE)
  store_f64(PAGE, 1.5)
  store_f64(PAGE + 8, -2.0)
  let v = input_f64s()
  assert_eq((v.length(), v[0], v[1]), (2, 1.5, -2.0))
  clear_input()
  assert_eq(input_f64s().length(), 0)
}

///|
test "input_length is the prepared length and output_fits caps at MAX_OUTPUT_BYTES" {
  assert_eq(prepare_input(20, MAX_INPUT_BYTES), PAGE)
  assert_eq(input_length(), 20)
  clear_input()
  assert_eq(input_length(), 0)
  assert_true(output_fits(MAX_OUTPUT_BYTES.to_int64() / 8L, 8))
  assert_false(output_fits(MAX_OUTPUT_BYTES.to_int64() / 8L + 1L, 8))
  assert_false(output_fits(-1L, 8))
}

///|
test "lengths_fit refuses negative lengths and sums past the total, overflowing ones included" {
  assert_true(lengths_fit(2, 8, 10))
  assert_false(lengths_fit(2, 9, 10))
  assert_false(lengths_fit(-1, 0, 10))
  assert_false(lengths_fit(0, -1, 10))
  assert_false(lengths_fit(2147483647, 2, 10))
  assert_false(lengths_fit(2, 2147483647, 10))
}

///|
test "write_bytes, write_f64s_after and write_f64_rows place every value" {
  clear_input()
  assert_eq(write_bytes(b"abcdef"[:]), 6)
  assert_eq(load_i32(PAGE), 0x64636261)
  assert_eq((load_u8(PAGE + 4), load_u8(PAGE + 5)), (101, 102))
  assert_eq(write_f64s_after([1.0, 2.0], [3.0]), 3)
  assert_eq(
    (load_f64(PAGE), load_f64(PAGE + 8), load_f64(PAGE + 16)),
    (1.0, 2.0, 3.0),
  )
  let grid = FixedArray::makei(12, i => i.to_double())
  assert_eq(write_f64_rows(grid, 4, 1, 1, 2, 2), 4)
  assert_eq(
    (
      load_f64(PAGE),
      load_f64(PAGE + 8),
      load_f64(PAGE + 16),
      load_f64(PAGE + 24),
    ),
    (5.0, 6.0, 9.0, 10.0),
  )
  assert_eq(write_f64_rows(grid, 4, 3, 0, 2, 1), -1)
  assert_eq(write_f64_rows(grid, 4, 0, 2, 1, 2), -1)
  assert_eq(write_f64_rows(grid, 4, 0, -1, 1, 1), -1)
  assert_eq(write_f64_rows(grid, 4, 0, 2147483647, 1, 2), -1)
  assert_eq(write_f64_rows(grid, 0, 0, 0, 0, 0), -1)
}
