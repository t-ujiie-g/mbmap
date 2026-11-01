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
