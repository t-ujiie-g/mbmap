// Exports shared by every backend: MoonBit-owned buffers in, MoonBit-owned
// buffers out. How JS reaches those buffers is what differs per backend.

///|
pub fn alloc_bytes(n : Int32) -> FixedArray[Byte] {
  FixedArray::make(n, b'\x00')
}

///|
pub fn alloc_floats(n : Int32) -> FixedArray[Float] {
  FixedArray::make(n, 0.0)
}

///|
pub fn decode(
  src : FixedArray[Byte],
  len : Int32,
  out : FixedArray[Float],
) -> Int32 {
  @kernel.decode_deltas(src, len, out)
}

///|
/// Element accessor for backends where JS cannot see MoonBit arrays directly.
pub fn get_f32(a : FixedArray[Float], i : Int32) -> Float {
  a[i]
}

///|
/// Element setter for backends where JS cannot see MoonBit arrays directly.
pub fn set_u8(a : FixedArray[Byte], i : Int32, v : Int32) -> Unit {
  a[i] = v.to_byte()
}

///|
pub fn alloc_churn(features : Int32, ring : Int32) -> Int32 {
  @kernel.alloc_churn(features, ring)
}
