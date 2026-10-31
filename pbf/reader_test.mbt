///|
fn reader(bytes : Bytes) -> @pbf.Reader {
  @pbf.Reader::new(bytes[:])
}

///|
test "read_varint32 decodes 1 to 5 byte varints" {
  for v in [0, 1, 127, 128, 300, 16383, 16384, 2097151, 268435455, 0x7fffffff] {
    let w = @pbf.Writer::new()
    w.write_varint32(v)
    let r = reader(w.to_bytes())
    assert_eq(r.read_varint32(), v)
    assert_true(r.at_end() && !r.failed())
  }
}

///|
test "read_varint32 keeps the low 32 bits of a 10-byte negative int32" {
  let w = @pbf.Writer::new()
  w.write_varint32(-2)
  let b = w.to_bytes()
  assert_eq(b.length(), 10)
  let r = reader(b)
  assert_eq(r.read_varint32(), -2)
  assert_true(r.at_end() && !r.failed())
}

///|
test "varints longer than 10 bytes record VarintTooLong" {
  let b : Bytes = [
    0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01,
  ]
  let r = reader(b)
  assert_eq(r.read_varint32(), 0)
  assert_eq(r.error(), Some(VarintTooLong(pos=0)))
  let r64 = reader(b)
  assert_eq(r64.read_varint64(), 0UL)
  assert_eq(r64.error(), Some(VarintTooLong(pos=0)))
}

///|
test "a failed read stops at the end and keeps the first error" {
  let b : Bytes = [0x05, 0x80, 0x80]
  // A view that ends before the varint terminates.
  let r = @pbf.Reader::new(b[1:3])
  assert_eq(r.read_varint32(), 0)
  assert_true(r.at_end())
  ignore(r.read_fixed32())
  assert_eq(r.error(), Some(UnexpectedEof(pos=3)))
  let short = reader([0x01, 0x02])
  assert_eq(short.read_fixed32(), 0U)
  assert_eq(short.error(), Some(UnexpectedEof(pos=0)))
}

///|
test "zigzag and 64-bit integers round-trip" {
  let w = @pbf.Writer::new()
  for v in [0, -1, 1, -64, 64, 0x7fffffff, -0x80000000] {
    w.write_svarint32(v)
  }
  for v in [0L, -1L, 9007199254740993L, -9223372036854775808L] {
    w.write_sint64(v)
  }
  w.write_varint(18446744073709551615UL)
  let r = reader(w.to_bytes())
  for v in [0, -1, 1, -64, 64, 0x7fffffff, -0x80000000] {
    assert_eq(r.read_svarint32(), v)
  }
  for v in [0L, -1L, 9007199254740993L, -9223372036854775808L] {
    assert_eq(r.read_sint64(), v)
  }
  assert_eq(r.read_int64(), -1L)
  assert_true(r.at_end() && !r.failed())
}

///|
test "fixed-width, float, double and bool fields" {
  let w = @pbf.Writer::new()
  w.write_fixed32(0xdeadbeefU)
  w.write_fixed64(0x0123456789abcdefUL)
  w.write_fixed32((1.5 : Float).reinterpret_as_uint())
  w.write_fixed64((-0.1 : Double).reinterpret_as_uint64())
  w.write_varint(1UL)
  w.write_varint(0UL)
  let r = reader(w.to_bytes())
  assert_eq(r.read_fixed32(), 0xdeadbeefU)
  assert_eq(r.read_fixed64(), 0x0123456789abcdefUL)
  assert_eq(r.read_float(), 1.5)
  assert_eq(r.read_double(), -0.1)
  assert_true(r.read_bool())
  assert_false(r.read_bool())
  assert_false(r.failed())
}

///|
test "strings decode UTF-8 and replace invalid sequences" {
  let w = @pbf.Writer::new()
  w.write_string("東京駅")
  w.write_bytes(([0x61, 0xff, 0x62] : Bytes)[:])
  let r = reader(w.to_bytes())
  assert_eq(r.read_string(), "東京駅")
  assert_eq(r.read_string(), "a\u{FFFD}b")
}

///|
fn nested() -> Bytes {
  let inner = @pbf.Writer::new()
  inner.write_tag(1, @pbf.WIRE_VARINT)
  inner.write_varint(42UL)
  inner.write_tag(2, @pbf.WIRE_VARINT)
  inner.write_varint(43UL)
  let outer = @pbf.Writer::new()
  outer.write_tag(3, @pbf.WIRE_LEN)
  outer.write_bytes(inner.to_bytes()[:])
  outer.write_tag(4, @pbf.WIRE_LEN)
  outer.write_bytes(([7, 8, 9] : Bytes)[:])
  outer.to_bytes()
}

///|
test "read_bytes returns a view over the original buffer" {
  let r = reader(nested())
  r.skip(r.read_tag())
  assert_eq(r.read_tag(), @pbf.tag(4, @pbf.WIRE_LEN))
  let v = r.read_bytes()
  assert_eq(v.start_offset(), 8)
  assert_eq(v.to_owned(), b"\x07\x08\x09")
  assert_true(r.at_end() && !r.failed())
}

///|
test "enter and exit narrow the reader in place, skipping unread fields" {
  let r = reader(nested())
  ignore(r.read_tag())
  let token = r.enter()
  assert_eq(r.remaining(), 4)
  ignore(r.read_tag())
  assert_eq(r.read_varint32(), 42)
  r.exit(token)
  assert_eq(r.read_tag(), @pbf.tag(4, @pbf.WIRE_LEN))
}

///|
test "reset repositions a reader and rejects bounds outside the buffer" {
  let r = reader(nested())
  r.reset(3, 4)
  assert_eq(r.read_varint32(), 42)
  assert_true(r.at_end() && !r.failed())
  r.reset(5, 100)
  assert_true(r.at_end())
  assert_eq(r.error(), Some(LengthOutOfRange(pos=5, 95)))
  r.reset(0, 1)
  assert_false(r.failed())
}

///|
test "skip handles every wire type" {
  let w = @pbf.Writer::new()
  w.write_tag(1, @pbf.WIRE_VARINT)
  w.write_varint(300UL)
  w.write_tag(2, @pbf.WIRE_FIXED64)
  w.write_fixed64(1UL)
  w.write_tag(3, @pbf.WIRE_LEN)
  w.write_string("skip me")
  w.write_tag(4, @pbf.WIRE_FIXED32)
  w.write_fixed32(1U)
  w.write_tag(5, @pbf.WIRE_VARINT)
  w.write_varint(7UL)
  let r = reader(w.to_bytes())
  for _ in 0..<4 {
    r.skip(r.read_tag())
  }
  assert_eq(r.read_tag(), @pbf.tag(5, @pbf.WIRE_VARINT))
  assert_eq(r.read_varint32(), 7)
  assert_false(r.failed())
}

///|
test "lengths beyond the buffer and group wire types are errors" {
  let r = reader([0x1a, 0x05, 0x01])
  ignore(r.read_tag())
  assert_true(r.read_bytes().is_empty())
  assert_eq(r.error(), Some(LengthOutOfRange(pos=1, 5)))
  let g = reader([0x0b])
  assert_eq(g.read_tag(), 0)
  assert_eq(g.error(), Some(UnsupportedWireType(pos=0, 3)))
  let e = reader([0x1a, 0x05, 0x01])
  ignore(e.read_tag())
  ignore(e.enter())
  assert_true(e.at_end() && e.failed())
}
