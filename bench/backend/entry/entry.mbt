///|
/// Allocates a zeroed MoonBit-owned input buffer.
#export_name("alloc_bytes")
pub fn alloc_bytes(n : Int32) -> FixedArray[Byte] {
  FixedArray::make(n, b'\x00')
}

///|
/// Allocates a zeroed MoonBit-owned output buffer.
#export_name("alloc_floats")
pub fn alloc_floats(n : Int32) -> FixedArray[Float] {
  FixedArray::make(n, 0.0)
}

///|
/// Runs `@kernel.decode_deltas` on MoonBit-owned buffers.
#export_name("decode")
pub fn decode(
  src : FixedArray[Byte],
  len : Int32,
  out : FixedArray[Float],
) -> Int32 {
  @kernel.decode_deltas(src, len, out)
}

///|
/// Element accessor for backends where JS cannot see MoonBit arrays directly.
#export_name("get_f32")
pub fn get_f32(a : FixedArray[Float], i : Int32) -> Float {
  a[i]
}

///|
/// Element setter for backends where JS cannot see MoonBit arrays directly.
#export_name("set_u8")
pub fn set_u8(a : FixedArray[Byte], i : Int32, v : Int32) -> Unit {
  a[i] = v.to_byte()
}

///|
/// Runs `@kernel.alloc_churn`.
#export_name("alloc_churn")
pub fn alloc_churn(features : Int32, ring : Int32) -> Int32 {
  @kernel.alloc_churn(features, ring)
}
