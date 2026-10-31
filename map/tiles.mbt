///|
/// `@worker.KIND_LINE`, mirrored so the main bundle does not pull in the worker.
const KIND_LINE : Int32 = 2

///|
fn Map::request_tile(self : Map, id : @core.TileId) -> Unit {
  let request = self.next_request
  self.next_request += 1
  let worker = self.next_worker
  self.next_worker = (worker + 1) % self.workers.length()
  let template = self.source.tiles[request % self.source.tiles.length()]
  post_tile(
    self.workers[worker],
    request,
    tile_url(template, id.z, id.x, id.y),
    self.source_index,
    id.z,
  )
  self.requests.set(request, id.key())
  self.tiles.set(id.key(), {
    id,
    state: Loading(request~, worker~),
    last_used: self.frame_count,
  })
}

///|
fn Map::on_message(self : Map, msg : JsValue) -> Unit {
  if self.destroyed {
    return
  }
  match get_string(msg, "type") {
    "tile" | "tile-error" as kind => {
      let request = get_int(msg, "id")
      guard self.requests.get(request) is Some(key) else { return }
      self.requests.remove(request)
      guard self.tiles.get(key) is Some(entry) else { return }
      if kind == "tile-error" {
        let id = entry.id
        console_warn(
          "tile \{id.z}/\{id.x}/\{id.y}: \{get_string(msg, "message")}",
        )
        entry.state = Failed
      } else {
        let meshes : Array[LayerMesh] = []
        for i in 0..<layers_of(msg) {
          let l = layer_at(msg, i)
          let shared = get_int(l, "shared")
          let line = get_int(l, "kind") == KIND_LINE
          let mesh = if shared >= 0 && shared < meshes.length() {
            meshes[shared].mesh
          } else {
            self.renderer.upload(
              line,
              buffer_of(l, "vertices"),
              buffer_of(l, "indices"),
              get_int(l, "count"),
              get_int(l, "indexBytes"),
            )
          }
          let props = props_or_null(l)
          meshes.push({
            layer: get_int(l, "layer"),
            line,
            mesh,
            owned: shared < 0,
            props: if is_null_value(props) {
              None
            } else {
              Some({ obj: props, })
            },
          })
        }
        entry.state = Ready(meshes)
      }
      self.request_render()
    }
    "error" => console_warn("worker: \{get_string(msg, "message")}")
    _ => ()
  }
}

///|
/// Requests the covering tiles that are missing and cancels loads that are
/// no longer needed.
fn Map::update_tiles(self : Map, cover : Array[@core.TileId]) -> Unit {
  let wanted = @hashset.HashSet([])
  for id in cover {
    wanted.add(id.key())
    match self.tiles.get(id.key()) {
      Some(e) => e.last_used = self.frame_count
      None => self.request_tile(id)
    }
  }
  let stale = []
  for key, e in self.tiles {
    if e.state is Loading(_) && !wanted.contains(key) {
      stale.push(key)
    }
  }
  for key in stale {
    if self.tiles.get(key) is Some(e) {
      self.release(e)
    }
    self.tiles.remove(key)
  }
  self.evict(wanted)
}

///|
/// Drops the least recently used loaded tiles beyond `MAX_CACHED_TILES`.
fn Map::evict(self : Map, wanted : @hashset.HashSet[Int64]) -> Unit {
  let extra = self.tiles.length() - wanted.length() - MAX_CACHED_TILES
  if extra <= 0 {
    return
  }
  let candidates = []
  for key, e in self.tiles {
    if !wanted.contains(key) {
      candidates.push((e.last_used, key))
    }
  }
  candidates.sort_by((a, b) => a.0.compare(b.0))
  for i in 0..<@cmp.minimum(extra, candidates.length()) {
    let key = candidates[i].1
    if self.tiles.get(key) is Some(e) {
      self.release(e)
    }
    self.tiles.remove(key)
  }
}

///|
fn Map::ready(self : Map, id : @core.TileId) -> Array[LayerMesh]? {
  match self.tiles.get(id.key()) {
    Some({ state: Ready(meshes), .. }) => Some(meshes)
    _ => None
  }
}

///|
/// What to draw for one covering tile: itself, or a loaded ancestor clipped
/// to its area, or its loaded children.
priv enum Source {
  Own(@core.TileId, Array[LayerMesh])
  Ancestor(@core.TileId, Array[LayerMesh], clip~ : @core.TileId)
  Children(Array[(@core.TileId, Array[LayerMesh])])
  Nothing
}

///|
fn Map::source_for(self : Map, id : @core.TileId) -> Source {
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
fn Map::settled(self : Map, id : @core.TileId) -> Bool {
  match self.tiles.get(id.key()) {
    Some({ state: Ready(_) | Failed, .. }) => true
    _ => false
  }
}
