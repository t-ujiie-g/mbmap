///|
/// Turns MapLibre's GeoJSON source options, in pixels, into tile units.
let units_per_pixel : Double = @core.TILE_EXTENT.to_double() / @core.TILE_SIZE

///|
/// How a source is cut into tiles: as it is, or its points clustered.
priv enum Index {
  Tiles(@tiler.Tiler)
  Clusters(@tiler.ClusterIndex)
}

///|
/// Each loaded source's table and index, by the number the host gave it.
let sources : Map[Int32, (@geom.Table, Index)] = Map([])

///|
/// Reads the input (`promoteId`, GeoJSON) as source `source` with its options (docs/FORMATS.md
/// "GeoJSON worker messages"; `properties` for clusters; the host's `trig`, `slow_number`). Returns
/// the feature count, or minus the length of a UTF-8 error message at `output_addr`.
pub fn load(
  source : Int32,
  max_zoom : Int32,
  buffer : Double,
  tolerance : Double,
  line_metrics : Int32,
  cluster : Int32,
  cluster_max_zoom : Int32,
  cluster_radius : Double,
  cluster_min_points : Int32,
  trig : @core.Trig,
  slow_number : (Int32, Int32) -> Double,
  properties? : (@geom.Table) -> @tiler.ClusterProperties,
) -> Int32 {
  // The style's ranges (style/source.mbt), which the facade clamps to.
  if !(max_zoom >= 0 &&
    max_zoom <= @tiler.MAX_ZOOM &&
    buffer >= 0.0 &&
    buffer <= 512.0 &&
    tolerance >= 0.0 &&
    tolerance < 1.0e9 &&
    cluster_max_zoom <= 30) {
    return @wasmio.fail_with("source options out of range")
  }
  let input = @wasmio.input_bytes()
  guard split_input(input) is Some((at, head)) else {
    return @wasmio.fail_with("malformed input")
  }
  let promote_id = match @core.utf8_lossy(head) {
    "" => None
    k => Some(k)
  }
  let (table, feature_ends) = read_features(
    input,
    at,
    input.length(),
    slow_number,
  ) catch {
    e => return @wasmio.fail_with(e.message())
  }
  let buffer = (buffer * units_per_pixel).round().to_int()
  let index = if cluster != 0 {
    let options : @tiler.ClusterOptions = {
      ..@tiler.ClusterOptions::default(),
      max_zoom: cluster_max_zoom,
      min_points: cluster_min_points,
      radius: cluster_radius * units_per_pixel,
      extent: @core.TILE_EXTENT,
    }
    let wrap_buffer = buffer.to_double() / @core.TILE_EXTENT.to_double()
    Clusters(
      @tiler.ClusterIndex::new(
        table,
        options~,
        wrap_buffer~,
        trig~,
        properties?=properties.map(f => f(table)),
        feature_ends~,
        promote_id?,
      ),
    )
  } else {
    let options : @tiler.TilerOptions = {
      ..@tiler.TilerOptions::default(),
      max_zoom,
      buffer,
      tolerance: tolerance * units_per_pixel,
      line_metrics: line_metrics != 0,
    }
    Tiles(@tiler.Tiler::new(table, options~, trig~, feature_ends~, promote_id?))
  }
  sources[source] = (table, index)
  table.length()
}

///|
/// The input's leading part, a u32 length and that many bytes: where what
/// follows starts, and the part. None if it does not fit.
fn split_input(input : Bytes) -> (Int32, BytesView)? {
  let r = @core.ByteReader::new(input[:])
  let n = r.u32()
  guard r.ok() && n >= 0 && n <= r.remaining() else { return None }
  Some((4 + n, input[4:4 + n]))
}

///|
/// The GeoJSON in bytes `from` to `to` of the input and where its features end.
fn read_features(
  input : Bytes,
  from : Int32,
  to : Int32,
  slow_number : (Int32, Int32) -> Double,
) -> (@geom.Table, Array[Int32]) raise @formats.GeoJSONError {
  @formats.read_geojson_features(input[from:to], (s, e) => {
    slow_number(s + from, e + from)
  })
}

///|
/// Applies the input, a diff (docs/FORMATS.md "GeoJSON diff"), to source `source`
/// as geojson-vt's `updateData` does. Returns 1 if it changed the source, 0 if
/// not, or minus the length of an error message at `output_addr`.
pub fn update(source : Int32, slow_number : (Int32, Int32) -> Double) -> Int32 {
  guard sources.get(source) is Some((_, index)) else {
    return @wasmio.fail_with("source not loaded")
  }
  let input = @wasmio.input_bytes()
  guard split_input(input) is Some((at, _)) else {
    return @wasmio.fail_with("malformed diff")
  }
  let (table, ends) = read_features(input, 4, at, slow_number) catch {
    e => return @wasmio.fail_with(e.message())
  }
  guard @tiler.Diff::read(input[at:], table, ends) is Some(diff) else {
    return @wasmio.fail_with("malformed diff")
  }
  let changed = match index {
    Tiles(t) => t.update(diff)
    Clusters(c) => c.update(diff)
  }
  if changed {
    1
  } else {
    0
  }
}

///|
/// Cuts tile (z, x, y) of source `source` and writes it, encoded, at
/// `output_addr`. Returns its length, 0 if the source has no features
/// there, -1 if the source is not loaded or -2 if memory ran out.
pub fn tile(source : Int32, z : Int32, x : Int32, y : Int32) -> Int32 {
  guard sources.get(source) is Some((table, index)) else { return -1 }
  @wasmio.clear_input()
  match index {
    Tiles(tiler) =>
      match tiler.tile(z, x, y) {
        None => 0
        Some(d) if d.types.is_empty() => 0
        Some(d) => @wasmio.write_bytes(@tiler.encode_tile(d, table)[:])
      }
    Clusters(clusters) =>
      match clusters.tile(z, x, y) {
        None | Some([]) => 0
        Some(fs) =>
          @wasmio.write_bytes(@tiler.encode_cluster_tile(fs, table)[:])
      }
  }
}

///|
/// Whether source `source` clusters its points: 1 if so, 0 if not, -1 if
/// it is not loaded.
pub fn clustered(source : Int32) -> Int32 {
  match sources.get(source) {
    Some((_, Clusters(_))) => 1
    Some(_) => 0
    None => -1
  }
}

///|
/// The zoom at which cluster `id` of source `source` breaks apart (0 if the
/// source does not cluster; see `clustered`).
pub fn cluster_expansion_zoom(source : Int32, id : Int32) -> Int32 {
  match sources.get(source) {
    Some((_, Clusters(c))) => c.expansion_zoom(id)
    _ => 0
  }
}

///|
/// Writes `fs` at `output_addr` as docs/FORMATS.md's "Cluster features" and
/// returns their length; -1 if there are none (no such cluster), -2 if
/// memory ran out.
fn write_features(
  source : Int32,
  f : (@tiler.ClusterIndex) -> Array[@tiler.ClusterFeature]?,
) -> Int32 {
  guard sources.get(source) is Some((table, Clusters(c))) && f(c) is Some(fs) else {
    return -1
  }
  @wasmio.clear_input()
  @wasmio.write_bytes(@tiler.encode_cluster_features(fs, table)[:])
}

///|
/// The children of cluster `id` of source `source`, as `write_features`.
pub fn cluster_children(source : Int32, id : Int32) -> Int32 {
  write_features(source, c => c.children(id))
}

///|
/// Up to `limit` (none if negative) of the points of cluster `id` of source
/// `source` after the first `offset`, as `write_features`.
pub fn cluster_leaves(
  source : Int32,
  id : Int32,
  limit : Int32,
  offset : Int32,
) -> Int32 {
  write_features(source, c => c.leaves(id, limit~, offset~))
}

///|
/// Forgets source `source` (it left the style or was loaded again under
/// another number).
pub fn unload(source : Int32) -> Unit {
  sources.remove(source)
}
