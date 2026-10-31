///|
/// Decodes zigzag varint (dx, dy) pairs from the first `len` bytes of `src`,
/// accumulating them like MVT geometry deltas, and returns the floats written.
/// `out` must have room for every decoded value.
pub fn decode_deltas(
  src : FixedArray[Byte],
  len : Int32,
  out : FixedArray[Float],
) -> Int32 {
  let mut pos = 0
  let mut n = 0
  let mut x = 0
  let mut y = 0
  while pos < len {
    let mut b = src[pos].to_int()
    pos += 1
    let mut v = b & 0x7f
    let mut shift = 7
    while b >= 0x80 {
      b = src[pos].to_int()
      pos += 1
      v = v | ((b & 0x7f) << shift)
      shift += 7
    }
    let d = (v >> 1) ^ -(v & 1)
    if (n & 1) == 0 {
      x += d
      out[n] = Float::from_int(x)
    } else {
      y += d
      out[n] = Float::from_int(y)
    }
    n += 1
  }
  n
}
