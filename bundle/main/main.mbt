///|
/// `{lng, lat, zoom, bearing, pitch}` as a JS object.
#external
pub type JsCamera

///|
extern "js" fn js_camera(c : @core.Camera) -> JsCamera =
  #|(c) => ({ lng: c.center.lng, lat: c.center.lat, zoom: c.zoom, bearing: c.bearing, pitch: c.pitch })

///|
extern "js" fn throw_error(message : String) -> @map.Map =
  #|(m) => { throw new Error(m); }

///|
fn camera_of(
  lng : Double,
  lat : Double,
  zoom : Double,
  bearing : Double,
  pitch : Double,
) -> @core.Camera {
  { center: { lng, lat, }, zoom, bearing, pitch, }
}

///|
/// Creates a map; throws a JS Error if the style or WebGL2 is unusable.
#export_name("create_map")
pub fn create_map(
  canvas : @render_webgl2.Canvas,
  style_json : String,
  lng : Double,
  lat : Double,
  zoom : Double,
  bearing : Double,
  pitch : Double,
  worker_url : String,
  wasm_url : String,
  workers : Int32,
  geojson : @map.Provider,
  font : String,
  limits : FixedArray[Double],
  strict : Bool,
) -> @map.Map {
  @map.Map::new(
    canvas,
    style_json,
    camera_of(lng, lat, zoom, bearing, pitch),
    worker_url~,
    wasm_url~,
    workers~,
    geojson~,
    font~,
    limits=limits_of(limits),
    strict~,
  ) catch {
    BadStyle(e) => throw_error("mbmap: style: \{e.message()}")
    NoWebGL2 => throw_error("mbmap: WebGL2 is not available")
  }
}

///|
/// The camera as `{lng, lat, zoom, bearing, pitch}`.
#export_name("map_camera")
pub fn map_camera(map : @map.Map) -> JsCamera {
  js_camera(map.camera())
}

///|
/// `@map.Map::set_camera` from the camera's numbers.
#export_name("map_set_camera")
pub fn map_set_camera(
  map : @map.Map,
  lng : Double,
  lat : Double,
  zoom : Double,
  bearing : Double,
  pitch : Double,
) -> Unit {
  map.set_camera(camera_of(lng, lat, zoom, bearing, pitch))
}

///|
/// Calls `f` on camera changes (read the camera with `map_camera`); returns
/// an id for `map_off`.
#export_name("map_on_move")
pub fn map_on_move(map : @map.Map, f : () -> Unit) -> Int32 {
  map.on_move(_ => f())
}

///|
/// Calls `f` after each frame is drawn; returns an id for `map_off`.
#export_name("map_on_render")
pub fn map_on_render(map : @map.Map, f : () -> Unit) -> Int32 {
  map.on_render(f)
}

///|
/// Calls `f` each time the map settles after a change; returns an id for `map_off`.
#export_name("map_on_idle")
pub fn map_on_idle(map : @map.Map, f : () -> Unit) -> Int32 {
  map.on_idle(f)
}

///|
/// Removes the listener `id`.
#export_name("map_off")
pub fn map_off(map : @map.Map, id : Int32) -> Unit {
  map.off(id)
}

///|
/// Frames rendered so far (a test hook).
#export_name("map_frame_count")
pub fn map_frame_count(map : @map.Map) -> Int32 {
  map.frame_count()
}

///|
/// Stops workers, removes listeners and frees GPU buffers.
#export_name("map_destroy")
pub fn map_destroy(map : @map.Map) -> Unit {
  map.destroy()
}

///|
/// Limits from min zoom, max zoom, min pitch, max pitch and bounds (west,
/// south, east, north; NaN west for none).
fn limits_of(a : FixedArray[Double]) -> @core.Limits {
  {
    min_zoom: a[0],
    max_zoom: a[1],
    min_pitch: a[2],
    max_pitch: a[3],
    bounds: if a[4].is_nan() {
      None
    } else {
      Some({ west: a[4], south: a[5], east: a[6], north: a[7], })
    },
  }
}

///|
/// Sets the limits `limits_of` reads; the camera moves at once if outside them.
#export_name("map_set_limits")
pub fn map_set_limits(map : @map.Map, limits : FixedArray[Double]) -> Unit {
  map.set_limits(limits_of(limits))
}

///|
/// A move target from center (lng, lat), zoom, bearing, pitch, around (lng,
/// lat), each NaN for none, and the offset (x, y).
fn target_of(g : FixedArray[Double]) -> @core.CameraTarget {
  let some = (v : Double) => if v.is_nan() { None } else { Some(v) }
  @core.CameraTarget::new(
    center?=if g[0].is_nan() { None } else { Some({ lng: g[0], lat: g[1], }) },
    zoom?=some(g[2]),
    bearing?=some(g[3]),
    pitch?=some(g[4]),
    around?=if g[5].is_nan() { None } else { Some({ lng: g[5], lat: g[6], }) },
    offset=(g[7], g[8]),
  )
}

///|
/// `Map::ease_to` toward `target_of(g)`; `easing` maps 0-1 to 0-1.
#export_name("map_ease_to")
pub fn map_ease_to(
  map : @map.Map,
  g : FixedArray[Double],
  duration : Double,
  easing : (Double) -> Double,
  id : String,
) -> Unit {
  map.ease_to(target_of(g), duration~, easing~, id~)
}

///|
/// `Map::fly_to` with `o`: duration, curve, speed, screen speed, max
/// duration, min zoom (each NaN for the default).
#export_name("map_fly_to")
pub fn map_fly_to(
  map : @map.Map,
  g : FixedArray[Double],
  o : FixedArray[Double],
  easing : (Double) -> Double,
) -> Unit {
  let some = (v : Double) => if v.is_nan() { None } else { Some(v) }
  map.fly_to(
    target_of(g),
    duration?=some(o[0]),
    curve=some(o[1]).unwrap_or(1.42),
    speed=some(o[2]).unwrap_or(1.2),
    screen_speed?=some(o[3]),
    max_duration?=some(o[4]),
    min_zoom?=some(o[5]),
    easing~,
  )
}

///|
/// Stops a running animation.
#export_name("map_stop")
pub fn map_stop(map : @map.Map) -> Unit {
  map.stop()
}

///|
/// 1 while the camera moves (a gesture, inertia or an animation), 2 while an
/// animation runs, else 0.
#export_name("map_motion")
pub fn map_motion(map : @map.Map) -> Int32 {
  if map.is_easing() {
    2
  } else if map.is_moving() {
    1
  } else {
    0
  }
}

///|
/// Screen x and y of (lng, lat), on the terrain if any.
#export_name("map_project")
pub fn map_project(
  map : @map.Map,
  lng : Double,
  lat : Double,
) -> FixedArray[Double] {
  let (x, y, _) = map.locate({ lng, lat, })
  [x, y]
}

///|
/// For each (lng, lat) pair of `points`: its screen x and y on the terrain if
/// any, and 1 where the terrain hides it (0 otherwise).
#export_name("map_locate")
pub fn map_locate(
  map : @map.Map,
  points : FixedArray[Double],
) -> FixedArray[Double] {
  let n = points.length() / 2
  let out = FixedArray::make(n * 3, 0.0)
  for i in 0..<n {
    let (x, y, covered) = map.locate({
      lng: points[2 * i],
      lat: points[2 * i + 1],
    })
    out[3 * i] = x
    out[3 * i + 1] = y
    out[3 * i + 2] = if covered { 1.0 } else { 0.0 }
  }
  out
}

///|
/// Lng and lat under screen point (x, y), on the terrain if any.
#export_name("map_unproject")
pub fn map_unproject(
  map : @map.Map,
  x : Double,
  y : Double,
) -> FixedArray[Double] {
  let p = map.point_location(x, y)
  [p.lng, p.lat]
}

///|
/// West, south, east, north of the view.
#export_name("map_bounds")
pub fn map_bounds(map : @map.Map) -> FixedArray[Double] {
  let b = map.bounds()
  [b.west, b.south, b.east, b.north]
}

///|
/// `camera_for_bounds` of `b` (west, south, east, north, bearing, padding
/// top, right, bottom, left, offset x, y, max zoom or NaN): lng, lat, zoom,
/// bearing, pitch, or empty when it does not fit.
#export_name("map_camera_for_bounds")
pub fn map_camera_for_bounds(
  map : @map.Map,
  b : FixedArray[Double],
) -> FixedArray[Double] {
  let fit = map.camera_for_bounds(
    { west: b[0], south: b[1], east: b[2], north: b[3], },
    bearing=b[4],
    padding={ top: b[5], right: b[6], bottom: b[7], left: b[8], },
    offset=(b[9], b[10]),
    max_zoom?=if b[11].is_nan() { None } else { Some(b[11]) },
  )
  match fit {
    Some(c) => [c.center.lng, c.center.lat, c.zoom, c.bearing, c.pitch]
    None => []
  }
}

///|
let handlers : FixedArray[@map.Handler] = [
  DragPan,
  ScrollZoom,
  BoxZoom,
  DragRotate,
  Keyboard,
  DoubleClickZoom,
  TouchZoomRotate,
  TouchPitch,
]

///|
/// Turns handler `h` (an index into `handlers`) on or off.
#export_name("map_set_handler")
pub fn map_set_handler(map : @map.Map, h : Int32, enabled : Bool) -> Unit {
  if h >= 0 && h < handlers.length() {
    map.set_handler(handlers[h], enabled)
  }
}

///|
/// Calls `f` when the camera starts moving; returns an id for `map_off`.
#export_name("map_on_move_start")
pub fn map_on_move_start(map : @map.Map, f : (@map.Event) -> Unit) -> Int32 {
  map.on_move_start(f)
}

///|
/// Calls `f` when the camera stops; returns an id for `map_off`.
#export_name("map_on_move_end")
pub fn map_on_move_end(map : @map.Map, f : (@map.Event) -> Unit) -> Int32 {
  map.on_move_end(f)
}

///|
/// The input event behind the current camera change, or null.
#export_name("map_input_event")
pub fn map_input_event(map : @map.Map) -> @map.Event {
  map.input_event()
}

///|
/// MapLibre's default easing (`@core.Bezier::ease`) at `t`.
#export_name("default_easing")
pub fn default_easing(t : Double) -> Double {
  ease_curve.at(t)
}

///|
let ease_curve : @core.Bezier = @core.Bezier::ease()

///|
/// Draws `style_json` from now on; returns "" or, keeping the current style,
/// why it cannot be drawn.
#export_name("map_set_style")
pub fn map_set_style(
  map : @map.Map,
  style_json : String,
  strict : Bool,
) -> String {
  map.set_style(style_json, strict~) catch {
    BadStyle(e) => return "mbmap: style: \{e.message()}"
    NoWebGL2 => return "mbmap: WebGL2 is not available"
  }
  ""
}

///|
/// `@map.compile_cluster_properties`, for the GeoJSON worker.
#export_name("compile_cluster_properties")
pub fn compile_cluster_properties(text : String) -> Bytes {
  @map.compile_cluster_properties(text)
}

///|
/// What the current style uses that is not drawn: path, message, path, ...
#export_name("map_warnings")
pub fn map_warnings(map : @map.Map) -> FixedArray[String] {
  let out = []
  for w in map.warnings() {
    let (path, message) = match w {
      Invalid(path~, m) | Unsupported(path~, m) => (path, m)
    }
    out.push(path)
    out.push(message)
  }
  FixedArray::from_array(out)
}

///|
/// Loads the tiles of source `id` again, after its data changed.
#export_name("map_reload_source")
pub fn map_reload_source(map : @map.Map, id : String) -> Unit {
  map.reload_source(id)
}

///|
/// Loads again the tiles of source `id` that are loading or `changed`.
#export_name("map_reload_tiles")
pub fn map_reload_tiles(
  map : @map.Map,
  id : String,
  changed : (Int32, Int32, Int32) -> Bool,
) -> Unit {
  map.reload_tiles(id, changed)
}

///|
/// Shows `picture` (null for nothing) for image, video or canvas source `id`
/// placed by `quad` (see `@map.Map::set_media_quad`).
#export_name("map_set_media")
pub fn map_set_media(
  map : @map.Map,
  id : String,
  picture : @render_webgl2.Picture,
  quad : FixedArray[Double],
) -> Unit {
  map.set_media(id, picture, quad)
}

///|
/// Places source `id`'s picture by `quad`.
#export_name("map_set_media_quad")
pub fn map_set_media_quad(
  map : @map.Map,
  id : String,
  quad : FixedArray[Double],
) -> Unit {
  map.set_media_quad(id, quad)
}

///|
/// Draws the style's custom layers through `f` (`@map.CustomRenderer`).
#export_name("map_set_custom_renderer")
pub fn map_set_custom_renderer(map : @map.Map, f : @map.CustomRenderer) -> Unit {
  map.set_custom_renderer(f)
}

///|
/// The map's WebGL2RenderingContext.
#export_name("map_gl")
pub fn map_gl(map : @map.Map) -> @render_webgl2.Context {
  map.gl()
}

///|
/// Draws a frame soon.
#export_name("map_trigger_repaint")
pub fn map_trigger_repaint(map : @map.Map) -> Unit {
  map.trigger_repaint()
}

///|
/// Whether source `id`'s picture changes by itself (drawn every frame).
#export_name("map_set_media_playing")
pub fn map_set_media_playing(
  map : @map.Map,
  id : String,
  playing : Bool,
) -> Unit {
  map.set_media_playing(id, playing)
}

///|
/// The features under `points` (one point or a closed ring, CSS pixels) of the
/// layers named (all when `all_layers`) passing `filter` (JSON or ""); `done`
/// gets each tile's hits. Returns "" or why the query cannot run.
#export_name("map_query_rendered")
pub fn map_query_rendered(
  map : @map.Map,
  points : FixedArray[Double],
  all_layers : Bool,
  layers : FixedArray[String],
  filter : String,
  done : (@map.TileResults) -> Unit,
) -> String {
  let ps = Array::makei(points.length() / 2, i => {
    (points[i * 2], points[i * 2 + 1])
  })
  map.query_rendered(
    ps,
    if all_layers {
      None
    } else {
      Some(layers.iter().collect())
    },
    filter,
    done,
  )
}

///|
/// The features of `source_layer` in the drawn tiles of source `source`
/// passing `filter` (JSON, or ""); `done` gets each tile's. Returns "" or why
/// the query cannot run.
#export_name("map_query_source")
pub fn map_query_source(
  map : @map.Map,
  source : String,
  source_layer : String,
  filter : String,
  done : (@map.TileResults) -> Unit,
) -> String {
  map.query_source(source, source_layer, filter, done)
}

///|
/// Sets feature `id`'s state (a JS object, or null to remove it) in
/// `source_layer` ("" for GeoJSON) of `source`.
#export_name("map_set_feature_state")
pub fn map_set_feature_state(
  map : @map.Map,
  source : String,
  source_layer : String,
  id : String,
  state : @map.FeatureState,
) -> Unit {
  map.set_feature_state(source, source_layer, id, state)
}

///|
/// Sets the map's `transformRequest` for tiles: a function `(url, "Tile")`
/// giving `{url, headers?, credentials?}`, or null for none.
#export_name("map_set_transform_request")
pub fn map_set_transform_request(
  map : @map.Map,
  f : @map.RequestTransform,
) -> Unit {
  map.set_transform_request(f)
}

///|
/// Whether the map has settled: its tiles loaded and drawn.
#export_name("map_is_idle")
pub fn map_is_idle(map : @map.Map) -> Bool {
  map.is_idle()
}

///|
/// The largest side `map_render_region` draws at once.
#export_name("map_max_region")
pub fn map_max_region(map : @map.Map) -> Int32 {
  map.max_region()
}

///|
/// RGBA pixels, top row first, of a part of the view drawn at `ratio`
/// (`@map.Map::render_region`).
#export_name("map_render_region")
pub fn map_render_region(
  map : @map.Map,
  ratio : Double,
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> @render_webgl2.JsBuffer {
  map.render_region(ratio, x, y, width, height)
}

///|
/// The zoom `zoom` becomes at the current center once the camera is kept to
/// the limits (MapLibre's `getMinZoom(true)` asks it of the minimum).
#export_name("map_constrained_zoom")
pub fn map_constrained_zoom(map : @map.Map, zoom : Double) -> Double {
  map.constrained_zoom(zoom)
}

///|
/// Layer `id`'s paint now for a feature with properties `props`
/// (`@map.Map::paint_at`).
#export_name("map_paint_at")
pub fn map_paint_at(
  map : @map.Map,
  id : String,
  props : @map.Properties,
) -> @map.PaintValues {
  map.paint_at(id, props)
}

///|
/// Values of expression `text` for each of `features` at `zoom`, or the
/// error's message (`@map.evaluate_expression`).
#export_name("evaluate_expression")
pub fn evaluate_expression(
  text : String,
  features : FixedArray[@map.Properties],
  zoom : Double,
) -> @map.ExpressionValues {
  @map.evaluate_expression(text, features, zoom)
}

///|
/// The labels shown at the last placement (`@map.Map::placed_labels`), for
/// tests; the facade does not use it.
#export_name("map_placed_labels")
pub fn map_placed_labels(map : @map.Map) -> String {
  map.placed_labels()
}

///|
/// Adds or replaces style image `name` (straight RGBA bytes, `width` x
/// `height`); false when the bytes do not match the size.
#export_name("map_add_image")
pub fn map_add_image(
  map : @map.Map,
  name : String,
  width : Int32,
  height : Int32,
  data : FixedArray[Byte],
  pixel_ratio : Double,
  sdf : Bool,
) -> Bool {
  map.add_image(name, width, height, data, pixel_ratio~, sdf~)
}

///|
/// Removes style image `name`; false if there is none.
#export_name("map_remove_image")
pub fn map_remove_image(map : @map.Map, name : String) -> Bool {
  map.remove_image(name)
}

///|
/// Calls `f` with the name of an image the style lacks (`styleimagemissing`).
#export_name("map_on_missing_image")
pub fn map_on_missing_image(map : @map.Map, f : (String) -> Unit) -> Unit {
  map.on_missing_image(f)
}

///|
/// Holds tiles with icons while a sprite is `loading`.
#export_name("map_hold_images")
pub fn map_hold_images(map : @map.Map, loading : Bool) -> Unit {
  map.hold_images(loading)
}

///|
/// Longitude, latitude and meters up of what is drawn under screen point (x, y), or empty.
#export_name("map_pick_position")
pub fn map_pick_position(
  map : @map.Map,
  x : Double,
  y : Double,
) -> FixedArray[Double] {
  match map.pick_position(x, y) {
    Some((lng, lat, h)) => [lng, lat, h]
    None => []
  }
}

///|
/// Where the segment between two points (longitude, latitude, meters up) first meets what is drawn,
/// short of the second by `margin` meters, or empty.
#export_name("map_cast_ray")
pub fn map_cast_ray(
  map : @map.Map,
  points : FixedArray[Double],
  margin : Double,
) -> FixedArray[Double] {
  match
    map.cast_ray(
      (points[0], points[1], points[2]),
      (points[3], points[4], points[5]),
      margin,
    ) {
    Some((lng, lat, h)) => [lng, lat, h]
    None => []
  }
}

///|
/// Shows what is seen from the viewshed `v` (`Map::set_viewshed`'s eight numbers), or none when empty.
#export_name("map_set_viewshed")
pub fn map_set_viewshed(map : @map.Map, v : FixedArray[Double]) -> Unit {
  map.set_viewshed(if v.length() == 8 { Some(v) } else { None })
}

///|
/// Clips extrusions by `c` (`Map::set_clipping`), or nothing when empty.
#export_name("map_set_clipping")
pub fn map_set_clipping(map : @map.Map, c : FixedArray[Double]) -> Unit {
  map.set_clipping(c)
}
