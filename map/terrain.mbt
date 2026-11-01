///|
/// Pixels per side of the texture a terrain tile's map is drawn into.
const TERRAIN_TEXTURE : Int32 = 512

///|
/// How far terrain skirts hang below tile edges, in meters.
const SKIRT_METERS : Double = 300.0

///|
/// Offscreen targets kept beyond those drawn this frame.
const MAX_SPARE_TARGETS : Int32 = 32

///|
/// One tile's meshes and where they go this frame.
priv struct Draw {
  id : @core.TileId
  at : @render_webgl2.Placement
  meshes : Array[LayerMesh]
}

///|
extern "js" fn f32_index(buffer : @render_webgl2.JsBuffer, i : Int32) -> Double =
  #|(b, i) => b[i]

///|
/// Whether one tile lies inside the other (quadtree tiles overlap no other way).
fn overlap(a : @core.TileId, b : @core.TileId) -> Bool {
  let z = @cmp.minimum(a.z, b.z)
  a.x >> (a.z - z) == b.x >> (b.z - z) && a.y >> (a.z - z) == b.y >> (b.z - z)
}

///|
fn Map::terrain_source(self : Map) -> SourceTiles? {
  guard self.style.terrain is Some(t) else { return None }
  self.sources.search_by(s => s.source.id == t.source).map(i => self.sources[i])
}

///|
/// The terrain's height in meters at `m`, from the deepest loaded DEM tile
/// there, or None where none has loaded.
fn elevation_at(src : SourceTiles, m : @core.MercatorCoord) -> Double? {
  let mut z = src.source.max_zoom
  while z >= src.source.min_zoom {
    let n = (1 << z).to_double()
    if @core.tile_containing(m, z) is Some(id) &&
      src.ready(id).bind(dem_of) is Some((_, d)) {
      return Some(
        d.height_at(m.x * n - id.x.to_double(), m.y * n - id.y.to_double()),
      )
    }
    z -= 1
  }
  None
}

///|
/// Where `d`'s meshes go in the `size`-pixel texture of terrain tile `into`: its
/// tile units scaled into the texture's clip space, a texture pixel's worth of
/// tile units, clipped as on screen (`d.at.clip`).
fn texture_placement(
  d : Draw,
  into : @core.TileId,
  size : Int32,
) -> @render_webgl2.Placement {
  let s = d.id
  let k = @math.pow(2.0, (into.z - s.z).to_double())
  let unit = 2.0 * k / @core.TILE_EXTENT.to_double()
  let matrix = @core.Mat4::identity()
    .translate(
      (s.x.to_double() * k - into.x.to_double()) * 2.0 - 1.0,
      1.0 - (s.y.to_double() * k - into.y.to_double()) * 2.0,
      0.0,
    )
    .scale(unit, -unit, 1.0)
  {
    matrix,
    units_per_pixel: @core.TILE_EXTENT.to_double() / (size.to_double() * k),
    center_depth: 1.0,
    clip: d.at.clip,
    latitudes: d.at.latitudes,
  }
}

///|
/// The loaded DEM tile under terrain tile `id` (itself or its nearest loaded ancestor)
/// and `id`'s part of it: offset x, y and scale.
fn dem_under(
  src : SourceTiles,
  id : @core.TileId,
) -> (@render_webgl2.Mesh, FixedArray[Double])? {
  let mut at : @core.TileId? = Some(id)
  while at is Some(d) && d.z >= src.source.min_zoom {
    if src.ready(d).bind(dem_of) is Some((mesh, _)) {
      let k = @math.pow(2.0, (d.z - id.z).to_double())
      return Some(
        (
          mesh,
          [
            id.x.to_double() * k - d.x.to_double(),
            id.y.to_double() * k - d.y.to_double(),
            k,
          ],
        ),
      )
    }
    at = d.parent()
  }
  None
}

///|
/// Draws the map onto terrain. Terrain tiles follow the display zoom (or the DEM
/// tiles', if deeper): each gets a texture of the layers under it (all but
/// symbols), then its grid is drawn raised by the DEM, nearest surface wins.
fn Map::render_terrain(
  self : Map,
  src : SourceTiles,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
  dpr : Double,
) -> Unit {
  let t = self.transform
  let zoom = t.camera.zoom
  let scale = self.terrain_scale()
  let (r, g, b) = self.background()
  let size = TERRAIN_TEXTURE *
    @cmp.maximum(1, @cmp.minimum(2, dpr.round().to_int()))
  let dem_z = t.tile_zoom(
    src.source.min_zoom,
    src.source.max_zoom,
    tile_size=src.source.tile_size,
  )
  let z = @cmp.maximum(t.tile_zoom(0, 24), dem_z)
  let fog = self.fog()
  let skirt = SKIRT_METERS * t.pixels_per_meter()
  let drawn = []
  self.renderer.clear_depth()
  for id in t.covering_tiles(src.source.min_zoom, z) {
    guard dem_under(src, id) is Some((mesh, part)) else { continue }
    let target = self.target_for(id, size)
    self.renderer.begin_target(target, r, g, b)
    // Texture pixels per CSS pixel: the tile spans TILE_SIZE * 2^(zoom - z) on screen.
    let px = size.to_double() /
      (@core.TILE_SIZE * @math.pow(2.0, zoom - id.z.to_double()))
    for index, layer in self.style.layers {
      if layer.kind is (Background | Symbol | FillExtrusion) ||
        zoom < layer.min_zoom ||
        zoom >= layer.max_zoom {
        continue
      }
      let shared = paint_of(layer, zoom, JsProps::none())
      for s in draws_of.get(layer.source).unwrap_or([]) {
        if overlap(s.id, id) {
          self.draw_layer(
            index,
            layer,
            shared,
            texture_placement(s, id, size),
            s.meshes,
            px,
          )
        }
      }
    }
    self.renderer.end_target()
    let at = self.placement(id, None, dpr)
    self.renderer.draw_terrain(mesh, target, at, scale, skirt, part, fog)
    drawn.push((mesh, target, at, part))
  }
  // The same grids again into the depth target labels are hidden by.
  self.renderer.begin_depth()
  for d in drawn {
    let (mesh, target, at, part) = d
    self.renderer.draw_terrain(mesh, target, at, scale, skirt, part, fog)
  }
  self.renderer.end_depth()
  self.prune_targets()
}

///|
/// World pixels per meter of terrain height (exaggerated) at this camera.
fn Map::terrain_scale(self : Map) -> Double {
  let exaggeration = self.style.terrain.map(t => t.exaggeration).unwrap_or(1.0)
  self.transform.pixels_per_meter() * exaggeration
}

///|
/// The `size`-pixel offscreen target of terrain tile `id`, made on first use.
fn Map::target_for(
  self : Map,
  id : @core.TileId,
  size : Int32,
) -> @render_webgl2.Target {
  // Keyed by size too, so a new device pixel ratio gets new targets.
  let key = id.key() * 4L + (size / TERRAIN_TEXTURE).to_int64()
  match self.targets.get(key) {
    Some((target, _)) => {
      self.targets.set(key, (target, self.frame_count))
      target
    }
    None => {
      let target = self.renderer.target(size)
      self.targets.set(key, (target, self.frame_count))
      target
    }
  }
}

///|
/// Frees the offscreen targets least recently drawn beyond `MAX_SPARE_TARGETS`
/// unused ones.
fn Map::prune_targets(self : Map) -> Unit {
  let idle = []
  for key, v in self.targets {
    if v.1 != self.frame_count {
      idle.push((v.1, key))
    }
  }
  if idle.length() <= MAX_SPARE_TARGETS {
    return
  }
  idle.sort_by((a, b) => a.0.compare(b.0))
  for i in 0..<(idle.length() - MAX_SPARE_TARGETS) {
    if self.targets.get(idle[i].1) is Some((target, _)) {
      self.renderer.release_target(target)
    }
    self.targets.remove(idle[i].1)
  }
}

///|
/// Whether the request is for a tile of the style's terrain source.
fn Map::is_terrain_source(self : Map, request : Int32) -> Bool {
  guard self.requests.get(request) is Some((source, _)) &&
    self.source_tiles(source) is Some(src) &&
    self.style.terrain is Some(t) else {
    return false
  }
  src.source.id == t.source
}
