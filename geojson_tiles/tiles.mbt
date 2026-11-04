///|
/// Largest GeoJSON accepted (AGENTS.md §8.2: limit the size before tiling).
pub const MAX_GEOJSON_BYTES : Int32 = 256 * 1024 * 1024

///|
/// The JSON number at `[addr, addr + len)` of linear memory, by the host's
/// `Number()`: correctly rounded like strconv, which it keeps out of the module.
fn host_number(addr : Int32, len : Int32) -> Double = "host" "number"

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
/// Reads the input GeoJSON as source `source` with its options (pixels; 1 for `line_metrics`
/// and `cluster`, docs/FORMATS.md; `properties` for clusters). Returns the feature count, or
/// minus the length of a UTF-8 error message at `output_addr`.
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
  properties? : (@geom.Table) -> @tiler.ClusterProperties,
) -> Int32 {
  let table = @formats.read_geojson(@wasmio.input_bytes()[:], slow_number=(s, e) => {
    host_number(@wasmio.PAGE + s, e - s)
  }) catch {
    e => return @wasmio.fail_with(e.message())
  }
  let buffer = (buffer * units_per_pixel).round().to_int()
  // The host's `Math`: projections then match geojson-vt bit for bit.
  let trig = @wasmio.host_trig()
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
    Tiles(@tiler.Tiler::new(table, options~, trig~))
  }
  sources[source] = (table, index)
  table.length()
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
