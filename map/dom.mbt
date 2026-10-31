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
extern "js" fn post_init(w : Worker, wasm : String, style : String) -> Unit =
  #|(w, wasm, style) => w.postMessage({ type: "init", wasm, style })

///|
extern "js" fn post_tile(
  w : Worker,
  id : Int32,
  url : String,
  source : Int32,
  z : Int32,
) -> Unit =
  #|(w, id, url, source, z) => w.postMessage({ type: "tile", id, url, source, z })

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
