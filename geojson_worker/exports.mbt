///|
/// `@geojson_tiles.load` (docs/FORMATS.md "GeoJSON worker messages").
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
  @geojson_tiles.load(
    source, max_zoom, buffer, tolerance, line_metrics, cluster, cluster_max_zoom,
    cluster_radius, cluster_min_points,
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
