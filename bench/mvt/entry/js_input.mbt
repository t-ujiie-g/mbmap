///|
/// `bytes` is the tile's Uint8Array; the js backend reads it without copying.
#export_name("decode_bytes")
pub fn decode_bytes(bytes : Bytes) -> Int32 {
  decode_all(bytes[:])
}
