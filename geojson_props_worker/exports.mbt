///|
/// The host's `Math`, `Number`, `String` and `Intl`, as the display worker's.
let hooks : @cluster_props.Hooks = {
  trig: @wasmio.host_trig(),
  number_text: @wasmio.host_number_to_text,
  text_number: @wasmio.host_text_to_number,
  intl: {
    number_format: @wasmio.host_number_format,
    collate: @wasmio.host_collate,
    resolved_locale: @wasmio.host_resolved_locale,
  },
}

///|
/// The cluster properties the next `load` takes.
let properties : Ref[Array[(String, @style.Expr, @style.Expr)]] = Ref([])

///|
/// Reads the input as cluster properties (`@style.write_cluster_properties`) for the
/// next `load`; 0, or -1 if they are malformed.
#export_name("set_properties")
pub fn set_properties() -> Int32 {
  match @style.read_cluster_properties(@wasmio.input_bytes()[:]) {
    Some(p) => {
      properties.val = p
      0
    }
    None => -1
  }
}

///|
/// `@geojson_tiles.load`, clusters taking the properties `set_properties` read
/// since the last `load` (none if it was not called).
#export_name("load")
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
) -> Int32 {
  let props = properties.val
  properties.val = []
  @geojson_tiles.load(
    source,
    max_zoom,
    buffer,
    tolerance,
    line_metrics,
    cluster,
    cluster_max_zoom,
    cluster_radius,
    cluster_min_points,
    hooks.trig,
    @wasmio.input_number,
    properties?=match props {
      [] => None
      props =>
        Some(table => @cluster_props.cluster_properties(table, props, hooks~))
    },
  )
}

///|
#export_name("tile")
pub fn tile(source : Int32, z : Int32, x : Int32, y : Int32) -> Int32 {
  @geojson_tiles.tile(source, z, x, y)
}

///|
#export_name("clustered")
pub fn clustered(source : Int32) -> Int32 {
  @geojson_tiles.clustered(source)
}

///|
#export_name("cluster_expansion_zoom")
pub fn cluster_expansion_zoom(source : Int32, id : Int32) -> Int32 {
  @geojson_tiles.cluster_expansion_zoom(source, id)
}

///|
#export_name("cluster_children")
pub fn cluster_children(source : Int32, id : Int32) -> Int32 {
  @geojson_tiles.cluster_children(source, id)
}

///|
#export_name("cluster_leaves")
pub fn cluster_leaves(
  source : Int32,
  id : Int32,
  limit : Int32,
  offset : Int32,
) -> Int32 {
  @geojson_tiles.cluster_leaves(source, id, limit, offset)
}

///|
#export_name("unload")
pub fn unload(source : Int32) -> Unit {
  @geojson_tiles.unload(source)
}
