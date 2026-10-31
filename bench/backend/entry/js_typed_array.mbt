///|
#external
type Float32Array

///|
extern "js" fn f32_set(a : Float32Array, i : Int32, v : Float) =
  #|(a, i, v) => { a[i] = v; }

///|
/// Same algorithm as `@kernel.decode_deltas`, writing into a JS typed array.
#export_name("decode_f32")
pub fn decode_f32(
  src : FixedArray[Byte],
  len : Int32,
  out : Float32Array,
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
      f32_set(out, n, Float::from_int(x))
    } else {
      y += d
      f32_set(out, n, Float::from_int(y))
    }
    n += 1
  }
  n
}
