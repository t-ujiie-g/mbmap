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

///|
/// `build_tiler` on the GeoJSON's UTF-8 Uint8Array.
#export_name("geojson_tiler")
pub fn geojson_tiler(
  bytes : Bytes,
  max_zoom : Int32,
  index_max_zoom : Int32,
  index_max_points : Int32,
  tolerance : Double,
  extent : Int32,
  buffer : Int32,
  wrap : Bool,
) -> Int32 {
  build_tiler(
    bytes[:],
    max_zoom,
    index_max_zoom,
    index_max_points,
    tolerance,
    extent,
    buffer,
    wrap,
    @tiler.Trig::moonbit(),
  )
}

///|
/// `read_only` on the GeoJSON's UTF-8 Uint8Array.
#export_name("geojson_read")
pub fn geojson_read(bytes : Bytes) -> Int32 {
  read_only(bytes[:])
}
