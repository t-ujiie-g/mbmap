///|
/// `{lng, lat, zoom}` as a JS object.
#external
pub type JsCamera

///|
extern "js" fn js_camera(lng : Double, lat : Double, zoom : Double) -> JsCamera =
  #|(lng, lat, zoom) => ({ lng, lat, zoom })

///|
extern "js" fn throw_error(message : String) -> @map.Map =
  #|(m) => { throw new Error(m); }

///|
fn camera_of(lng : Double, lat : Double, zoom : Double) -> @core.Camera {
  { center: { lng, lat, }, zoom, }
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
  worker_url : String,
  wasm_url : String,
  workers : Int32,
) -> @map.Map {
  @map.Map::new(
    canvas,
    style_json,
    camera_of(lng, lat, zoom),
    worker_url~,
    wasm_url~,
    workers~,
  ) catch {
    e => throw_error("mbmap: \{Repr(e)}")
  }
}

///|
/// The camera as `{lng, lat, zoom}`.
#export_name("map_camera")
pub fn map_camera(map : @map.Map) -> JsCamera {
  let c = map.camera()
  js_camera(c.center.lng, c.center.lat, c.zoom)
}

///|
#export_name("map_set_camera")
pub fn map_set_camera(
  map : @map.Map,
  lng : Double,
  lat : Double,
  zoom : Double,
) -> Unit {
  map.set_camera(camera_of(lng, lat, zoom))
}

///|
/// Calls `f(lng, lat, zoom)` on camera changes; returns an id for `map_off`.
#export_name("map_on_move")
pub fn map_on_move(
  map : @map.Map,
  f : (Double, Double, Double) -> Unit,
) -> Int32 {
  map.on_move(c => f(c.center.lng, c.center.lat, c.zoom))
}

///|
#export_name("map_on_idle")
pub fn map_on_idle(map : @map.Map, f : () -> Unit) -> Int32 {
  map.on_idle(f)
}

///|
#export_name("map_off")
pub fn map_off(map : @map.Map, id : Int32) -> Unit {
  map.off(id)
}

///|
#export_name("map_frame_count")
pub fn map_frame_count(map : @map.Map) -> Int32 {
  map.frame_count()
}

///|
#export_name("map_gpu_bytes")
pub fn map_gpu_bytes(map : @map.Map) -> Int32 {
  map.gpu_bytes()
}

///|
#export_name("map_destroy")
pub fn map_destroy(map : @map.Map) -> Unit {
  map.destroy()
}
