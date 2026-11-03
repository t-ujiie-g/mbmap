///|
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// Compiles the style JSON placed as input (`@style.Style::to_compiled`).
/// Returns the output's length, or minus an error message's.
#export_name("compile_style")
pub fn compile_style() -> Int32 {
  let input = @wasmio.input_bytes()
  try @style.Style::from_json(@core.parse_json(input[:]), strict=false) catch {
    e => @wasmio.fail_with(e.to_string())
  } noraise {
    s => @wasmio.write_bytes(s.to_compiled()[:])
  }
}
