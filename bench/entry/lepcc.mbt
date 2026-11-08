///|
/// `@lepcc.decode` of all of `src` as `kind` (0 xyz, 1 rgb, 2 intensity) laid out as
/// docs/FORMATS.md "LEPCC output", or no bytes when it gives None.
#export_name("lepcc_decode")
pub fn lepcc_decode(kind : Int32, src : FixedArray[Byte]) -> FixedArray[Byte] {
  let kinds : FixedArray[@lepcc.BlobType] = [Xyz, Rgb, Intensity]
  guard kind >= 0 && kind < 3 else { return [] }
  match @lepcc.decode(kinds[kind], src, 0, src.length()) {
    Some(out) => out
    None => []
  }
}
