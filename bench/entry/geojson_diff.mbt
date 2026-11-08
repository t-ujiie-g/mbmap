///|
/// The table the current tiler's rows are in, for `geojson_tile_bytes`.
let current_table : Ref[@geom.Table?] = Ref(None)

///|
/// Where the part after a u32 length and that many bytes starts, as the GeoJSON
/// worker's inputs begin (geojson_worker/js/diff.mjs); -1 if it does not fit.
fn after_sized(b : BytesView) -> Int32 {
  let r = @core.ByteReader::new(b)
  let n = r.u32()
  if r.ok() && n >= 0 && n <= r.remaining() {
    4 + n
  } else {
    -1
  }
}

///|
/// The GeoJSON in `b[from:to]` and its feature ends; `slow` gives the
/// `slow_number` for a part starting at an offset of `b`.
fn diff_features(
  b : BytesView,
  from : Int32,
  to : Int32,
  slow : (Int32) -> (Int32, Int32) -> Double,
) -> (@geom.Table, Array[Int32])? {
  Some(@formats.read_geojson_features(b[from:to], slow(from))) catch {
    _ => None
  }
}

///|
/// `build_tiler` on the GeoJSON worker's `load` input (`promoteId`, then the
/// GeoJSON), keeping features and their ids for `apply_diff`.
fn diff_tiler(
  b : BytesView,
  options : @tiler.TilerOptions,
  trig : @tiler.Trig,
  slow : (Int32) -> (Int32, Int32) -> Double,
) -> Int32 {
  let at = after_sized(b)
  guard at >= 0 && diff_features(b, at, b.length(), slow) is Some((table, ends)) else {
    return -1
  }
  let promote_id = if at > 4 { Some(@core.utf8_lossy(b[4:at])) } else { None }
  current_tiler.val = Some(
    @tiler.Tiler::new(table, options~, trig~, feature_ends=ends, promote_id?),
  )
  current_table.val = Some(table)
  current_clusters.val = None
  table.length()
}

///|
/// `build_clusters` on the `load` input, as `diff_tiler`.
fn diff_clusters(
  b : BytesView,
  options : @tiler.ClusterOptions,
  wrap_buffer : Double,
  trig : @tiler.Trig,
  slow : (Int32) -> (Int32, Int32) -> Double,
  properties? : Array[(String, @style.Expr, @style.Expr)],
  hooks~ : @cluster_props.Hooks = @cluster_props.Hooks::default(),
) -> Int32 {
  let at = after_sized(b)
  guard at >= 0 && diff_features(b, at, b.length(), slow) is Some((table, ends)) else {
    return -1
  }
  let promote_id = if at > 4 { Some(@core.utf8_lossy(b[4:at])) } else { None }
  let properties = properties.map(p => {
    @cluster_props.cluster_properties(table, p, hooks~)
  })
  let index = @tiler.ClusterIndex::new(
    table,
    options~,
    wrap_buffer~,
    trig~,
    properties?,
    feature_ends=ends,
    promote_id?,
  )
  current_clusters.val = Some((table, index))
  current_tiler.val = None
  table.length()
}

///|
/// Applies the GeoJSON worker's `update` input to the current tiler or cluster
/// index: 1 if it changed, 0 if not, -1 if the diff is malformed.
fn apply_diff(
  b : BytesView,
  slow : (Int32) -> (Int32, Int32) -> Double,
) -> Int32 {
  let at = after_sized(b)
  guard at >= 0 && diff_features(b, 4, at, slow) is Some((table, ends)) else {
    return -1
  }
  guard @tiler.Diff::read(b[at:], table, ends) is Some(diff) else { return -1 }
  let changed = match (current_tiler.val, current_clusters.val) {
    (Some(t), _) => t.update(diff)
    (_, Some((_, c))) => c.update(diff)
    _ => return -1
  }
  if changed {
    1
  } else {
    0
  }
}

///|
/// Tile (z, x, y) of the current tiler as the GeoJSON worker sends it
/// (`@tiler.encode_tile`); empty for none.
#export_name("geojson_tile_bytes")
pub fn geojson_tile_bytes(z : Int32, x : Int32, y : Int32) -> Bytes {
  guard current_tiler.val is Some(t) &&
    current_table.val is Some(table) &&
    t.tile(z, x, y) is Some(d) else {
    return b""
  }
  @tiler.encode_tile(d, table)
}

///|
/// FNV-1a over the bytes of `geojson_tile_bytes(z, x, y)` (0 for none).
#export_name("geojson_tile_bytes_hash")
pub fn geojson_tile_bytes_hash(z : Int32, x : Int32, y : Int32) -> Int32 {
  let bytes = geojson_tile_bytes(z, x, y)
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
