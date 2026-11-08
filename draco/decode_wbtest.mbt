///|
fn buffer_of(bytes : Array[Int32]) -> Buffer {
  let b = Buffer::new(
    FixedArray::makei(bytes.length(), i => bytes[i].to_byte()),
    0,
    bytes.length(),
  )
  b.version = bitstream(2, 2)
  b
}

///|
test "Buffer::varint: at most five bytes, mod 2^32" {
  assert_eq(buffer_of([0xac, 0x02]).varint(), 300)
  assert_eq(buffer_of([0xff, 0xff, 0xff, 0xff, 0x7f]).varint(), -1)
  let long = buffer_of([0x80, 0x80, 0x80, 0x80, 0x80, 0x01])
  let _ = long.varint()
  assert_true(long.failed)
  let short = buffer_of([0x80])
  let _ = short.varint()
  assert_true(short.failed)
  assert_eq(
    buffer_of([0x81, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]).varint64(),
    0x8000000000000001UL,
  )
}

///|
test "Buffer: reads fail without moving, bits past the end read as 0" {
  let b = buffer_of([1, 2, 3])
  assert_eq(b.u16(), 0x201)
  let _ = b.u32()
  assert_true(b.failed)
  assert_eq(b.pos, 2)
  let _ = b.start_bits(false)
  assert_eq(b.bits(8), 3)
  assert_eq(b.bits(4), 0)
  b.end_bits()
  assert_eq(b.pos, 3)
}

///|
test "decode_symbols: unknown schemes, empty tables and bit lengths past 18 fail" {
  let out = FixedArray::make(4, 0)
  assert_true(decode_symbols(0, 1, buffer_of([]), out))
  assert_false(decode_symbols(1, 1, buffer_of([2]), out))
  assert_false(decode_symbols(1, 1, buffer_of([1, 19]), out))
  assert_false(decode_symbols(1, 1, buffer_of([1, 1, 0]), out))
  assert_false(decode_symbols(1, 1, buffer_of([0, 0]), out))
}

///|
test "SymbolDecoder: a one-symbol table decodes that symbol" {
  let b = buffer_of([1, 1, 0x40, 1, 0x00])
  let d = SymbolDecoder::new(b.data, 2)
  assert_true(d.create(b))
  assert_eq(d.num_symbols, 1)
  assert_true(d.start(b))
  assert_eq(d.symbol(), 0)
}

///|
test "BitDecoder::start: sizes past the buffer and bad state bytes fail" {
  let d = BitDecoder::new([])
  assert_false(d.start(buffer_of([0, 5, 0])))
  assert_false(d.start(buffer_of([0, 1, 0xc0])))
  assert_false(d.start(buffer_of([0, 0])))
  assert_true(d.start(buffer_of([128, 1, 0x00])))
}

///|
test "int_sqrt: floor of the square root" {
  assert_eq(int_sqrt(0), 0)
  assert_eq(int_sqrt(15), 3)
  assert_eq(int_sqrt(16), 4)
  assert_eq(int_sqrt(0xffffffffffffffffUL), 0xffffffffUL)
}

///|
test "Toolbox::set_bits: 2 to 30 bits" {
  let tb = Toolbox::new()
  assert_false(tb.set_bits(1))
  assert_false(tb.set_bits(31))
  assert_true(tb.set_bits(8))
  assert_eq((tb.max_quantized, tb.max_value, tb.center), (255, 254, 127))
}

///|
test "Transform::set_max_quantized: odd values only" {
  let t = Transform::new(TRANSFORM_OCTAHEDRON)
  assert_false(t.set_max_quantized(256))
  assert_false(t.set_max_quantized(-1))
  assert_true(t.set_max_quantized(255))
  assert_eq(t.bits(), 8)
}

///|
test "to_int_or_min: NaN and out of range give INT_MIN" {
  assert_eq(to_int_or_min(0.0 / 0.0), -2147483648)
  assert_eq(to_int_or_min(3.0e9), -2147483648)
  assert_eq(to_int_or_min(-7.0), -7)
}

///|
test "Names::add: one name per parent" {
  let data : FixedArray[Byte] = [b'a', b'b', b'a']
  let names : Names = {
    parent: [],
    start: [],
    len: [],
    slots: FixedArray::make(2, -1),
  }
  assert_true(names.add(data, 0, 0, 1))
  assert_true(names.add(data, 0, 1, 1))
  assert_false(names.add(data, 0, 2, 1))
  assert_true(names.add(data, 1, 2, 1))
}
