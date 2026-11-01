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

///|
/// `table_tiler` on a `@geom.Table::to_bytes` Uint8Array (pipeline B).
#export_name("geojson_tiler_table")
pub fn geojson_tiler_table(
  bytes : Bytes,
  max_zoom : Int32,
  index_max_zoom : Int32,
  index_max_points : Int32,
  tolerance : Double,
  extent : Int32,
  buffer : Int32,
  wrap : Bool,
) -> Int32 {
  table_tiler(
    bytes[:],
    {
      max_zoom,
      index_max_zoom,
      index_max_points,
      tolerance,
      extent,
      buffer,
      wrap,
    },
    @tiler.Trig::moonbit(),
  )
}

///|
/// `clip_words` on input i32s in a Uint8Array, as comma-separated i32s.
#export_name("clip_bytes")
pub fn clip_bytes(
  bytes : Bytes,
  op : Int32,
  fill : Int32,
  tree : Int32,
) -> String {
  clip_words(words_of(bytes[:]), op, fill, tree=tree != 0)
  .map(v => v.to_string())
  .join(",")
}

///|
/// `offset_words` on input i32s in a Uint8Array, as comma-separated i32s.
#export_name("offset_bytes")
pub fn offset_bytes(
  bytes : Bytes,
  delta : Double,
  join : Int32,
  end : Int32,
  miter_limit : Double,
  arc_tolerance : Double,
) -> String {
  offset_words(words_of(bytes[:]), delta, join, end, miter_limit, arc_tolerance)
  .map(v => v.to_string())
  .join(",")
}

///|
/// `proj_coords` on a Uint8Array, as comma-separated numbers.
#export_name("proj_bytes")
pub fn proj_bytes(bytes : Bytes, from : Int32, to : Int32) -> String {
  proj_coords(bytes[:], from, to).map(v => v.to_string()).join(",")
}
