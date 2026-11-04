///|
/// `@worker.KIND_FILL`, `KIND_LINE` and `KIND_CIRCLE`, mirrored so the main
/// bundle does not pull in the worker.
const KIND_FILL : Int32 = 1

///|
const KIND_LINE : Int32 = 2

///|
const KIND_CIRCLE : Int32 = 3

///|
/// `@worker.KIND_EXTRUSION`, mirrored like the other kinds.
const KIND_EXTRUSION : Int32 = 6

///|
/// A `raster-dem` tile's slopes for its source's hillshade layers (the worker's
/// entry has layer -1: it serves every hillshade layer of the source).
const KIND_HILLSHADE : Int32 = 5

///|
/// A raster tile's image: like a DEM tile's entry, layer -1 serves every
/// raster layer of the source.
const KIND_RASTER : Int32 = 7

///|
/// The tiles of one source the style's layers draw from: `index` is its
/// position in the style's sources (the worker knows sources by it).
priv struct SourceTiles {
  index : Int32
  source : @style.Source
  tiles : @hashmap.HashMap[Int64, TileEntry]
}

///|
/// Requests tile `id` of `src`: a vector tile is fetched by a worker, a
/// GeoJSON tile comes from the provider and is then handed to a worker.
fn Map::request_tile(
  self : Map,
  src : SourceTiles,
  id : @core.TileId,
  previous? : Array[LayerMesh],
) -> Unit {
  let request = self.next_request
  self.next_request += 1
  let worker = self.pick_worker()
  self.requests.set(request, (src.index, id.key()))
  src.tiles.set(id.key(), {
    id,
    state: Loading(request~, worker~, previous~),
    last_used: self.frame_count,
    kept: (-1, -1),
  })
  guard worker >= 0 else {
    self.finish(request, None)
    return
  }
  if src.source.kind is (Vector | RasterDem | Raster) {
    let tiles = src.source.tiles
    post_tile(
      self.workers[worker],
      request,
      tile_url(
        tiles[request % tiles.length()],
        id.z,
        id.x,
        if src.source.tms {
          (1 << id.z) - 1 - id.y
        } else {
          id.y
        },
      ),
      src.index,
      id.z,
      id.x,
      id.y,
      src.source.kind is RasterDem,
      src.source.kind is Raster,
      self.transform_request,
    )
    return
  }
  guard !is_null_provider(self.geojson) else {
    self.finish(request, None)
    return
  }
  call_provider(self.geojson, src.source.id, id.z, id.x, id.y, bytes => {
    // The tile may have been dropped while the provider worked.
    if self.destroyed || self.requests.get(request) is None {
      return
    }
    if is_null_value(bytes) {
      self.finish(request, Some([]))
    } else {
      post_tile_bytes(
        self.workers[worker],
        request,
        bytes,
        src.index,
        id.z,
        id.x,
        id.y,
      )
    }
  })
}

///|
/// The next worker in turn that has not failed; -1 if all have.
fn Map::pick_worker(self : Map) -> Int32 {
  let n = self.workers.length()
  for _ in 0..<n {
    let w = self.next_worker
    self.next_worker = (w + 1) % n
    if !self.failed_workers[w] {
      return w
    }
  }
  -1
}

///|
/// Worker `w` failed: it gets no more work, and what it was asked and has not
/// answered fails (tiles, queries, feature ranges), so the map can settle.
fn Map::worker_failed(self : Map, w : Int32, message : String) -> Unit {
  if self.destroyed || self.failed_workers[w] {
    return
  }
  self.failed_workers[w] = true
  terminate(self.workers[w])
  console_warn("mbmap worker: \{message}")
  let answers = []
  for request, at in self.requests {
    if self.source_tiles(at.0) is Some(src) &&
      src.tiles.get(at.1) is Some(e) &&
      e.state is Loading(worker~, ..) &&
      worker == w {
      answers.push(failed_answer("tile-error", request, message))
    }
  }
  for part, x in self.waiting {
    match x {
      Part(p) if p.worker == w =>
        answers.push(failed_answer("query", part, message))
      Ranges(p) if p.worker == w =>
        answers.push(failed_answer("ranges", part, message))
      _ => ()
    }
  }
  for a in answers {
    self.on_message(a)
  }
}

///|
/// An answer of `kind` to request `id` with nothing in it.
extern "js" fn failed_answer(
  kind : String,
  id : Int32,
  message : String,
) -> JsValue =
  #|(type, id, message) => ({ type, id, message, hits: [], entries: [] })

///|
fn Map::source_tiles(self : Map, index : Int32) -> SourceTiles? {
  self.sources.search_by(s => s.index == index).map(i => self.sources[i])
}

///|
/// Settles request `request`: with meshes, or failed (None).
fn Map::finish(self : Map, request : Int32, meshes : Array[LayerMesh]?) -> Unit {
  guard self.requests.get(request) is Some((source, key)) else { return }
  self.requests.remove(request)
  guard self.source_tiles(source) is Some(src) &&
    src.tiles.get(key) is Some(entry) else {
    return
  }
  self.content_version += 1
  if entry.state is Loading(previous~, worker~, ..) {
    if previous is Some(old) {
      self.release_meshes(old)
    }
    self.drop_kept(entry)
    if meshes is Some(_) && !(src.source.kind is (RasterDem | Raster)) {
      entry.kept = (worker, request)
    }
  }
  entry.state = match meshes {
    Some(m) => Ready(m)
    None => Failed
  }
  self.request_render()
}

///|
/// A gradient line's rows (start, end) and, last, how many tiles long its ramp
/// must be for a step: its longest line, times the zoom levels a tile at the
/// source's deepest zoom can be overzoomed (as MapLibre sizes it).
fn Map::ramp_clips(
  self : Map,
  request : Int32,
  clips : FixedArray[Double],
) -> FixedArray[Double] {
  let n = clips.length()
  if n > 0 &&
    self.requests.get(request) is Some((source, key)) &&
    self.source_tiles(source) is Some(src) &&
    src.tiles.get(key) is Some(entry) &&
    entry.id.z == src.source.max_zoom {
    let over = @math.pow(
      2.0,
      self.transform.limits.max_zoom - entry.id.z.to_double(),
    ).ceil()
    clips[n - 1] = clips[n - 1] * @cmp.maximum(1.0, over)
  }
  clips
}

///|
fn Map::on_message(self : Map, msg : JsValue) -> Unit {
  if self.destroyed {
    return
  }
  match get_string(msg, "type") {
    "tile-error" => {
      let request = get_int(msg, "id")
      if self.requests.get(request) is Some((source, key)) &&
        self.source_tiles(source) is Some(src) &&
        src.tiles.get(key) is Some(entry) {
        let id = entry.id
        console_warn(
          "tile \{src.source.id} \{id.z}/\{id.x}/\{id.y}: \{get_string(msg, "message")}",
        )
      }
      self.finish(request, None)
    }
    "tile" => {
      self.take_glyphs(msg)
      let request = get_int(msg, "id")
      guard self.requests.get(request) is Some(_) else { return }
      let meshes : Array[LayerMesh] = []
      for i in 0..<layers_of(msg) {
        let l = layer_at(msg, i)
        let shared = get_int(l, "shared")
        let kind = get_int(l, "kind")
        let (mesh, labels) = if kind == KIND_RASTER {
          (self.renderer.upload_raster(buffer_of(l, "image")), None)
        } else if kind == KIND_HILLSHADE {
          let mesh = self.renderer.upload_slopes(
            buffer_of(l, "image"),
            get_int(l, "size"),
          )
          if self.is_terrain_source(request) {
            self.renderer.add_elevations(
              mesh,
              buffer_of(l, "elevations"),
              get_int(l, "size"),
            )
            // Labels stand on terrain: look their heights up again.
            self.dem_version += 1
            self.labels_dirty = true
          }
          (mesh, None)
        } else if kind == KIND_SYMBOL {
          let (mesh, labels) = self.symbol_mesh(l)
          (mesh, Some(labels))
        } else if shared >= 0 && shared < meshes.length() {
          (meshes[shared].mesh, None)
        } else if kind == KIND_EXTRUSION {
          (
            self.renderer.upload_extrusion(
              buffer_of(l, "vertices"),
              buffer_of(l, "indices"),
              get_int(l, "count"),
              get_int(l, "indexBytes"),
            ),
            None,
          )
        } else {
          let mesh = self.renderer.upload(
            kind != KIND_FILL,
            buffer_of(l, "vertices"),
            buffer_of(l, "indices"),
            get_int(l, "count"),
            get_int(l, "indexBytes"),
          )
          if kind == KIND_LINE && !is_null_value(distances_of_layer(l)) {
            self.renderer.upload_distances(mesh, buffer_of(l, "distances"))
          }
          if kind == KIND_LINE && !is_null_value(offsets_of_layer(l)) {
            self.renderer.upload_offsets(mesh, buffer_of(l, "offsets"))
          }
          if kind == KIND_LINE && !is_null_value(progress_of_layer(l)) {
            self.renderer.upload_progress(mesh, buffer_of(l, "progress"))
          }
          if kind == KIND_FILL && get_int(l, "outlineCount") > 0 {
            self.renderer.upload_outline(
              mesh,
              buffer_of(l, "outline"),
              get_int(l, "outlineCount"),
            )
          }
          (mesh, None)
        }
        let props = props_or_null(l)
        meshes.push({
          entry: get_int(l, "entry"),
          states: [],
          layer: get_int(l, "layer"),
          kind,
          mesh,
          owned: shared < 0,
          props: if is_null_value(props) {
            None
          } else {
            Some({
              obj: props,
              state: js_null(),
              progress: @double.not_a_number,
              density: @double.not_a_number,
              elevation: @double.not_a_number,
            })
          },
          paint: None,
          vertex_paint: if is_null_value(paint_of_layer(l)) {
            None
          } else {
            Some(self.renderer.upload_paint(buffer_of(l, "paint")))
          },
          labels,
          ground: if kind == KIND_EXTRUSION {
            Some({
              runs: @render_webgl2.extrusion_runs(buffer_of(l, "vertices")),
              at: 0,
            })
          } else {
            None
          },
          clips: if kind == KIND_LINE && !is_null_value(progress_of_layer(l)) {
            Some(self.ramp_clips(request, f64_array(buffer_of(l, "clips"))))
          } else {
            None
          },
          key_runs: if is_null_value(key_runs_of_layer(l)) {
            None
          } else {
            Some(f64_array(buffer_of(l, "keyRuns")))
          },
          gradient: None,
          dem: if kind == KIND_HILLSHADE {
            let heights = buffer_of(l, "elevations")
            let range = height_range(heights)
            Some({
              edges: f64_array(buffer_of(l, "edges")),
              heights,
              size: get_int(l, "size"),
              lowest: range[0],
              highest: range[1],
            })
          } else {
            None
          },
        })
      }
      let at = self.requests.get(request)
      self.finish(request, Some(meshes))
      // Stated features of the new tile, drawn by state once the worker says where.
      if at is Some((source, key)) &&
        self.source_tiles(source) is Some(src) &&
        src.tiles.get(key) is Some(entry) &&
        self.feature_states.get(src.source.id) is Some(states) &&
        states.length() > 0 {
        self.ask_ranges(src, entry)
      }
      if at is Some((source, key)) &&
        self.source_tiles(source) is Some(src) &&
        src.tiles.get(key) is Some(entry) &&
        dem_of(meshes) is Some(_) {
        self.stitch_dem(src, entry.id)
        self.border_relief(src, entry.id)
      }
    }
    "query" => self.on_query(msg)
    "ranges" => self.on_ranges(msg)
    "error" => console_warn("worker: \{get_string(msg, "message")}")
    _ => ()
  }
}

///|
/// Requests the covering tiles of `src` that are missing and cancels its
/// loads that are no longer needed.
fn Map::update_tiles(
  self : Map,
  src : SourceTiles,
  cover : Array[@core.TileId],
) -> Unit {
  let wanted = @hashset.HashSet([])
  for id in cover {
    wanted.add(id.key())
    match src.tiles.get(id.key()) {
      Some({ state: Stale(meshes), .. }) =>
        self.request_tile(src, id, previous=meshes)
      Some(e) => e.last_used = self.frame_count
      None => self.request_tile(src, id)
    }
  }
  let stale = []
  for key, e in src.tiles {
    if e.state is Loading(_) && !wanted.contains(key) {
      stale.push(key)
    }
  }
  for key in stale {
    if src.tiles.get(key) is Some(e) {
      self.release(e)
    }
    src.tiles.remove(key)
  }
  self.evict(src, wanted)
}

///|
/// Drops the least recently used loaded tiles of `src` beyond
/// `MAX_CACHED_TILES`.
fn Map::evict(
  self : Map,
  src : SourceTiles,
  wanted : @hashset.HashSet[Int64],
) -> Unit {
  let extra = src.tiles.length() - wanted.length() - MAX_CACHED_TILES
  if extra <= 0 {
    return
  }
  let candidates = []
  for key, e in src.tiles {
    if !wanted.contains(key) {
      candidates.push((e.last_used, key))
    }
  }
  candidates.sort_by((a, b) => a.0.compare(b.0))
  for i in 0..<@cmp.minimum(extra, candidates.length()) {
    let key = candidates[i].1
    if src.tiles.get(key) is Some(e) {
      self.release(e)
    }
    src.tiles.remove(key)
  }
}

///|
fn SourceTiles::ready(
  self : SourceTiles,
  id : @core.TileId,
) -> Array[LayerMesh]? {
  match self.tiles.get(id.key()) {
    Some({ state: Ready(meshes) | Stale(meshes), .. }) => Some(meshes)
    Some({ state: Loading(previous=Some(meshes), ..), .. }) => Some(meshes)
    _ => None
  }
}

///|
/// What to draw for one covering tile: itself, or a loaded ancestor clipped
/// to its area, or its loaded children.
priv enum Fallback {
  Own(@core.TileId, Array[LayerMesh])
  Ancestor(@core.TileId, Array[LayerMesh], clip~ : @core.TileId)
  Children(Array[(@core.TileId, Array[LayerMesh])])
  Nothing
}

///|
fn SourceTiles::fallback(self : SourceTiles, id : @core.TileId) -> Fallback {
  if self.ready(id) is Some(m) {
    return Own(id, m)
  }
  let mut p = id.parent()
  for _ in 0..<MAX_FALLBACK_LEVELS {
    guard p is Some(parent) else { break }
    if self.ready(parent) is Some(m) {
      return Ancestor(parent, m, clip=id)
    }
    p = parent.parent()
  }
  let kids = []
  if id.children() is Some(children) {
    for c in children {
      if self.ready(c) is Some(m) {
        kids.push((c, m))
      }
    }
  }
  if kids.is_empty() {
    Nothing
  } else {
    Children(kids)
  }
}

///|
fn SourceTiles::settled(self : SourceTiles, id : @core.TileId) -> Bool {
  match self.tiles.get(id.key()) {
    Some({ state: Ready(_) | Failed, .. }) => true
    _ => false
  }
}
