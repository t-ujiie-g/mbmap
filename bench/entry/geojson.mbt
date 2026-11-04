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
  line_metrics : Bool,
  trig : @tiler.Trig,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
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
    line_metrics,
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
    @core.strconv_number(bytes[s:e])
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
/// Tile (z, x, y)'s line metrics (`TileData::clips`), empty without them.
#export_name("geojson_tile_clips")
pub fn geojson_tile_clips(
  z : Int32,
  x : Int32,
  y : Int32,
) -> FixedArray[Double] {
  guard current_tiler.val is Some(t) && t.tile(z, x, y) is Some(d) else {
    return []
  }
  FixedArray::from_array(d.clips)
}

///|
/// FNV-1a over the 32-bit halves of `geojson_tile_clips` (low half first).
#export_name("geojson_tile_clips_hash")
pub fn geojson_tile_clips_hash(z : Int32, x : Int32, y : Int32) -> Int32 {
  let mut h = 0x811c9dc5
  for v in geojson_tile_clips(z, x, y) {
    // NaN as JavaScript writes it into a Float64Array.
    let bits = if v.is_nan() {
      0x7ff8000000000000L
    } else {
      v.reinterpret_as_int64()
    }
    h = (h ^ bits.to_int()) * 0x01000193
    h = (h ^ (bits >> 32).to_int()) * 0x01000193
  }
  h
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

///|
/// The table and cluster index the geojson_cluster* exports work on.
let current_clusters : Ref[(@geom.Table, @tiler.ClusterIndex)?] = Ref(None)

///|
/// Reads GeoJSON and clusters its points with geojson-vt's cluster options
/// (`radius` in units of an `extent`-wide tile, `wrap_buffer` a share of a
/// tile); returns the feature count, or -1 if the GeoJSON is malformed.
fn build_clusters(
  bytes : BytesView,
  max_zoom : Int32,
  min_points : Int32,
  radius : Double,
  extent : Int32,
  wrap_buffer : Double,
  wrap : Bool,
  trig : @tiler.Trig,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
  },
  properties? : Array[(String, @style.Expr, @style.Expr)],
  hooks~ : @cluster_props.Hooks = @cluster_props.Hooks::default(),
) -> Int32 {
  let table = @formats.read_geojson(bytes, slow_number~) catch {
    _ => return -1
  }
  let properties = properties.map(p => {
    @cluster_props.cluster_properties(table, p, hooks~)
  })
  let options : @tiler.ClusterOptions = {
    ..@tiler.ClusterOptions::default(),
    max_zoom,
    min_points,
    radius,
    extent,
    wrap,
  }
  current_clusters.val = Some(
    (
      table,
      @tiler.ClusterIndex::new(
        table,
        options~,
        wrap_buffer~,
        trig~,
        properties?,
      ),
    ),
  )
  table.length()
}

///|
/// An answer of the current cluster index, encoded: `op` 0 is tile
/// (a, b, c) as a columnar tile, 1 the children of cluster a, 2 its leaves
/// (limit b, offset c) as cluster features. Empty for None.
#export_name("geojson_cluster")
pub fn geojson_cluster(op : Int32, a : Int32, b : Int32, c : Int32) -> Bytes {
  guard current_clusters.val is Some((table, index)) else { return b"" }
  match op {
    0 =>
      match index.tile(a, b, c) {
        Some(fs) => @tiler.encode_cluster_tile(fs, table)
        None => b""
      }
    1 =>
      match index.children(a) {
        Some(fs) => @tiler.encode_cluster_features(fs, table)
        None => b""
      }
    _ =>
      match index.leaves(a, limit=b, offset=c) {
        Some(fs) => @tiler.encode_cluster_features(fs, table)
        None => b""
      }
  }
}

///|
/// FNV-1a over the bytes of `geojson_cluster(op, a, b, c)` (0 for none).
#export_name("geojson_cluster_hash")
pub fn geojson_cluster_hash(
  op : Int32,
  a : Int32,
  b : Int32,
  c : Int32,
) -> Int32 {
  let bytes = geojson_cluster(op, a, b, c)
  let mut h = 0x811c9dc5
  for v in bytes {
    h = (h ^ v.to_int()) * 0x01000193
  }
  if bytes.length() == 0 {
    0
  } else {
    h
  }
}

///|
/// The expansion zoom of cluster `id` in the current cluster index.
#export_name("geojson_cluster_expansion")
pub fn geojson_cluster_expansion(id : Int32) -> Int32 {
  match current_clusters.val {
    Some((_, index)) => index.expansion_zoom(id)
    None => 0
  }
}
