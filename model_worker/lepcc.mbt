///|
/// LEPCC blob types in the order `model_worker/js/decode.mjs` numbers them.
let lepcc_kinds : FixedArray[@lepcc.BlobType] = [Xyz, Rgb, Intensity]

///|
/// Decodes the input, an I3S point cloud's LEPCC blob of `kind` (0 xyz, 1 rgb, 2 intensity),
/// into the output as docs/FORMATS.md "LEPCC output"; returns its length, -1 for blobs Esri's
/// decoder refuses (or past `@lepcc.MAX_POINTS`), -2 without memory.
#export_name("lepcc_decode")
pub fn lepcc_decode(kind : Int32) -> Int32 {
  guard kind >= 0 && kind < lepcc_kinds.length() else { return -1 }
  let source = @wasmio.input_byte_array()
  guard @lepcc.decode(lepcc_kinds[kind], source, 0, source.length())
    is Some(out) else {
    return -1
  }
  @wasmio.write_bytes(out.unsafe_reinterpret_as_bytes()[:])
}
