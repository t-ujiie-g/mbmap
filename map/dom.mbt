///|
/// A JS object passed around without inspection (DOM events, worker messages).
#external
priv type JsValue

///|
#external
priv type Worker

///|
extern "js" fn hardware_concurrency() -> Int32 =
  #|() => navigator.hardwareConcurrency || 2

///|
extern "js" fn device_pixel_ratio() -> Double =
  #|() => globalThis.devicePixelRatio || 1

///|
extern "js" fn css_width(canvas : @render_webgl2.Canvas) -> Double =
  #|(c) => c.clientWidth

///|
extern "js" fn css_height(canvas : @render_webgl2.Canvas) -> Double =
  #|(c) => c.clientHeight

///|
extern "js" fn set_canvas_size(
  canvas : @render_webgl2.Canvas,
  width : Int32,
  height : Int32,
) -> Unit =
  #|(c, w, h) => { if (c.width !== w) c.width = w; if (c.height !== h) c.height = h; }

///|
extern "js" fn request_frame(f : () -> Unit) -> Int32 =
  #|(f) => requestAnimationFrame(() => f())

///|
extern "js" fn cancel_frame(id : Int32) -> Unit =
  #|(id) => cancelAnimationFrame(id)

///|
/// Absolute URL for a tile; `template` may be relative to the page.
extern "js" fn tile_url(
  template : String,
  z : Int32,
  x : Int32,
  y : Int32,
) -> String =
  #|(t, z, x, y) => new URL(t.replace("{z}", z).replace("{x}", x).replace("{y}", y), location.href).href

///|
extern "js" fn absolute_url(url : String) -> String =
  #|(u) => new URL(u, location.href).href

///|
extern "js" fn spawn_worker(
  url : String,
  on_message : (JsValue) -> Unit,
) -> Worker =
  #|(url, f) => { const w = new Worker(url, { type: "module" }); w.onmessage = (e) => f(e.data); return w; }

///|
extern "js" fn post_init(
  w : Worker,
  wasm : String,
  style : String,
  font : String,
) -> Unit =
  #|(w, wasm, style, font) => w.postMessage({ type: "init", wasm, style, font })

///|
extern "js" fn post_tile(
  w : Worker,
  id : Int32,
  url : String,
  source : Int32,
  z : Int32,
  dem : Bool,
) -> Unit =
  #|(w, id, url, source, z, dem) => w.postMessage({ type: "tile", id, url, source, z, dem })

///|
extern "js" fn post_cancel(w : Worker, id : Int32) -> Unit =
  #|(w, id) => w.postMessage({ type: "cancel", id })

///|
extern "js" fn terminate(w : Worker) -> Unit =
  #|(w) => w.terminate()

///|
extern "js" fn get_string(v : JsValue, key : String) -> String =
  #|(v, k) => String(v[k] ?? "")

///|
extern "js" fn get_int(v : JsValue, key : String) -> Int32 =
  #|(v, k) => v[k] | 0

///|
extern "js" fn get_double(v : JsValue, key : String) -> Double =
  #|(v, k) => +v[k]

///|
extern "js" fn layers_of(v : JsValue) -> Int32 =
  #|(v) => (v.layers ?? []).length

///|
extern "js" fn layer_at(v : JsValue, i : Int32) -> JsValue =
  #|(v, i) => v.layers[i]

///|
extern "js" fn buffer_of(v : JsValue, key : String) -> @render_webgl2.JsBuffer =
  #|(v, k) => v[k]

///|
extern "js" fn console_warn(message : String) -> Unit =
  #|(m) => console.warn("[mbmap] " + m)

///|
/// Listens for `type` on `target`; returns a function that removes the listener.
extern "js" fn listen(
  target : @render_webgl2.Canvas,
  type_ : String,
  f : (JsValue) -> Unit,
) -> () -> Unit =
  #|(t, type, f) => {
  #|  const h = (e) => f(e);
  #|  const opts = { passive: type !== "wheel" };
  #|  t.addEventListener(type, h, opts);
  #|  return () => t.removeEventListener(type, h, opts);
  #|}

///|
extern "js" fn observe_resize(
  target : @render_webgl2.Canvas,
  f : () -> Unit,
) -> () -> Unit =
  #|(t, f) => { const o = new ResizeObserver(() => f()); o.observe(t); return () => o.disconnect(); }

///|
extern "js" fn prevent_default(e : JsValue) -> Unit =
  #|(e) => e.preventDefault()

///|
extern "js" fn capture_pointer(
  target : @render_webgl2.Canvas,
  e : JsValue,
) -> Unit =
  #|(t, e) => { try { t.setPointerCapture(e.pointerId); } catch {} }

///|
/// Wheel delta in CSS pixels, whatever the event's delta mode.
extern "js" fn wheel_pixels(e : JsValue) -> Double =
  #|(e) => e.deltaY * (e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? 800 : 1)

///|
/// The JS value parsed from `text` with JSON.parse, rebuilt as a MoonBit Json
/// through the given constructors (keeps a JSON parser out of the bundle).
extern "js" fn parse_json_js(
  text : String,
  null_ : () -> Json,
  bool_ : (Bool) -> Json,
  num : (Double) -> Json,
  str : (String) -> Json,
  arr : (FixedArray[Json]) -> Json,
  obj : (FixedArray[String], FixedArray[Json]) -> Json,
) -> Json =
  #|(text, mkNull, mkBool, mkNum, mkStr, mkArr, mkObj) => {
  #|  const build = (v) => {
  #|    if (v === null) return mkNull();
  #|    switch (typeof v) {
  #|      case "boolean": return mkBool(v);
  #|      case "number": return mkNum(v);
  #|      case "string": return mkStr(v);
  #|    }
  #|    if (Array.isArray(v)) return mkArr(v.map(build));
  #|    const keys = Object.keys(v);
  #|    return mkObj(keys, keys.map((k) => build(v[k])));
  #|  };
  #|  return build(JSON.parse(text));
  #|}

///|
fn parse_json(text : String) -> Json {
  parse_json_js(
    text,
    () => Json::null(),
    b => Json::boolean(b),
    n => Json::number(n),
    s => Json::string(s),
    items => Json::array(items.iter().collect()),
    (keys, values) => {
      let m = Map([])
      for i, k in keys {
        m[k] = values[i]
      }
      Json::object(m)
    },
  )
}

///|
/// 0 absent, 1 null, 2 boolean, 3 number, 4 string, 5 other.
extern "js" fn prop_kind(obj : JsValue, key : String) -> Int32 =
  #|(o, k) => {
  #|  if (o == null || !Object.hasOwn(o, k)) return 0;
  #|  const v = o[k];
  #|  return v === null ? 1 : typeof v === "boolean" ? 2 : typeof v === "number" ? 3 : typeof v === "string" ? 4 : 5;
  #|}

///|
extern "js" fn prop_bool(obj : JsValue, key : String) -> Bool =
  #|(o, k) => o[k]

///|
extern "js" fn props_or_null(layer : JsValue) -> JsValue =
  #|(l) => l.props ?? null

///|
extern "js" fn is_null_value(v : JsValue) -> Bool =
  #|(v) => v == null

///|
extern "js" fn js_null() -> JsValue =
  #|() => null

///|
/// Whether a pointerdown starts a rotating drag: right button or Ctrl held.
extern "js" fn rotating_drag(e : JsValue) -> Bool =
  #|(e) => e.button === 2 || e.ctrlKey

///|
/// Keeps the context menu from opening on the map, so right-drag rotates.
extern "js" fn prevent_context_menu(
  target : @render_webgl2.Canvas,
) -> () -> Unit =
  #|(t) => { const f = (e) => e.preventDefault(); t.addEventListener("contextmenu", f); return () => t.removeEventListener("contextmenu", f); }

///|
/// Posts an already loaded tile (an ArrayBuffer, transferred) to a worker.
extern "js" fn post_tile_bytes(
  w : Worker,
  id : Int32,
  bytes : JsValue,
  source : Int32,
  z : Int32,
) -> Unit =
  #|(w, id, bytes, source, z) => w.postMessage({ type: "tile", id, bytes, source, z }, [bytes])

///|
/// Asks the GeoJSON provider for a tile and calls `done` with its bytes, or
/// null when there is none or it failed (logged).
extern "js" fn call_provider(
  provider : Provider,
  source : String,
  z : Int32,
  x : Int32,
  y : Int32,
  done : (JsValue) -> Unit,
) -> Unit =
  #|(p, s, z, x, y, done) => {
  #|  Promise.resolve().then(() => p(s, z, x, y)).then(
  #|    (b) => done(b ?? null),
  #|    (e) => { console.warn(`mbmap: GeoJSON tile ${z}/${x}/${y}: ${e?.message ?? e}`); done(null); });
  #|}

///|
/// The GeoJSON tile provider `Map::new` takes: a JS function `(source, z, x,
/// y) => Promise<ArrayBuffer | null>` (source being the source's id), or JS
/// null.
#external
pub type Provider

///|
/// No provider (JS null).
pub fn no_provider() -> Provider {
  null_provider()
}

///|
extern "js" fn null_provider() -> Provider =
  #|() => null

///|
extern "js" fn is_null_provider(p : Provider) -> Bool =
  #|(p) => p == null
