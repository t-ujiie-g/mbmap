///|
/// Largest GeoJSON accepted (AGENTS.md §8.2: limit the size before tiling).
pub const MAX_GEOJSON_BYTES : Int32 = 256 * 1024 * 1024

///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, MAX_GEOJSON_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}
