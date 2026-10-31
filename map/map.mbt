///|
pub(all) suberror MapError {
  BadStyle(@style.StyleError)
  NoWebGL2
  NoVectorSource
} derive(Debug)

///|
/// `owned` is false when the mesh belongs to an earlier layer of the same tile;
/// `props` are the inputs a data-driven layer's group shares, and `paint` caches
/// their paint at the zoom it was evaluated for.
priv struct LayerMesh {
  layer : Int32
  line : Bool
  mesh : @render_webgl2.Mesh
  owned : Bool
  props : JsProps?
  mut paint : (Double, Paint)?
}

///|
priv enum TileState {
  Loading(request~ : Int32, worker~ : Int32)
  Ready(Array[LayerMesh])
  Failed
}

///|
priv struct TileEntry {
  id : @core.TileId
  mut state : TileState
  mut last_used : Int32
}

///|
/// Tiles kept beyond the ones on screen, for panning back and as fallbacks.
const MAX_CACHED_TILES : Int32 = 96

///|
/// How many zoom levels up to look for a loaded tile to show meanwhile.
const MAX_FALLBACK_LEVELS : Int32 = 4

///|
/// Most tile workers started by default (VISION §4-7).
const MAX_WORKERS : Int32 = 4

///|
/// Wheel zoom per CSS pixel of scrolling.
const WHEEL_ZOOM_RATE : Double = 1.0 / 450.0

///|
/// A map drawn into a canvas. It owns its camera, workers and GPU resources;
/// the camera can be read and replaced as a value (`camera`, `set_camera`).
pub struct Map {
  priv canvas : @render_webgl2.Canvas
  priv renderer : @render_webgl2.Renderer
  priv style : @style.Style
  priv source_index : Int32
  priv source : @style.VectorSource
  priv mut transform : @core.Transform
  priv workers : Array[Worker]
  priv mut next_worker : Int32
  priv tiles : @hashmap.HashMap[Int64, TileEntry]
  priv requests : @hashmap.HashMap[Int32, Int64]
  priv mut next_request : Int32
  priv mut frame : Int32
  priv mut frame_count : Int32
  priv mut idle_fired : Bool
  priv move_listeners : @hashmap.HashMap[Int32, (@core.Camera) -> Unit]
  priv idle_listeners : @hashmap.HashMap[Int32, () -> Unit]
  priv mut next_listener : Int32
  priv pointers : @hashmap.HashMap[Int32, (Double, Double)]
  priv cleanups : Array[() -> Unit]
  priv mut destroyed : Bool
}

///|
/// Creates a map drawing `style_json` into `canvas`. `worker_url` is
/// worker/js/worker.mjs and `wasm_url` the wasm-gc build of the worker
/// package. `workers` tile workers are started; 0 picks half the hardware
/// threads, between 1 and `MAX_WORKERS`.
pub fn Map::new(
  canvas : @render_webgl2.Canvas,
  style_json : String,
  camera : @core.Camera,
  worker_url~ : String,
  wasm_url~ : String,
  workers~ : Int32 = 2,
) -> Map raise MapError {
  let style = @style.Style::from_json(parse_json(style_json)) catch {
    e => raise BadStyle(e)
  }
  // One vector source for now: the first one a layer draws from.
  let mut source_index = -1
  for l in style.layers {
    if l.kind is Background {
      continue
    }
    for i, s in style.sources {
      if s.id == l.source && source_index < 0 {
        source_index = i
      }
    }
  }
  if source_index < 0 {
    raise NoVectorSource
  }
  guard @render_webgl2.Renderer::new(canvas) is Some(renderer) else {
    raise NoWebGL2
  }
  let map : Map = {
    canvas,
    renderer,
    style,
    source_index,
    source: style.sources[source_index],
    transform: @core.Transform::new(
      camera,
      css_width(canvas),
      css_height(canvas),
    ),
    workers: [],
    next_worker: 0,
    tiles: @hashmap.HashMap([]),
    requests: @hashmap.HashMap([]),
    next_request: 0,
    frame: -1,
    frame_count: 0,
    idle_fired: false,
    move_listeners: @hashmap.HashMap([]),
    idle_listeners: @hashmap.HashMap([]),
    next_listener: 0,
    pointers: @hashmap.HashMap([]),
    cleanups: [],
    destroyed: false,
  }
  let wasm = absolute_url(wasm_url)
  let count = if workers > 0 {
    workers
  } else {
    @cmp.maximum(1, @cmp.minimum(MAX_WORKERS, hardware_concurrency() / 2))
  }
  for _ in 0..<count {
    let w = spawn_worker(absolute_url(worker_url), msg => map.on_message(msg))
    post_init(w, wasm, style_json)
    map.workers.push(w)
  }
  map.attach_input()
  map.cleanups.push(observe_resize(canvas, () => map.request_render()))
  map.request_render()
  map
}

///|
pub fn Map::camera(self : Map) -> @core.Camera {
  self.transform.camera
}

///|
/// Moves the camera. Like any camera change it fires `move`, unless the value
/// is unchanged, so an outside state store can echo cameras back safely.
pub fn Map::set_camera(self : Map, camera : @core.Camera) -> Unit {
  self.apply_camera(camera)
}

///|
/// Calls `f` with the new camera whenever it changes; returns an id for `off`.
pub fn Map::on_move(self : Map, f : (@core.Camera) -> Unit) -> Int32 {
  self.next_listener += 1
  self.move_listeners.set(self.next_listener, f)
  self.next_listener
}

///|
/// Calls `f` once the visible tiles are loaded and drawn, each time the map
/// settles after a change; returns an id for `off`.
pub fn Map::on_idle(self : Map, f : () -> Unit) -> Int32 {
  self.next_listener += 1
  self.idle_listeners.set(self.next_listener, f)
  self.next_listener
}

///|
pub fn Map::off(self : Map, id : Int32) -> Unit {
  self.move_listeners.remove(id)
  self.idle_listeners.remove(id)
}

///|
/// Frames rendered so far.
pub fn Map::frame_count(self : Map) -> Int32 {
  self.frame_count
}

///|
/// GPU bytes held by loaded tiles.
pub fn Map::gpu_bytes(self : Map) -> Int32 {
  let mut n = 0
  for _, e in self.tiles {
    if e.state is Ready(meshes) {
      for m in meshes {
        if m.owned {
          n += m.mesh.byte_size()
        }
      }
    }
  }
  n
}

///|
/// Stops workers, removes listeners and frees GPU buffers.
pub fn Map::destroy(self : Map) -> Unit {
  if self.destroyed {
    return
  }
  self.destroyed = true
  if self.frame >= 0 {
    cancel_frame(self.frame)
  }
  for f in self.cleanups {
    f()
  }
  for w in self.workers {
    terminate(w)
  }
  for _, e in self.tiles {
    self.release(e)
  }
  self.tiles.clear()
}

///|
fn Map::apply_camera(self : Map, camera : @core.Camera) -> Unit {
  let next = self.transform.with_camera(camera)
  if next.camera == self.transform.camera {
    return
  }
  self.transform = next
  self.idle_fired = false
  for _, f in self.move_listeners {
    f(next.camera)
  }
  self.request_render()
}

///|
fn Map::request_render(self : Map) -> Unit {
  if self.frame < 0 && !self.destroyed {
    self.frame = request_frame(() => self.render())
  }
}

///|
fn Map::release(self : Map, e : TileEntry) -> Unit {
  match e.state {
    Ready(meshes) =>
      for m in meshes {
        if m.owned {
          self.renderer.release(m.mesh)
        }
      }
    Loading(request~, worker~) => {
      post_cancel(self.workers[worker], request)
      self.requests.remove(request)
    }
    Failed => ()
  }
}
