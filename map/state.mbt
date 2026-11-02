///|
/// A feature's state as given to `set_feature_state`: a JS object, or null.
#external
pub type FeatureState

///|
extern "js" fn state_value(s : FeatureState) -> JsValue =
  #|(s) => s

///|
/// A request for the ranges of stated features in one tile: its source, the
/// tile, the request its bytes came with, and the ids asked for.
priv struct RangePart {
  source : String
  key : Int64
  request : Int32
  ids : Array[String]
}

///|
extern "js" fn post_ranges(
  w : Worker,
  id : Int32,
  tile : Int32,
  ids : FixedArray[String],
) -> Unit =
  #|(w, id, tile, ids) => w.postMessage({ type: "ranges", id, tile, ids })

///|
extern "js" fn range_entries(msg : JsValue) -> Int32 =
  #|(m) => Array.isArray(m.entries) ? m.entries.length : 0

///|
extern "js" fn range_entry(msg : JsValue, i : Int32) -> Int32 =
  #|(m, i) => m.entries[i].entry | 0

///|
extern "js" fn range_values(msg : JsValue, i : Int32) -> FixedArray[Int32] =
  #|(m, i) => Array.from(m.entries[i].ranges ?? [], (v) => v | 0)

///|
fn state_key(source_layer : String, id : String) -> String {
  "\{source_layer}\u{0}\{id}"
}

///|
/// Sets the state of feature `id` (as `String(id)`) of `source_layer` (""
/// for a GeoJSON source) in `source` to the JS object `state`, or removes it
/// when `state` is null. Layers whose paint reads the feature state draw
/// that feature with it once the workers have said where it lies.
pub fn Map::set_feature_state(
  self : Map,
  source : String,
  source_layer : String,
  id : String,
  state : FeatureState,
) -> Unit {
  let state = state_value(state)
  let states = match self.feature_states.get(source) {
    Some(s) => s
    None => {
      let s = @hashmap.HashMap([])
      self.feature_states.set(source, s)
      s
    }
  }
  if is_null_value(state) {
    states.remove(state_key(source_layer, id))
  } else {
    states.set(state_key(source_layer, id), state)
  }
  guard self.sources.search_by(s => s.source.id == source) is Some(at) else {
    return
  }
  let src = self.sources[at]
  for _, e in src.tiles {
    self.ask_ranges(src, e)
  }
}

///|
/// Asks the worker keeping `e`'s bytes where its stated features lie, if
/// any layer of the tile draws by feature state; with no state left, clears
/// the tile's ranges at once.
fn Map::ask_ranges(self : Map, src : SourceTiles, e : TileEntry) -> Unit {
  guard e.state is (Ready(meshes) | Stale(meshes)) &&
    meshes.iter().any(m => m.layer >= 0 && self.state_layer(m.layer)) else {
    return
  }
  let ids = []
  if self.feature_states.get(src.source.id) is Some(states) {
    for k, _ in states {
      let id = k.split("\u{0}").last().map(v => v.to_owned()).unwrap_or("")
      if !ids.contains(id) {
        ids.push(id)
      }
    }
  }
  if ids.is_empty() {
    for m in meshes {
      m.states = []
    }
    self.content_version += 1
    self.idle_fired = false
    self.request_render()
    return
  }
  let (worker, request) = e.kept
  guard worker >= 0 else { return }
  let part = self.next_query
  self.next_query += 1
  self.range_parts.set(part, {
    source: src.source.id,
    key: e.id.key(),
    request,
    ids,
  })
  post_ranges(self.workers[worker], part, request, FixedArray::from_array(ids))
}

///|
fn Map::state_layer(self : Map, index : Int32) -> Bool {
  index < self.style.layers.length() && self.style.layers[index].reads_state()
}

///|
/// A worker's answer: each entry's ranges of the features asked for, as
/// (first index, count, index in the ids) triples.
fn Map::on_ranges(self : Map, msg : JsValue) -> Unit {
  let part = get_int(msg, "id")
  guard self.range_parts.get(part) is Some(p) else { return }
  self.range_parts.remove(part)
  guard self.sources.search_by(s => s.source.id == p.source) is Some(at) &&
    self.sources[at].tiles.get(p.key) is Some(e) &&
    e.kept.1 == p.request &&
    e.state is (Ready(meshes) | Stale(meshes)) else {
    // Settles the map if this was the last answer awaited.
    self.request_render()
    return
  }
  let states = self.feature_states.get(p.source).unwrap_or(@hashmap.HashMap([]))
  for m in meshes {
    m.states = []
  }
  for i in 0..<range_entries(msg) {
    let entry = range_entry(msg, i)
    let r = range_values(msg, i)
    for m in meshes {
      guard m.entry == entry && m.layer >= 0 && self.state_layer(m.layer) else {
        continue
      }
      let source_layer = self.style.layers[m.layer].source_layer
      for k = 0; k + 2 < r.length(); k = k + 3 {
        let id = p.ids.get(r[k + 2]).unwrap_or("")
        if states.get(state_key(source_layer, id)) is Some(state) {
          m.states.push((r[k], r[k + 1], state))
        }
      }
      m.states.sort_by((a, b) => a.0.compare(b.0))
    }
  }
  self.content_version += 1
  self.idle_fired = false
  self.request_render()
}

///|
/// Draws `m` with `draw`: whole with `p`, or, with stated features, in
/// index order, each stated feature with its own paint and the runs between
/// with `p`.
fn Map::draw_by_state(
  self : Map,
  m : LayerMesh,
  layer : @style.StyleLayer,
  p : Paint,
  zoom : Double,
  draw : (Paint) -> Unit,
) -> Unit {
  if m.states.is_empty() {
    draw(p)
    return
  }
  let obj = match m.props {
    Some(props) => props.obj
    None => js_null()
  }
  let total = self.renderer.index_count(m.mesh)
  let mut at = 0
  for s in m.states {
    let (first, count, state) = s
    if first > at {
      self.renderer.set_range(m.mesh, at, first - at)
      draw(p)
    }
    self.renderer.set_range(m.mesh, first, count)
    draw(paint_of(layer, zoom, { obj, state, }))
    at = first + count
  }
  if at < total {
    self.renderer.set_range(m.mesh, at, total - at)
    draw(p)
  }
  self.renderer.whole_mesh(m.mesh)
}
