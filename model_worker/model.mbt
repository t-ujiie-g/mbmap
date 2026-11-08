///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// meshopt's modes and filters in the order `model_worker/js/worker.mjs`
/// numbers them.
let modes : FixedArray[@meshopt.Mode] = [Attributes, Triangles, Indices]

///|
let filters : FixedArray[@meshopt.Filter] = [
  NoFilter,
  Octahedral,
  Quaternion,
  Exponential,
  Color,
]

///|
/// Decodes the input, a meshopt-compressed glTF buffer view of `count`
/// elements of `size` bytes, into the output (`mode` and `filter` numbered as
/// `modes` and `filters`); returns its length, -1 for malformed input, -2
/// without memory.
#export_name("meshopt_decode")
pub fn meshopt_decode(
  count : Int32,
  size : Int32,
  mode : Int32,
  filter : Int32,
) -> Int32 {
  guard mode >= 0 &&
    mode < modes.length() &&
    filter >= 0 &&
    filter < filters.length() &&
    count >= 0 &&
    size > 0 &&
    @wasmio.output_fits(count.to_int64(), size) else {
    return -1
  }
  let target = FixedArray::make(count * size, b'\x00')
  let source = @wasmio.input_byte_array()
  guard @meshopt.decode_gltf_buffer(
    target,
    count,
    size,
    source,
    0,
    source.length(),
    modes[mode],
    filters[filter],
  ) else {
    return -1
  }
  @wasmio.write_bytes(target.unsafe_reinterpret_as_bytes()[:])
}
