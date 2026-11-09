///|
/// Decodes the input, a Draco mesh (a KHR_draco_mesh_compression buffer view) or point cloud,
/// into the output as docs/FORMATS.md "Draco output"; returns its length, -1 for data draco3d
/// would refuse (or past `@draco`'s caps), -2 without memory.
#export_name("draco_decode")
pub fn draco_decode() -> Int32 {
  let source = @wasmio.input_byte_array()
  guard @draco.decode(source, 0, source.length()) is Some(mesh) else {
    return -1
  }
  guard mesh.to_bytes() is Some(out) else { return -2 }
  @wasmio.write_bytes(out.unsafe_reinterpret_as_bytes()[:])
}
