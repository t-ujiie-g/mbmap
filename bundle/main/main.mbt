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
  ) catch {
    BadStyle(e) => throw_error("mbmap: style: \{e.message()}")
    NoWebGL2 => throw_error("mbmap: WebGL2 is not available")
    NoSource => throw_error("mbmap: the style draws from no source")
  }
}

///|
/// The camera as `{lng, lat, zoom, bearing, pitch}`.
#export_name("map_camera")
pub fn map_camera(map : @map.Map) -> JsCamera {
  js_camera(map.camera())
}

///|
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
