///|
test "clipping_ok takes Map.setClipping's layout and refuses others" {
  let head = [139.0, 35.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
  let plane = [..head, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0]
  assert_true(clipping_ok(FixedArray::from_array(plane)))
  assert_true(clipping_ok([]))
  let square = [..head, 0.0, 1.0, 3.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0]
  assert_true(clipping_ok(FixedArray::from_array(square)))
  // Fewer vertices than the ring says, too many planes, a NaN.
  assert_false(
    clipping_ok(FixedArray::from_array([..head, 0.0, 1.0, 4.0, 0.0, 0.0])),
  )
  assert_false(clipping_ok(FixedArray::from_array([..head, 17.0, 0.0])))
  let nan = plane.copy()
  nan[10] = @double.not_a_number
  assert_false(clipping_ok(FixedArray::from_array(nan)))
  assert_false(clipping_ok(FixedArray::from_array([..head, 0.0, 9.0])))
  let many = [..head, 0.0, 1.0, 65.0, ..FixedArray::make(130, 0.0)]
  assert_false(clipping_ok(FixedArray::from_array(many)))
}
