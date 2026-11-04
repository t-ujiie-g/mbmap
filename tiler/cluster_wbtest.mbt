///|
test "abbreviated counts follow geojson-vt" {
  assert_eq(abbreviated_count(999), Num(999.0))
  assert_eq(abbreviated_count(1000), Str("1k"))
  assert_eq(abbreviated_count(1050), Str("1.1k"))
  assert_eq(abbreviated_count(9999), Str("10k"))
  assert_eq(abbreviated_count(12500), Str("13k"))
}
