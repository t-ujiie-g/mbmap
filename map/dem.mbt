///|
/// A `raster-dem` tile's border elevations (`@raster.dem_edges`), kept so its
/// neighbors' edge slopes can be redone when either arrives, and its heights
/// (a Float32Array, row by row) for looking terrain up.
priv struct DemTile {
  edges : FixedArray[Double]
  heights : @render_webgl2.JsBuffer
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
  self.content_version += 1
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

///|
/// The height in meters at (`x`, `y`), fractions of the tile from its top-left
/// corner, interpolated between pixel centers as the terrain shader does.
fn DemTile::height_at(self : DemTile, x : Double, y : Double) -> Double {
  let size = self.size
  let fx = x * size.to_double() - 0.5
  let fy = y * size.to_double() - 0.5
  let at = (x : Int32, y : Int32) => {
    let cx = @cmp.maximum(0, @cmp.minimum(size - 1, x))
    let cy = @cmp.maximum(0, @cmp.minimum(size - 1, y))
    f32_at(self.heights, cy * size + cx)
  }
  let x0 = fx.floor().to_int()
  let y0 = fy.floor().to_int()
  let tx = fx - x0.to_double()
  let ty = fy - y0.to_double()
  let top = at(x0, y0) * (1.0 - tx) + at(x0 + 1, y0) * tx
  let bottom = at(x0, y0 + 1) * (1.0 - tx) + at(x0 + 1, y0 + 1) * tx
  top * (1.0 - ty) + bottom * ty
}
