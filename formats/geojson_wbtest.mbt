///|
test "input past the point limit is rejected" {
  let line = b"{\"type\": \"LineString\", \"coordinates\": [[0, 0], [1, 1], [2, 2]]}"
  let number = (s : Int32, e : Int32) => @core.strconv_number(line[s:e])
  assert_eq(read_points(line[:], number, 3).length(), 1)
  try read_points(line[:], number, 2) catch {
    e => assert_true(e.message().has_suffix("too many points"))
  } noraise {
    _ => fail("expected the point limit to apply")
  }
}
