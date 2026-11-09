///|
/// `@draco.decode` of all of `src` as docs/FORMATS.md "Draco output", or no bytes when it
/// gives None.
#export_name("draco_decode")
pub fn draco_decode(src : FixedArray[Byte]) -> FixedArray[Byte] {
  match @draco.decode(src, 0, src.length()) {
    Some(mesh) => mesh.to_bytes().unwrap_or([])
    None => []
  }
}
