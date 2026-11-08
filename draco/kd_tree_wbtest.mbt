///|
/// The bytes of a direct bit decoder over `words` (its size, then each word little-endian).
fn direct_stream(words : Array[UInt32]) -> Array[Int32] {
  let out = []
  let size = 4 * words.length()
  out.append([size & 0xff, (size >> 8) & 0xff, 0, 0])
  for w in words {
    let v = w.reinterpret_as_int()
    out.append([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff])
  }
  out
}

///|
test "DirectBits: bits from the top of each word, across words, false past the end" {
  let d = DirectBits::start(
    buffer_of(direct_stream([0xa0000003U, 0xc0000000U])),
  ).unwrap()
  assert_true(d.bits(3))
  assert_eq(d.value, 5)
  assert_true(d.bits(28))
  assert_eq(d.value, 1)
  assert_true(d.bits(3))
  assert_eq(d.value, 0b111)
  assert_false(d.next_bit())
  assert_true(d.bits(29))
  assert_eq(d.value, 0)
  assert_false(d.bits(1))
  assert_eq(d.value, 0)
  assert_false(d.next_bit())
}

///|
test "DirectBits::start: sizes of zero, not a multiple of 4 or past the buffer fail" {
  assert_true(DirectBits::start(buffer_of([0, 0, 0, 0])) is None)
  assert_true(DirectBits::start(buffer_of([2, 0, 0, 0, 1, 2])) is None)
  assert_true(DirectBits::start(buffer_of([8, 0, 0, 0, 1, 2, 3, 4])) is None)
}

///|
test "KdOut::put: writes the points that fit, counts them all, stops collecting past the limit" {
  let bytes = FixedArray::make(4, b'\x00')
  let out = KdOut::to_attributes([
    {
      bytes,
      ints: [],
      portable: false,
      offset: 1,
      data_size: 2,
      nc: 1,
      size: 2,
    },
  ])
  assert_true(out.put([0U, 0x1234U], 5))
  assert_eq(out.count, 5)
  assert_eq(bytes, [b'\x34', b'\x12', b'\x34', b'\x12'])
  let collect = KdOut::collecting(2)
  assert_true(collect.put([1U, 2U, 3U], 2))
  assert_false(collect.put([1U, 2U, 3U], 1))
  assert_true(collect.over)
  assert_eq(collect.collected, [1U, 2U, 3U, 1U, 2U, 3U])
}

///|
test "decode_kd_points: a chain of single halves ends at the last level" {
  // 1023 points whose numbers are all ones split into nothing and themselves at every level, down
  // to 32 levels of each of 64 axes; then all are put at once.
  let words = Array::make(600, 0xffffffffU)
  let bytes = [32, 0, 0, 0, 0xff, 0x03, 0, 0]
  bytes.append(direct_stream(words))
  for _ in 0..<3 {
    bytes.append(direct_stream([0U]))
  }
  let out = KdOut::to_attributes([])
  assert_true(decode_kd_points(buffer_of(bytes), 0, 64, 0xffffffffU, out))
  assert_eq(out.count, 1023)
}

///|
test "signed_of_symbol: even symbols are positive, odd negative" {
  assert_eq(signed_of_symbol(0), 0)
  assert_eq(signed_of_symbol(1), -1)
  assert_eq(signed_of_symbol(4), 2)
  assert_eq(signed_of_symbol(-1), -0x80000000)
}
