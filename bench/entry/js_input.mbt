///|
/// `bytes` is the tile's Uint8Array; the js backend reads it without copying.
#export_name("decode_bytes")
pub fn decode_bytes(bytes : Bytes) -> Int32 {
  decode_all(bytes[:])
}

///|
/// `tessellate_tile` on the tile's Uint8Array.
#export_name("tess_bytes")
pub fn tess_bytes(bytes : Bytes, mode : Int32) -> Int32 {
  tessellate_tile(bytes[:], mode)
}

///|
/// Per-feature fill hashes (see `fill_hash`), comma separated.
#export_name("fill_digest")
pub fn fill_digest(bytes : Bytes) -> String {
  let hashes = []
  ignore(fill_hash(bytes[:], hashes))
  hashes.map(h => h.to_string()).join(",")
}
