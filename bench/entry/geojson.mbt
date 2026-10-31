///|
/// The tiler the geojson_* exports work on.
let current_tiler : Ref[@tiler.Tiler?] = Ref(None)

///|
/// Reads GeoJSON and indexes it with geojson-vt's options; returns the
/// feature count, or -1 if the GeoJSON is malformed.
fn build_tiler(
  bytes : BytesView,
  max_zoom : Int32,
  index_max_zoom : Int32,
  index_max_points : Int32,
  tolerance : Double,
  extent : Int32,
  buffer : Int32,
  wrap : Bool,
  trig : @tiler.Trig,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @formats.strconv_number(bytes[s:e])
  },
) -> Int32 {
  let table = @formats.read_geojson(bytes, slow_number~) catch {
    _ => return -1
  }
  let options : @tiler.TilerOptions = {
    max_zoom,
    index_max_zoom,
    index_max_points,
    tolerance,
    extent,
    buffer,
    wrap,
  }
  current_tiler.val = Some(@tiler.Tiler::new(table, options~, trig~))
  table.length()
}

///|
/// Only `@formats.read_geojson`, to separate its cost in the bench; returns
/// the feature count or -1.
fn read_only(
  bytes : BytesView,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @formats.strconv_number(bytes[s:e])
  },
) -> Int32 {
  (@formats.read_geojson(bytes, slow_number~) catch { _ => return -1 }).length()
}

///|
/// Tile (z, x, y) of the current tiler, flattened: the feature count, then
/// per feature its type, row and ring count, per ring its point count, and
/// the coordinates; an empty array for no tile.
#export_name("geojson_tile")
pub fn geojson_tile(z : Int32, x : Int32, y : Int32) -> FixedArray[Int32] {
  guard current_tiler.val is Some(t) && t.tile(z, x, y) is Some(d) else {
    return []
  }
  let out = [d.types.length()]
  let mut ring = 0
  for f in 0..<d.types.length() {
    out.push(d.types[f])
    out.push(d.rows[f])
    out.push(d.ring_ends[f] - ring)
    while ring < d.ring_ends[f] {
      let a = if ring == 0 { 0 } else { d.point_ends[ring - 1] }
      out.push(d.point_ends[ring] - a)
      ring += 1
    }
  }
  for v in d.xy {
    out.push(v)
  }
  FixedArray::from_array(out)
}

///|
/// The total length of tile (z, x, y)'s flattened form, for timing without
/// copying it out.
#export_name("geojson_tile_size")
pub fn geojson_tile_size(z : Int32, x : Int32, y : Int32) -> Int32 {
  guard current_tiler.val is Some(t) && t.tile(z, x, y) is Some(d) else {
    return 0
  }
  d.xy.length() + d.point_ends.length()
}

///|
/// FNV-1a over the 32-bit words of tile (z, x, y)'s flattened form (0 for
/// no tile), for comparing builds whose arrays JS cannot read directly.
#export_name("geojson_tile_hash")
pub fn geojson_tile_hash(z : Int32, x : Int32, y : Int32) -> Int32 {
  let flat = geojson_tile(z, x, y)
  let mut h = 0x811c9dc5
  for v in flat {
    h = (h ^ v) * 0x01000193
  }
  if flat.length() == 0 {
    0
  } else {
    h
  }
}

///|
/// `Tiler::new` on a table in `@geom.Table::to_bytes` form; returns the row
/// count or -1 if the bytes are malformed.
fn table_tiler(
  bytes : BytesView,
  options : @tiler.TilerOptions,
  trig : @tiler.Trig,
) -> Int32 {
  guard @geom.Table::from_bytes(bytes) is Some(table) else { return -1 }
  current_tiler.val = Some(@tiler.Tiler::new(table, options~, trig~))
  table.length()
}
