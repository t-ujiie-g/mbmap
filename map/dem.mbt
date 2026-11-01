///|
/// A `raster-dem` tile's border elevations (`@raster.dem_edges`), kept so its
/// neighbors' edge slopes can be redone when either arrives.
priv struct DemTile {
  edges : FixedArray[Double]
  size : Int32
}

///|
extern "js" fn f64_array(
  buffer : @render_webgl2.JsBuffer,
) -> FixedArray[Double] =
  #|(b) => Array.from(b)

///|
fn dem_of(meshes : Array[LayerMesh]) -> (@render_webgl2.Mesh, DemTile)? {
  for m in meshes {
    if m.dem is Some(d) {
      return Some((m.mesh, d))
    }
  }
  None
}

///|
/// Redoes the edge slopes between `id` and its loaded neighbors on both sides of
/// each shared edge, so a hillshade shows no seams (MapLibre backfills borders
/// the same way). Sides are 0 top, 1 bottom, 2 left, 3 right.
fn Map::stitch_dem(self : Map, src : SourceTiles, id : @core.TileId) -> Unit {
  guard src.ready(id).bind(dem_of) is Some((mesh, own)) else { return }
  let n = 1 << id.z
  let neighbors = [(0, 0, -1, 1), (1, 0, 1, 0), (2, -1, 0, 3), (3, 1, 0, 2)]
  for s in neighbors {
    let (side, dx, dy, opposite) = s
    let y = id.y + dy
    guard y >= 0 && y < n else { continue }
    let x = (id.x + dx + n) % n
    guard @core.TileId::new(id.z, x, y) is Some(nid) &&
      src.ready(nid).bind(dem_of) is Some((nmesh, other)) &&
      other.size == own.size else {
      continue
    }
    self.renderer.update_slopes(
      mesh,
      side,
      @raster.edge_slopes(own.edges, other.edges, side, own.size, id.z),
    )
    self.renderer.update_slopes(
      nmesh,
      opposite,
      @raster.edge_slopes(other.edges, own.edges, opposite, own.size, id.z),
    )
  }
}
