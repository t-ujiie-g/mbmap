///|
/// Query results as JS: per tile asked, `{z, x, y, hits}`, each hit
/// `{layer, index, distance, feature}` (docs/FORMATS.md, "Query result"; the
/// layer as its id, or -1 for a source query, `feature` a GeoJSON feature).
#external
pub type TileResults

///|
/// A query sent to the workers one tile at a time: tiles still to answer, the
/// answers so far and who gets them.
priv struct PendingQuery {
  mut left : Int32
  results : TileResults
  done : (TileResults) -> Unit
}

///|
/// What a worker's answer is awaited for, by id (one map, so the bundle holds
/// one map type for them): a query, one tile's part of it, or a tile's
/// feature ranges.
priv enum Waiting {
  Query(PendingQuery)
  Part(QueryPart)
  Ranges(RangePart)
}

///|
/// One tile's part of a query: the query, the worker asked, the tile, and the
/// style its layer indices refer to (None for a source query, whose hits name no layer).
priv struct QueryPart {
  query : Int32
  worker : Int32
  tile : @core.TileId
  style : @style.Style?
}

///|
extern "js" fn new_results() -> TileResults =
  #|() => []

///|
extern "js" fn add_result(
  results : TileResults,
  z : Int32,
  x : Int32,
  y : Int32,
  hits : JsValue,
) -> Unit =
  #|(r, z, x, y, hits) => { r.push({ z, x, y, hits: Array.isArray(hits) ? hits : [] }) }

///|
extern "js" fn hits_of(msg : JsValue) -> JsValue =
  #|(m) => Array.isArray(m.hits) ? m.hits : []

///|
extern "js" fn hit_count(hits : JsValue) -> Int32 =
  #|(h) => h.length

///|
extern "js" fn hit_layer(hits : JsValue, i : Int32) -> Int32 =
  #|(h, i) => h[i].layer | 0

///|
extern "js" fn set_hit_layer(hits : JsValue, i : Int32, id : String) -> Unit =
  #|(h, i, id) => { h[i].layer = id }

///|
extern "js" fn drop_hits(hits : JsValue, keep : (Int32) -> Bool) -> JsValue =
  #|(h, keep) => h.filter((_, i) => keep(i))

///|
extern "js" fn post_query(
  w : Worker,
  id : Int32,
  kind : String,
  tile : Int32,
  source : Int32,
  z : Int32,
  x : Int32,
  y : Int32,
  request : Bytes,
) -> Unit =
  #|(w, id, kind, tile, source, z, x, y, request) => w.postMessage({ type: "query", id, kind, tile, source, z, x, y, request })

///|
extern "js" fn later(f : () -> Unit) -> Unit =
  #|(f) => queueMicrotask(f)

///|
/// Starts a query of `parts` tiles; `done` gets the answers once all are in
/// (at once, later, when there are none).
fn Map::start_query(
  self : Map,
  done : (TileResults) -> Unit,
) -> (Int32, PendingQuery) {
  let id = self.next_query
  self.next_query += 1
  let q = { left: 0, results: new_results(), done, }
  self.waiting.set(id, Query(q))
  (id, q)
}

///|
fn Map::finish_query(self : Map, id : Int32) -> Unit {
  guard self.waiting.get(id) is Some(Query(q)) && q.left == 0 else { return }
  self.waiting.remove(id)
  (q.done)(q.results)
}

///|
/// Asks the worker keeping `entry`'s bytes; false if none does.
fn Map::send_part(
  self : Map,
  query : Int32,
  q : PendingQuery,
  kind : String,
  src : SourceTiles,
  entry : TileEntry,
  request : Bytes,
  style : @style.Style?,
) -> Bool {
  let (worker, tile) = entry.kept
  guard worker >= 0 && !self.failed_workers[worker] else { return false }
  let part = self.next_query
  self.next_query += 1
  self.waiting.set(part, Part({ query, worker, tile: entry.id, style, }))
  q.left += 1
  let id = entry.id
  post_query(
    self.workers[worker],
    part,
    kind,
    tile,
    src.index,
    id.z,
    id.x,
    id.y,
    request,
  )
  true
}

///|
/// A worker's answer for one tile: its hits' layers become ids, unless the
/// style changed since (then the tile has none).
fn Map::on_query(self : Map, msg : JsValue) -> Unit {
  let part = get_int(msg, "id")
  guard self.waiting.get(part) is Some(Part(p)) else { return }
  self.waiting.remove(part)
  guard self.waiting.get(p.query) is Some(Query(q)) else { return }
  let mut hits = hits_of(msg)
  if p.style is Some(s) {
    if physical_equal(s, self.style) {
      for i in 0..<hit_count(hits) {
        let layer = hit_layer(hits, i)
        if layer >= 0 && layer < s.layers.length() {
          set_hit_layer(hits, i, s.layers[layer].id)
        }
      }
    } else {
      hits = drop_hits(hits, _ => false)
    }
  }
  add_result(q.results, p.tile.z, p.tile.x, p.tile.y, hits)
  q.left -= 1
  self.finish_query(p.query)
}

///|
/// Ends every query in flight with what it has (the map is going away).
fn Map::end_queries(self : Map) -> Unit {
  let pending = []
  for _, w in self.waiting {
    if w is Query(q) {
      pending.push(q)
    }
  }
  self.waiting.clear()
  self.ranges_waiting = 0
  for q in pending {
    (q.done)(q.results)
  }
}

///|
/// The tiles of `src` drawn in the last frame, each once.
fn Map::drawn_tiles(self : Map, src : SourceTiles) -> Array[TileEntry] {
  let seen : @hashmap.HashMap[Int64, Unit] = @hashmap.HashMap([])
  let out = []
  for d in self.drawn.get(src.source.id).unwrap_or([]) {
    let key = d.id.key()
    if seen.contains(key) {
      continue
    }
    seen.set(key, ())
    if src.tiles.get(key) is Some(e) {
      out.push(e)
    }
  }
  out
}

///|
/// Compiles a query's `filter` (JSON text from `JSON.stringify`, or "" for
/// none); the error if it is not one mbmap evaluates.
fn compile_filter(filter : String) -> Result[@style.Expr?, String] {
  if filter == "" {
    return Ok(None)
  }
  try
    @style.compile(parse_json(filter), expected=BoolType, path="filter")
  catch {
    e => Err("mbmap: \{e.message()}")
  } noraise {
    e => Ok(Some(e))
  }
}

///|
/// The features under `points` (one point or a closed ring, CSS pixels) of the
/// layers named (all if None) passing `filter` (JSON or ""), as MapLibre finds
/// them; `done` gets each tile's hits. Returns why it cannot run, or "".
pub fn Map::query_rendered(
  self : Map,
  points : Array[(Double, Double)],
  layers : Array[String]?,
  filter : String,
  done : (TileResults) -> Unit,
) -> String {
  let filter = match compile_filter(filter) {
    Ok(f) => f
    Err(why) => return why
  }
  if points.is_empty() {
    return "mbmap: a query needs a point"
  }
  let style = self.style
  let wanted = style.layers.map(l => {
    match layers {
      Some(ids) => ids.contains(l.id)
      None => true
    }
  })
  let t = self.transform
  let extent = @core.TILE_EXTENT.to_double()
  let mercator = points.map(p => t.screen_to_mercator(p.0, p.1))
  // MapLibre's camera query geometry: the query's box grown to the point
  // under the camera, so that buildings standing between are found.
  let camera_point = (
    t.width / 2.0,
    t.height / 2.0 +
    @math.tan(t.camera.pitch * @math.PI / 180.0) * t.center_depth(),
  )
  let camera_screen = if points.length() == 1 {
    [points[0], camera_point]
  } else {
    let xs = points.map(p => p.0)
    let ys = points.map(p => p.1)
    let x0 = @cmp.minimum(
      xs.fold(init=camera_point.0, @cmp.minimum),
      camera_point.0,
    )
    let x1 = xs.fold(init=camera_point.0, @cmp.maximum)
    let y0 = ys.fold(init=camera_point.1, @cmp.minimum)
    let y1 = ys.fold(init=camera_point.1, @cmp.maximum)
    [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
  }
  let pitch_factor = t.max_pitch_scale_factor()
  let (query, q) = self.start_query(done)
  for src in self.sources {
    if src.source.kind is (RasterDem | Raster | Image) {
      continue
    }
    let indices = []
    let mut extruded = false
    for i, l in style.layers {
      if wanted[i] &&
        l.source == src.source.id &&
        !(l.kind is (Symbol | Background | Hillshade | ColorRelief | Raster)) {
        indices.push(i)
        extruded = extruded || l.kind is FillExtrusion
      }
    }
    let camera = if extruded { camera_screen } else { points }
    let camera_mercator = camera.map(p => t.screen_to_mercator(p.0, p.1))
    let symbols = self.symbols_under(src, points, wanted)
    for e in self.drawn_tiles(src) {
      let labels = symbols.get(e.id.key()).unwrap_or([])
      if indices.is_empty() && labels.is_empty() {
        continue
      }
      let id = e.id
      let n = (1 << id.z).to_double()
      let tile_point = (m : @core.MercatorCoord) => {
        (
          (m.x * n - id.x.to_double()) * extent,
          (m.y * n - id.y.to_double()) * extent,
        )
      }
      let w = @core.ByteWriter::new()
      w.f64(t.camera.zoom)
      w.f64(1.0 / t.tile_scale(id, @core.TILE_EXTENT))
      w.f64(pitch_factor)
      w.f64(t.width)
      w.f64(t.height)
      w.f64(t.center_depth())
      w.f64(t.pixels_per_meter())
      w.f64(t.camera.bearing * @math.PI / 180.0)
      for v in t.tile_matrix(id, @core.TILE_EXTENT).m {
        w.f64(v)
      }
      w.u32(mercator.length())
      for m in mercator {
        let (x, y) = tile_point(m)
        w.f64(x)
        w.f64(y)
      }
      w.u32(camera_mercator.length())
      for m in camera_mercator {
        let (x, y) = tile_point(m)
        w.f64(x)
        w.f64(y)
      }
      w.u8(if layers is None { 1 } else { 0 })
      w.u32(indices.length())
      for i in indices {
        w.u32(i)
      }
      w.u32(labels.length())
      for l in labels {
        w.u32(l.0)
        w.u32(l.1)
      }
      @style.write_expr(w, filter)
      self.send_part(query, q, "rendered", src, e, w.to_bytes(), Some(style))
      |> ignore
    }
  }
  later(() => self.finish_query(query))
  ""
}

///|
/// The labels of `src` shown under `points` (screen pixels) at the last
/// placement, of the style layers `wanted` marks, by tile: (layer, feature)
/// pairs, each once (MapLibre's `queryRenderedSymbols`).
fn Map::symbols_under(
  self : Map,
  src : SourceTiles,
  points : Array[(Double, Double)],
  wanted : Array[Bool],
) -> @hashmap.HashMap[Int64, Array[(Int32, Int32)]] {
  let out : @hashmap.HashMap[Int64, Array[(Int32, Int32)]] = @hashmap.HashMap([])
  for d in self.drawn.get(src.source.id).unwrap_or([]) {
    for m in d.meshes {
      guard m.labels is Some(s) &&
        m.layer >= 0 &&
        m.layer < wanted.length() &&
        wanted[m.layer] &&
        s.round == self.placement_round else {
        continue
      }
      let list = match out.get(d.id.key()) {
        Some(l) => l
        None => {
          let l = []
          out.set(d.id.key(), l)
          l
        }
      }
      for i in 0..<s.count {
        // Its text's box and its icon's, each if shown.
        let hits = (shown : Bool, k : Int32) => {
          let b = i * BOX_FLOATS + k
          shown &&
          @core.polygon_hits_box(
            points,
            s.boxes[b],
            s.boxes[b + 1],
            s.boxes[b + 2],
            s.boxes[b + 3],
          )
        }
        let icon = match s.icon {
          Some(ic) => ic.shown[i]
          None => false
        }
        if hits(s.shown[i], 0) || hits(icon, 4) {
          let hit = (
            m.layer,
            f32_at(s.labels, i * LABEL_FLOATS + LABEL_FEATURE).to_int(),
          )
          if !list.contains(hit) {
            list.push(hit)
          }
        }
      }
    }
  }
  out
}

///|
/// Every feature of `source_layer` (any, for GeoJSON) in the drawn tiles of
/// `source` passing `filter` (JSON or ""), as MapLibre's `querySourceFeatures`;
/// `done` gets each tile's. Returns why it cannot run, or "".
pub fn Map::query_source(
  self : Map,
  source : String,
  source_layer : String,
  filter : String,
  done : (TileResults) -> Unit,
) -> String {
  let filter = match compile_filter(filter) {
    Ok(f) => f
    Err(why) => return why
  }
  let (query, q) = self.start_query(done)
  if self.sources.search_by(s => s.source.id == source) is Some(at) &&
    !(self.sources[at].source.kind is (RasterDem | Raster | Image)) {
    let src = self.sources[at]
    let w = @core.ByteWriter::new()
    w.utf8(source_layer)
    @style.write_expr(w, filter)
    let request = w.to_bytes()
    for e in self.drawn_tiles(src) {
      self.send_part(query, q, "features", src, e, request, None) |> ignore
    }
  }
  later(() => self.finish_query(query))
  ""
}
