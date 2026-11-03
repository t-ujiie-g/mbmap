///|
pub(all) suberror MapError {
  BadStyle(@style.StyleError)
  NoWebGL2
} derive(Debug)

///|
/// `entry` is the mesh's index in the worker's packed tile; `owned` false when an
/// earlier layer's; `paint` the group's paint at the zoom it was evaluated for;
/// `vertex_paint` the layer's own per-vertex paint (also when the geometry is
/// shared); `states` the ranges of features with a state, in index order;
/// `clips` a gradient line's rows and ramp length, `gradient` its ramp and expression.
priv struct LayerMesh {
  entry : Int32
  mut states : Array[StateRange]
  layer : Int32
  kind : Int32
  mesh : @render_webgl2.Mesh
  mut owned : Bool
  props : JsProps?
  mut paint : (Double, Paint)?
  vertex_paint : @render_webgl2.PaintBuffer?
  labels : LabelSet?
  ground : ExtrusionGround?
  dem : DemTile?
  clips : FixedArray[Double]?
  mut gradient : (@style.Expr, @render_webgl2.Gradient)?
}

///|
/// A stated feature's indices in a mesh: `first`, `count` of its triangles and
/// `outline_first`, `outline_count` of its fill outline.
priv struct StateRange {
  first : Int32
  count : Int32
  outline_first : Int32
  outline_count : Int32
  state : JsValue
}

///|
/// An extrusion mesh's features (`@render_webgl2.extrusion_runs`) and the DEM
/// version its ground heights were last looked up at.
priv struct ExtrusionGround {
  runs : FixedArray[Int32]
  mut at : Int32
}

///|
/// A tile's meshes or how far it is: `Stale` meshes were made under an
/// earlier style and are drawn until the tile is loaded again (`Loading`
/// keeps them as `previous` meanwhile).
priv enum TileState {
  Loading(request~ : Int32, worker~ : Int32, previous~ : Array[LayerMesh]?)
  Ready(Array[LayerMesh])
  Stale(Array[LayerMesh])
  Failed
}

///|
/// `kept`: the worker keeping the tile's bytes for queries and the request
/// they came with, or (-1, -1).
priv struct TileEntry {
  id : @core.TileId
  mut state : TileState
  mut last_used : Int32
  mut kept : (Int32, Int32)
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
/// Bearing and pitch change per CSS pixel of a rotating drag (right button
/// or Ctrl), as in MapLibre.
const ROTATE_RATE : Double = 0.8

///|
const PITCH_RATE : Double = 0.5

///|
/// A map drawn into a canvas. It owns its camera, workers and GPU resources;
/// the camera can be read and replaced as a value (`camera`, `set_camera`).
pub struct Map {
  priv canvas : @render_webgl2.Canvas
  priv renderer : @render_webgl2.Renderer
  priv mut style : @style.Style
  /// Per style layer: its per-vertex paint (`@style.StyleLayer::vertex_paint`).
  priv mut vertex_paint : Array[Array[@style.VertexPaint]]
  priv sources : Array[SourceTiles]
  priv geojson : Provider
  priv mut transform : @core.Transform
  priv workers : Array[Worker]
  priv mut next_worker : Int32
  priv requests : @hashmap.HashMap[Int32, (Int32, Int64)]
  priv mut next_request : Int32
  priv mut frame : Int32
  priv mut frame_count : Int32
  priv mut idle_fired : Bool
  priv listeners : @hashmap.HashMap[Int32, Listener]
  priv mut moving : Bool
  priv mut animation : Animation?
  priv mut input_event : Event
  priv mut handlers : Int32
  priv mut wheel_timer : Int32
  priv inertia : Array[Sample]
  priv mut next_listener : Int32
  priv pointers : Array[(Int32, Double, Double)]
  priv mut rotating : Bool
  priv mut dragging : Bool
  priv mut press : (Double, Double)
  priv mut box_start : (
    Double,
    Double,
    (Double, Double, Double, Double) -> Unit,
    () -> Unit,
  )?
  priv cleanups : Array[() -> Unit]
  priv mut destroyed : Bool
  priv mut has_labels : Bool
  priv targets : @hashmap.HashMap[Int64, TerrainTarget]
  priv mut content_version : Int32
  priv atlas : @label.Atlas
  priv mut atlas_full : Bool
  priv mut labels_dirty : Bool
  priv mut dem_version : Int32
  priv mut placed_camera : @core.Camera?
  priv mut placed_at : Double
  priv mut placement_round : Int32
  priv mut drawn : @hashmap.HashMap[String, Array[Draw]]
  priv waiting : @hashmap.HashMap[Int32, Waiting]
  priv mut ranges_waiting : Int32
  priv mut transform_request : RequestTransform
  priv mut next_query : Int32
  priv mut window : Window?
  priv feature_states : @hashmap.HashMap[
    String,
    @hashmap.HashMap[String, JsValue],
  ]
  priv images : @hashmap.HashMap[String, @render_webgl2.StyleImage]
  priv missing_images : @hashset.HashSet[String]
  priv mut on_missing_image : (String) -> Unit
  /// Heatmap color ramps by `heatmap-color` expression.
  priv ramps : Array[(@style.Expr, @render_webgl2.Gradient)]
}

///|
/// What a listener (`on_move`, `on_idle`, `on_move_start`, `on_move_end`)
/// listens for; one map holds them all, so the bundle has one map type.
priv enum Listener {
  Move((@core.Camera) -> Unit)
  Idle(() -> Unit)
  Render(() -> Unit)
  Start((Event) -> Unit)
  End((Event) -> Unit)
}

///|
fn Map::fire_move(self : Map, c : @core.Camera) -> Unit {
  for _, l in self.listeners {
    if l is Move(f) {
      f(c)
    }
  }
}

///|
/// Creates a map drawing `style_json` into `canvas` with `workers` tile workers
/// (0 picks half the hardware threads, up to `MAX_WORKERS`); `geojson` gives
/// GeoJSON sources' tiles and `font` is the CSS font family labels are drawn in.
pub fn Map::new(
  canvas : @render_webgl2.Canvas,
  style_json : String,
  camera : @core.Camera,
  worker_url~ : String,
  wasm_url~ : String,
  workers~ : Int32 = 2,
  geojson~ : Provider = no_provider(),
  font~ : String = "sans-serif",
  limits~ : @core.Limits = @core.Limits::default(),
) -> Map raise MapError {
  let style = @style.Style::from_json(parse_json(style_json)) catch {
    e => raise BadStyle(e)
  }
  // The sources the drawable layers use, in style order.
  let sources : Array[SourceTiles] = []
  for i, s in style.sources {
    if draws_from(style, s.id) {
      sources.push({ index: i, source: s, tiles: @hashmap.HashMap([]), })
    }
  }
  guard @render_webgl2.Renderer::new(canvas) is Some(renderer) else {
    raise NoWebGL2
  }
  let map : Map = {
    canvas,
    renderer,
    style,
    vertex_paint: style.layers.map(l => l.vertex_paint()),
    sources,
    geojson,
    transform: @core.Transform::new(
      camera,
      css_width(canvas),
      css_height(canvas),
      limits~,
    ),
    workers: [],
    next_worker: 0,
    requests: @hashmap.HashMap([]),
    next_request: 0,
    frame: -1,
    frame_count: 0,
    idle_fired: false,
    listeners: @hashmap.HashMap([]),
    moving: false,
    animation: None,
    input_event: no_event(),
    handlers: ALL_HANDLERS,
    wheel_timer: -1,
    inertia: [],
    next_listener: 0,
    pointers: [],
    rotating: false,
    dragging: false,
    press: (0.0, 0.0),
    box_start: None,
    cleanups: [],
    destroyed: false,
    has_labels: style.layers.iter().any(l => l.kind is Symbol),
    targets: @hashmap.HashMap([]),
    content_version: 0,
    atlas: @label.Atlas::new(
      @render_webgl2.ATLAS_SIZE,
      @render_webgl2.ATLAS_SIZE,
    ),
    atlas_full: false,
    labels_dirty: false,
    dem_version: 0,
    placed_camera: None,
    placed_at: 0.0,
    placement_round: 0,
    drawn: @hashmap.HashMap([]),
    waiting: @hashmap.HashMap([]),
    ranges_waiting: 0,
    transform_request: no_transform(),
    next_query: 0,
    window: None,
    feature_states: @hashmap.HashMap([]),
    images: @hashmap.HashMap([]),
    missing_images: @hashset.HashSet([]),
    on_missing_image: _ => (),
    ramps: [],
  }
  let wasm = absolute_url(wasm_url)
  let count = if workers > 0 {
    workers
  } else {
    @cmp.maximum(1, @cmp.minimum(MAX_WORKERS, hardware_concurrency() / 2))
  }
  for _ in 0..<count {
    let w = spawn_worker(absolute_url(worker_url), msg => map.on_message(msg))
    post_init(w, wasm, style_json, font)
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
/// Moves the camera at once, stopping an animation. Like any camera change it
/// fires `move` (between `move_start` and `move_end`), unless the value is
/// unchanged, so an outside state store can echo cameras back safely.
pub fn Map::set_camera(self : Map, camera : @core.Camera) -> Unit {
  self.stop()
  if self.transform.with_camera(camera).camera == self.transform.camera {
    return
  }
  self.begin_move(no_event())
  self.apply_camera(camera)
  self.end_move(no_event())
}

///|
/// Calls `f` with the new camera whenever it changes; returns an id for `off`.
pub fn Map::on_move(self : Map, f : (@core.Camera) -> Unit) -> Int32 {
  self.next_listener += 1
  self.listeners.set(self.next_listener, Move(f))
  self.next_listener
}

///|
/// Calls `f` once the visible tiles are loaded and drawn, each time the map
/// settles after a change; returns an id for `off`.
pub fn Map::on_idle(self : Map, f : () -> Unit) -> Int32 {
  self.next_listener += 1
  self.listeners.set(self.next_listener, Idle(f))
  self.next_listener
}

///|
/// Calls `f` after each frame is drawn.
pub fn Map::on_render(self : Map, f : () -> Unit) -> Int32 {
  self.next_listener += 1
  self.listeners.set(self.next_listener, Render(f))
  self.next_listener
}

///|
pub fn Map::off(self : Map, id : Int32) -> Unit {
  self.listeners.remove(id)
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
  for src in self.sources {
    for _, e in src.tiles {
      if e.state is Ready(meshes) {
        for m in meshes {
          if m.owned {
            n += m.mesh.byte_size()
          }
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
  if self.wheel_timer >= 0 {
    clear_timeout(self.wheel_timer)
  }
  self.animation = None
  self.end_queries()
  for f in self.cleanups {
    f()
  }
  for w in self.workers {
    terminate(w)
  }
  for src in self.sources {
    for _, e in src.tiles {
      self.release(e)
    }
    src.tiles.clear()
  }
}

///|
fn Map::apply_camera(self : Map, camera : @core.Camera) -> Unit {
  let next = self.transform.with_camera(camera)
  if next.camera == self.transform.camera {
    return
  }
  self.transform = next
  self.idle_fired = false
  self.fire_move(next.camera)
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
  self.content_version += 1
  self.drop_kept(e)
  match e.state {
    Ready(meshes) | Stale(meshes) => self.release_meshes(meshes)
    Loading(request~, worker~, previous~) => {
      post_cancel(self.workers[worker], request)
      self.requests.remove(request)
      if previous is Some(meshes) {
        self.release_meshes(meshes)
      }
    }
    Failed => ()
  }
}

///|
/// Lets the worker keeping `e`'s bytes free them.
fn Map::drop_kept(self : Map, e : TileEntry) -> Unit {
  let (worker, request) = e.kept
  if worker >= 0 && !self.destroyed {
    post_drop(self.workers[worker], request)
  }
  e.kept = (-1, -1)
}

///|
fn Map::release_meshes(self : Map, meshes : Array[LayerMesh]) -> Unit {
  for m in meshes {
    if m.owned {
      self.renderer.release(m.mesh)
    }
    if m.vertex_paint is Some(b) {
      self.renderer.release_paint(b)
    }
    if m.gradient is Some((_, g)) {
      self.renderer.release_gradient(g)
    }
  }
}

///|
/// Sets the function tile requests pass through (`RequestTransform`), or
/// none with JS null.
pub fn Map::set_transform_request(self : Map, f : RequestTransform) -> Unit {
  self.transform_request = f
}
