///|
test "ByteWriter and ByteReader round-trip little-endian values" {
  let w = @core.ByteWriter::new()
  w.u8(7)
  w.pad4()
  w.u32(-2)
  w.i16(40000)
  w.i16(-5)
  w.f64(-0.125)
  w.utf8("日本")
  assert_eq(w.to_bytes().length(), 4 + 4 + 2 + 2 + 8 + 4 + 6)
  let r = @core.ByteReader::new(w.to_bytes()[:])
  assert_eq(r.u8(), 7)
  r.pad4()
  assert_eq((r.u32(), r.i16(), r.i16()), (-2, 32767, -5))
  assert_eq((r.f64(), r.utf8()), (-0.125, "日本"))
  assert_true(r.done())
}

///|
test "ByteReader fails sticky past the end and on fail()" {
  let r = @core.ByteReader::new(b"\x01\x02\x03"[:])
  assert_eq(r.u32(), 0)
  assert_false(r.ok())
  assert_eq(r.u8(), 0)
  // A string longer than what is left.
  let s = @core.ByteReader::new(b"\x09\x00\x00\x00abc"[:])
  assert_eq(s.utf8(), "")
  assert_false(s.ok())
  // A length whose sum with the position would overflow Int32.
  let big = @core.ByteReader::new(b"\x00\xff\xff\xff\x7f"[:])
  assert_eq(big.u8(), 0)
  assert_eq(big.utf8(), "")
  assert_false(big.ok())
  let t = @core.ByteReader::new(b"\x01"[:])
  t.fail()
  assert_false(t.done())
}
