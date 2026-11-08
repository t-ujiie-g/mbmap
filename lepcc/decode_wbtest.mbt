///|
fn wb_hex(s : String) -> FixedArray[Byte] {
  let out = FixedArray::make(s.length() / 2, b'\x00')
  for i in 0..<out.length() {
    let d = fn(c : Int32) {
      if c <= '9'.to_int() {
        c - '0'.to_int()
      } else {
        c - 'a'.to_int() + 10
      }
    }
    out[i] = (d(s.code_unit_at(2 * i).to_int()) * 16 +
    d(s.code_unit_at(2 * i + 1).to_int())).to_byte()
  }
  out
}

///|
fn put32(b : FixedArray[Byte], at : Int32, v : Int32) -> Unit {
  for k in 0..<4 {
    b[at + k] = ((v >> (8 * k)) & 0xff).to_byte()
  }
}

///|
/// Writes the checksum the C++ encoder would over the blob's own size.
fn reseal(b : FixedArray[Byte]) -> FixedArray[Byte] {
  let size = i64_at(b, 16).to_int()
  put32(b, 12, fletcher32(b, 16, size - 16).reinterpret_as_int())
  b
}

///|
/// An intensity blob of `values` bytes after its 32-byte header.
fn intensity_blob(
  n : Int32,
  scale : Int32,
  bpp : Int32,
  payload : Array[Int32],
) -> FixedArray[Byte] {
  let b = FixedArray::make(32 + payload.length(), b'\x00')
  let key = "Intensity "
  for i in 0..<10 {
    b[i] = key.code_unit_at(i).to_int().to_byte()
  }
  b[10] = b'\x01'
  put32(b, 16, b.length())
  put32(b, 24, n)
  b[28] = (scale & 0xff).to_byte()
  b[29] = (scale >> 8).to_byte()
  b[30] = bpp.to_byte()
  for i, v in payload {
    b[32 + i] = v.to_byte()
  }
  reseal(b)
}

///|
let wb_xyz : String = "4c455043432020202020010049f5657882000000000000006666666666766140cdcccccccccc41400000000000002440ef1b5f7b6676614014799274cdcc4140000000000000284048afbc9af2d77a3e48afbc9af2d77a3e7b14ae47e17a843f03000000000000008001870200328101018102018001860300200380018703800c19"

///|
test "fletcher32 matches Fletcher's checksum over bytes, odd lengths and long runs" {
  let b = wb_hex(wb_xyz)
  assert_eq(fletcher32(b, 16, b.length() - 16), 0x7865f549U)
  assert_eq(fletcher32(b, 0, 0), 0xffffffffU)
  assert_eq(fletcher32([b'\x01'], 0, 1), 0x01000100U)
  let long = FixedArray::make(2000, b'\xff')
  let sum = fletcher32(long, 0, 2000)
  assert_eq(sum, fletcher32(long, 0, 2000))
  assert_true(sum != fletcher32(long, 0, 1999))
}

///|
test "the bit stuffer unpacks values across word boundaries" {
  // Ten 7-bit values 0, 13, 26, ... packed from the low bits.
  let values = Array::makei(10, fn(i) { (i * 13).reinterpret_as_uint() })
  let words = FixedArray::make(3, 0U)
  for i, v in values {
    let bit = i * 7
    words[bit / 32] = words[bit / 32] | (v << (bit % 32))
    if bit % 32 + 7 > 32 {
      words[bit / 32 + 1] = words[bit / 32 + 1] | (v >> (32 - bit % 32))
    }
  }
  let data = FixedArray::make(2 + 9, b'\x00')
  data[0] = (7 | (2 << 6)).to_byte()
  data[1] = b'\x0a'
  for k in 0..<9 {
    data[2 + k] = ((words[k / 4] >> (8 * (k % 4))) & 0xffU)
      .reinterpret_as_int()
      .to_byte()
  }
  let c = { data, pos: 0, end: data.length(), }
  guard c.decode() is Some(out) else { fail("refused") }
  assert_eq(Array::makei(10, fn(i) { out[i] }), values)
  assert_eq(c.pos, 11)
  let short = { data, pos: 0, end: 10, }
  assert_true(short.decode() is None)
}

///|
test "the bit stuffer's table mode maps indexes through the table and its 0" {
  // Table [0, 9, 300] (9 bits each, the 0 left out), indexes 2 bits: 1 0 2 2 1.
  let data = [
    (9 | 32 | (2 << 6)).to_byte(),
    b'\x05',
    b'\x03',
    (9 & 0xff).to_byte(),
    ((300 << 1) & 0xff).to_byte(),
    ((300 >> 7) & 0xff).to_byte(),
    (1 | (0 << 2) | (2 << 4) | (2 << 6)).to_byte(),
    b'\x01',
  ]
  let fixed = FixedArray::from_array(data)
  let c = { data: fixed, pos: 0, end: fixed.length(), }
  guard c.decode() is Some(out) else { fail("refused") }
  assert_eq(out, [9U, 0, 300, 300, 9])
  // An index past the table is refused.
  fixed[6] = (3 | (0 << 2)).to_byte()
  assert_true({ data: fixed, pos: 0, end: fixed.length(), }.decode() is None)
  // A table size byte of 0 or 1 holds no values.
  fixed[2] = b'\x01'
  assert_true({ data: fixed, pos: 0, end: fixed.length(), }.decode() is None)
}

///|
test "the bit stuffer refuses counts past MAX_POINTS and a count size of 0" {
  let big = [b'\x00', b'\x01', b'\x00', b'\x40', b'\x00']
  let c = { data: FixedArray::from_array(big), pos: 0, end: 5, }
  assert_true(c.decode() is None)
  let empty = FixedArray::from_array([(3 << 6).to_byte(), b'\x00'])
  assert_true({ data: empty, pos: 0, end: 2, }.decode() is None)
  let zeros = FixedArray::from_array([(2 << 6).to_byte(), b'\x04'])
  guard { data: zeros, pos: 0, end: 2, }.decode() is Some(out) else {
    fail("refused")
  }
  assert_eq(out, [0U, 0, 0, 0])
  let none = FixedArray::from_array([(1 | (2 << 6)).to_byte(), b'\x00'])
  assert_true({ data: none, pos: 0, end: 2, }.decode() is None)
}

///|
test "decode_intensity decodes a table-mode array and refuses bad headers" {
  // Three values through table [0, 5]: 1 bit indexes 1 0 1, upscaled by 3.
  let lut = [3 | 32 | (2 << 6), 3, 2, 5, 5]
  let b = intensity_blob(3, 3, 3, lut)
  guard decode_intensity(b, 0, b.length()) is Some(values) else {
    fail("refused")
  }
  assert_eq(values, [15, 0, 15])
  assert_true(
    decode_intensity(intensity_blob(3, 0, 8, [1, 2, 3]), 0, 35) is None,
  )
  assert_true(
    decode_intensity(intensity_blob(3, 1, 17, [1, 2, 3]), 0, 35) is None,
  )
  assert_true(decode_intensity(intensity_blob(0, 1, 8, [1]), 0, 33) is None)
  assert_true(
    decode_intensity(intensity_blob(4, 1, 8, [1, 2, 3]), 0, 35) is None,
  )
  let b = intensity_blob(3, 300, 8, [1, 2, 255])
  guard decode_intensity(b, 0, b.length()) is Some(values) else {
    fail("refused")
  }
  assert_eq(values, [300, 600, (255 * 300) & 0xffff])
  // A bit-stuffed array of another length than the header's count.
  let two = [1 | (2 << 6), 2, 3]
  assert_true(decode_intensity(intensity_blob(3, 1, 1, two), 0, 35) is None)
}

///|
test "decode_xyz refuses resealed blobs with inconsistent counts or sizes" {
  let b = wb_hex(wb_xyz)
  let n = b.length()
  // More points in the header than the rows hold.
  let more = b.copy()
  put32(more, 96, 4)
  assert_true(decode_xyz(reseal(more), 0, n) is None)
  // Fewer.
  let fewer = b.copy()
  put32(fewer, 96, 2)
  assert_true(decode_xyz(reseal(fewer), 0, n) is None)
  // Past MAX_POINTS, and none.
  let huge = b.copy()
  put32(huge, 96, MAX_POINTS + 1)
  assert_true(decode_xyz(reseal(huge), 0, n) is None)
  let zero = b.copy()
  put32(zero, 96, 0)
  assert_true(decode_xyz(reseal(zero), 0, n) is None)
  // A blob size below the headers, or past the buffer.
  let small = b.copy()
  put32(small, 16, 50)
  assert_true(decode_xyz(small, 0, n) is None)
  let past = b.copy()
  put32(past, 16, n + 1)
  assert_true(decode_xyz(past, 0, n) is None)
  // A newer version.
  let newer = b.copy()
  newer[10] = b'\x02'
  assert_true(decode_xyz(newer, 0, n) is None)
  // Clean after all that: the original still decodes.
  assert_true(decode_xyz(b, 0, n) is Some(_))
}

///|
test "decode_rgb refuses resealed blobs with indexes past the colormap" {
  let b = wb_hex(
    "436c757374657252474201001d35963730000000000000000a00000002000100faf0e60a141e00010100010100010100",
  )
  b[40] = b'\x02'
  assert_true(decode_rgb(reseal(b), 0, b.length()) is None)
  b[40] = b'\x01'
  b[31] = b'\x02'
  assert_true(decode_rgb(reseal(b), 0, b.length()) is None)
  b[31] = b'\x00'
  assert_true(decode_rgb(reseal(b), 0, b.length()) is Some(_))
  put32(b, 24, 11)
  assert_true(decode_rgb(reseal(b), 0, b.length()) is None)
}
