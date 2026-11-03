///|
test "Trig's methods call its functions" {
  let m = @core.Trig::moonbit()
  assert_eq(m.sin(0.5), @math.sin(0.5))
  assert_eq(m.cos(0.5), @math.cos(0.5))
  assert_eq(m.tan(0.5), @math.tan(0.5))
  assert_eq(m.asin(0.5), @math.asin(0.5))
  assert_eq(m.acos(0.5), @math.acos(0.5))
  assert_eq(m.atan(0.5), @math.atan(0.5))
  assert_eq(m.atan2(1.0, 2.0), @math.atan2(1.0, 2.0))
  assert_eq(m.exp(0.5), @math.exp(0.5))
  assert_eq(m.ln(2.0), @math.ln(2.0))
  assert_eq(m.pow(2.0, 0.5), @math.pow(2.0, 0.5))
  // A host's functions go where MoonBit's would.
  let half : @core.Trig = { ..m, pow: (x, y) => x * y, }
  assert_eq(half.pow(3.0, 2.0), 6.0)
}
