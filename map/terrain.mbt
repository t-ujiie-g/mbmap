///|
/// CSS pixels per side of the texture a terrain tile's map is drawn into
/// (times the device pixel ratio, up to 2, for tiles at the full zoom).
const TERRAIN_TEXTURE : Int32 = 512

///|
/// How far terrain skirts hang below tile edges, in meters.
const SKIRT_METERS : Double = 300.0

///|
/// Offscreen targets kept beyond those drawn this frame.
const MAX_SPARE_TARGETS : Int32 = 8

///|
/// A terrain tile's offscreen target, the frame it was last used in, and the
/// signature of what was drawn into it (`Map::texture_signature`).
priv struct TerrainTarget {
  target : @render_webgl2.Target
  mut used : Int32
  mut signature : Int64
}

///|
/// One tile's meshes and where they go this frame; a picture reaching past its
/// tile has its Mercator `bounds` (min x, min y, max x, max y).
priv struct Draw {
  id : @core.TileId
  at : @render_webgl2.Placement
  meshes : Array[LayerMesh]
  bounds : (Double, Double, Double, Double)?
}

///|
/// Whether one tile lies inside the other (quadtree tiles overlap no other way).
fn overlap(a : @core.TileId, b : @core.TileId) -> Bool {
  let z = @cmp.minimum(a.z, b.z)
  a.x >> (a.z - z) == b.x >> (b.z - z) && a.y >> (a.z - z) == b.y >> (b.z - z)
}

///|
/// Whether `d` draws over terrain tile `id`.
fn Draw::reaches(d : Draw, id : @core.TileId) -> Bool {
  match d.bounds {
    None => overlap(d.id, id)
    Some((x0, y0, x1, y1)) => {
      let n = (1 << id.z).to_double()
      x1 * n > id.x.to_double() &&
      x0 * n < (id.x + 1).to_double() &&
      y1 * n > id.y.to_double() &&
      y0 * n < (id.y + 1).to_double()
    }
  }
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
      let neighbor = (dx : Int32, dy : Int32) => {
        let k = 1 << z
        guard @core.TileId::new(z, (id.x + dx + k) % k, id.y + dy) is Some(nid) else {
          return None
        }
        src.ready(nid).bind(dem_of).map(t => t.1)
      }
      return Some(
        d.height_at(
          m.x * n - id.x.to_double(),
          m.y * n - id.y.to_double(),
          neighbor~,
        ),
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
    raster_matrix: matrix,
    units_per_pixel: @core.TILE_EXTENT.to_double() / (size.to_double() * k),
    center_depth: 1.0,
    clip: d.at.clip,
    latitudes: d.at.latitudes,
    pattern: d.at.pattern,
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
/// Gives the terrain source's loaded DEM tiles their elevations: tiles made for
/// hillshade or color relief alone have none, and terrain does not draw those.
fn Map::raise_dem_tiles(self : Map) -> Unit {
  guard self.terrain_source() is Some(src) else { return }
  for _, e in src.tiles {
    if e.state is (Ready(meshes) | Stale(meshes)) &&
      dem_of(meshes) is Some((mesh, d)) {
      self.renderer.add_elevations(mesh, d.heights, d.size)
    }
  }
}

///|
/// Draws the map onto terrain: each terrain tile (the display zoom, or the DEM's
/// if deeper) gets a texture of the layers under it, redrawn when they change,
/// on its grid raised by the DEM.
fn Map::render_terrain(
  self : Map,
  src : SourceTiles,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
  dpr : Double,
) -> Unit {
  let t = self.transform
  let scale = self.terrain_scale()
  // Tiles at the full zoom get the device's resolution, distant ones not.
  let full = TERRAIN_TEXTURE *
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
    let size = if id.z >= z { full } else { TERRAIN_TEXTURE }
    let (target, current) = self.target_for(
      id,
      size,
      self.texture_signature(id, draws_of),
    )
    if !current {
      self.draw_texture(id, target, size, draws_of)
    }
    let at = self.placement(id, None, dpr)
    self.renderer.draw_terrain(mesh, target, at, scale, skirt, part, fog)
    drawn.push((mesh, target, at, part))
  }
  // The same grids again into the depth target labels are hidden by.
  if self.has_labels {
    self.renderer.begin_depth()
    for d in drawn {
      let (mesh, target, at, part) = d
      self.renderer.draw_terrain(mesh, target, at, scale, skirt, part, fog)
    }
    self.renderer.end_depth()
  } else {
    self.renderer.reset_depth()
  }
  self.prune_targets()
}

///|
/// How much the style's terrain exaggerates heights (1 without terrain).
fn Map::exaggeration(self : Map) -> Double {
  self.style.terrain.map(t => t.exaggeration).unwrap_or(1.0)
}

///|
/// World pixels per meter of terrain height (exaggerated) at this camera.
fn Map::terrain_scale(self : Map) -> Double {
  self.transform.pixels_per_meter() * self.exaggeration()
}

///|
/// The `size`-pixel offscreen target of terrain tile `id`, made on first use,
/// and whether it already holds what `signature` describes (it is marked so).
fn Map::target_for(
  self : Map,
  id : @core.TileId,
  size : Int32,
  signature : Int64,
) -> (@render_webgl2.Target, Bool) {
  // Keyed by size too, so a new device pixel ratio gets new targets.
  let key = id.key() * 4L + (size / TERRAIN_TEXTURE).to_int64()
  match self.targets.get(key) {
    Some(t) => {
      t.used = self.frame_count
      let current = t.signature == signature
      t.signature = signature
      (t.target, current)
    }
    None => {
      let target = self.renderer.target(size)
      self.targets.set(key, { target, used: self.frame_count, signature, })
      (target, false)
    }
  }
}

///|
/// What terrain tile `id`'s texture shows: the zoom and bearing it is drawn at,
/// the tiles' contents (`content_version`) and which tiles of each source
/// overlap it, where. Its texture is drawn again only when this changes.
fn Map::texture_signature(
  self : Map,
  id : @core.TileId,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Int64 {
  let mix = (h : Int64, v : Int64) => (h ^ v) * 1099511628211L
  let camera = self.transform.camera
  let mut h = mix(-3750763034362895579L, camera.zoom.reinterpret_as_int64())
  h = mix(h, camera.bearing.reinterpret_as_int64())
  h = mix(h, self.content_version.to_int64())
  for _, draws in draws_of {
    for d in draws {
      if d.reaches(id) {
        h = mix(h, d.id.key())
        for c in d.at.clip {
          h = mix(h, c.reinterpret_as_int64())
        }
      }
    }
  }
  h
}

///|
/// Draws the layers under terrain tile `id` (all but symbols and extrusions)
/// into its `size`-pixel `target`.
fn Map::draw_texture(
  self : Map,
  id : @core.TileId,
  target : @render_webgl2.Target,
  size : Int32,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  let zoom = self.transform.camera.zoom
  let (r, g, b) = self.background()
  self.renderer.begin_target(target, r, g, b)
  // Texture pixels per CSS pixel: the tile spans TILE_SIZE * 2^(zoom - z) on screen.
  let px = size.to_double() /
    (@core.TILE_SIZE * @math.pow(2.0, zoom - id.z.to_double()))
  for index, layer in self.style.layers {
    if layer.kind is (Background | Symbol | FillExtrusion | Custom) ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    let shared = paint_of(layer, zoom, JsProps::none())
    if layer.heatmap is Some(h) {
      // As MapLibre: each tile's own kernels, at 512 px.
      let draws = draws_of
        .get(layer.source)
        .unwrap_or([])
        .filter(s => overlap(s.id, id))
        .map(s => { ..s, at: texture_placement(s, id, size), })
      let scale = HEATMAP_TILE_SIZE / size.to_double()
      self.draw_heatmap(index, h, shared, draws, px, scale)
      continue
    }
    for s in draws_of.get(layer.source).unwrap_or([]) {
      if s.reaches(id) {
        self.draw_layer(
          index,
          layer,
          shared,
          s.id,
          texture_placement(s, id, size),
          s.meshes,
          px,
        )
      }
    }
  }
  self.renderer.end_target()
}

///|
/// Frees the offscreen targets least recently drawn beyond `MAX_SPARE_TARGETS`
/// unused ones.
fn Map::prune_targets(self : Map) -> Unit {
  let idle = []
  for key, t in self.targets {
    if t.used != self.frame_count {
      idle.push((t.used, key))
    }
  }
  if idle.length() <= MAX_SPARE_TARGETS {
    return
  }
  idle.sort_by((a, b) => a.0.compare(b.0))
  for i in 0..<(idle.length() - MAX_SPARE_TARGETS) {
    if self.targets.get(idle[i].1) is Some(t) {
      self.renderer.release_target(t.target)
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

///|
/// The loaded terrain as camera picks see it (heights exaggerated), or None
/// without terrain or before any of its DEM tiles has loaded.
fn Map::terrain_pick(self : Map) -> @core.Terrain? {
  guard self.terrain_source() is Some(src) else { return None }
  let k = self.exaggeration()
  let mut lowest = 0.0
  let mut highest = 0.0
  let mut any = false
  for _, e in src.tiles {
    if e.state is (Ready(meshes) | Stale(meshes)) &&
      dem_of(meshes) is Some((_, d)) {
      any = true
      lowest = @cmp.minimum(lowest, d.lowest * k)
      highest = @cmp.maximum(highest, d.highest * k)
    }
  }
  guard any else { return None }
  Some({
    // Ground without DEM data is flat at 0 m, as MapLibre draws and picks it.
    height: (x, y) => Some(elevation_at(src, { x, y, }).unwrap_or(0.0) * k),
    lowest,
    highest,
  })
}

///|
/// Screen point (CSS pixels) of `p` on the terrain if any, and whether the
/// terrain hides it from the camera (MapLibre's `project` and
/// `isLocationOccluded`).
pub fn Map::locate(self : Map, p : @core.LngLat) -> (Double, Double, Bool) {
  let t = self.transform
  match self.terrain_pick() {
    None => {
      let (x, y) = t.project(p)
      (x, y, false)
    }
    Some(terrain) => {
      let m = p.to_mercator()
      let elevation = (terrain.height)(m.x - m.x.floor(), m.y).unwrap_or(0.0)
      let (x, y) = t.project(p, elevation~)
      (x, y, t.occluded(p, elevation, terrain))
    }
  }
}

///|
/// The point under screen point (x, y), on the terrain if any (MapLibre's
/// `unproject`).
pub fn Map::point_location(self : Map, x : Double, y : Double) -> @core.LngLat {
  match self.terrain_pick() {
    None => self.transform.unproject(x, y)
    Some(terrain) => self.transform.unproject_on(x, y, terrain)
  }
}
