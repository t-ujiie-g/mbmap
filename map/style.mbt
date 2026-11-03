///|
extern "js" fn post_style(w : Worker, style : String) -> Unit =
  #|(w, style) => w.postMessage({ type: "style", style })

///|
/// Whether a style draws from source `id`: a layer other than the background
/// uses it, or the terrain does.
fn draws_from(style : @style.Style, id : String) -> Bool {
  style.layers.iter().any(l => !(l.kind is Background) && l.source == id) ||
  style.terrain.map(t => t.source) == Some(id)
}

///|
/// Whether `src`'s tiles made under `a` serve `b`: each of its layers in `b` has a
/// `same_tiles` twin in `a` (order is applied when drawing). DEM and raster
/// tiles serve any layers.
fn same_layers(src : @style.Source, a : @style.Style, b : @style.Style) -> Bool {
  src.kind is (RasterDem | Raster) ||
  b.layers
  .iter()
  .filter(l => l.source == src.id)
  .all(l => a.layers.iter().any(o => o.id == l.id && o.same_tiles(l)))
}

///|
/// `meshes` made under `old` with their layers renumbered for `next`, by
/// layer id: those of layers `next` lacks (or moved to another source) are
/// freed, their buffers kept when a remaining layer shares them.
fn Map::remap(
  self : Map,
  meshes : Array[LayerMesh],
  old : @style.Style,
  next : @style.Style,
  index_of : @hashmap.HashMap[String, Int32],
) -> Array[LayerMesh] {
  let kept = []
  let dropped = []
  for m in meshes {
    if m.layer < 0 {
      kept.push(m)
      continue
    }
    let before = old.layers[m.layer]
    match index_of.get(before.id) {
      Some(i) if next.layers[i].source == before.source =>
        kept.push({ ..m, layer: i, paint: None, })
      _ => dropped.push(m)
    }
  }
  for m in dropped {
    guard m.owned else { continue }
    match kept.search_by(k => physical_equal(k.mesh, m.mesh)) {
      Some(i) => kept[i].owned = true
      None => self.renderer.release(m.mesh)
    }
  }
  kept
}

///|
/// Draws `style_json` from now on: sources whose tiles would come out alike keep
/// them, the others are reloaded while the old ones are drawn. Raises, keeping
/// the current style, if it cannot be drawn.
pub fn Map::set_style(self : Map, style_json : String) -> Unit raise MapError {
  let next = @style.Style::from_json(parse_json(style_json)) catch {
    e => raise BadStyle(e)
  }
  let old = self.style
  let index_of : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
  for i, l in next.layers {
    index_of[l.id] = i
  }
  // Every tile in flight was asked for under the old style: ask again.
  self.requests.clear()
  let sources = []
  for i, s in next.sources {
    if !draws_from(next, s.id) {
      continue
    }
    let tiles : @hashmap.HashMap[Int64, TileEntry] = @hashmap.HashMap([])
    if self.sources.search_by(o => o.source.id == s.id) is Some(at) {
      let before = self.sources[at]
      let reload = !before.source.same(s) || !same_layers(s, old, next)
      for key, e in before.tiles {
        let meshes = match e.state {
          Ready(m) | Stale(m) => Some(m)
          Loading(request~, worker~, previous~) => {
            post_cancel(self.workers[worker], request)
            previous
          }
          Failed => None
        }
        guard meshes is Some(m) else { continue }
        let m = self.remap(m, old, next, index_of)
        e.state = if reload || !(e.state is Ready(_)) {
          Stale(m)
        } else {
          Ready(m)
        }
        tiles.set(key, e)
      }
      before.tiles.clear()
    }
    sources.push(({ index: i, source: s, tiles, } : SourceTiles))
  }
  for src in self.sources {
    for _, e in src.tiles {
      self.release(e)
    }
  }
  self.sources.clear()
  self.sources.push_iter(sources.iter())
  self.style = next
  self.has_labels = next.layers.iter().any(l => l.kind is Symbol)
  self.content_version += 1
  self.dem_version += 1
  self.labels_dirty = true
  self.idle_fired = false
  for w in self.workers {
    post_style(w, style_json)
  }
  // Which layers draw by state may have changed.
  for src in self.sources {
    if self.feature_states.get(src.source.id) is Some(states) &&
      states.length() > 0 {
      for _, e in src.tiles {
        self.ask_ranges(src, e)
      }
    }
  }
  self.request_render()
}

///|
/// Loads every tile of source `id` again (its data changed), drawing the old
/// ones until then.
pub fn Map::reload_source(self : Map, id : String) -> Unit {
  guard self.sources.search_by(s => s.source.id == id) is Some(at) else {
    return
  }
  let tiles = self.sources[at].tiles
  let gone = []
  for key, e in tiles {
    match e.state {
      Ready(m) => e.state = Stale(m)
      Loading(request~, worker~, previous~) => {
        post_cancel(self.workers[worker], request)
        self.requests.remove(request)
        match previous {
          Some(m) => e.state = Stale(m)
          None => gone.push(key)
        }
      }
      Stale(_) => ()
      Failed => gone.push(key)
    }
  }
  for key in gone {
    tiles.remove(key)
  }
  // Asked for now rather than by the next frame, so they can be drawn in it.
  self.update_tiles(self.sources[at], self.cover(self.sources[at]))
  self.content_version += 1
  self.idle_fired = false
  self.request_render()
}
