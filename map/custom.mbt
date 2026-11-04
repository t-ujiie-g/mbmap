///|
/// The JS function custom layers are drawn through (`npm/src/custom.ts`), or
/// JS null: `(id, prerender, numbers)` with `Map::custom_numbers`. It restores
/// the GL state the renderer relies on after the layer's own code.
#external
pub type CustomRenderer

///|
extern "js" fn no_custom() -> CustomRenderer = "() => null"

///|
extern "js" fn call_custom(
  f : CustomRenderer,
  id : String,
  prerender : Bool,
  numbers : FixedArray[Double],
) -> Unit =
  #|(f, id, prerender, n) => { if (f) f(id, prerender, n); }

///|
/// Draws the style's custom layers (`type: "custom"`) through `f` from now on.
pub fn Map::set_custom_renderer(self : Map, f : CustomRenderer) -> Unit {
  self.custom = f
  self.changed()
}

///|
/// The WebGL2RenderingContext the map draws with.
pub fn Map::gl(self : Map) -> @render_webgl2.Context {
  self.renderer.context()
}

///|
/// Draws a frame soon, as MapLibre's `triggerRepaint` (a custom layer's
/// animation asks for each of its frames).
pub fn Map::trigger_repaint(self : Map) -> Unit {
  self.request_render()
}

///|
/// What a custom layer is drawn with: MapLibre's `modelViewProjectionMatrix` and `projectionMatrix`
/// (16 numbers each, through the export window if any), the field of view in radians, the near and
/// far planes, the world size in pixels and the pixels per meter.
fn Map::custom_numbers(self : Map) -> FixedArray[Double] {
  let t = self.transform
  let (p, near, far) = t.projection()
  let (mvp, p) = match self.window {
    None => (t.world_matrix(), p)
    Some(w) => (w.matrix.mul(t.world_matrix()), w.matrix.mul(p))
  }
  let out = [..mvp.m, ..p.m]
  out.push(@core.FIELD_OF_VIEW)
  out.push(near)
  out.push(far)
  out.push(t.world_size())
  out.push(t.pixels_per_meter())
  FixedArray::from_array(out)
}

///|
/// Calls custom layer `id` (its `prerender` or `render`).
fn Map::draw_custom(self : Map, id : String, prerender~ : Bool) -> Unit {
  call_custom(self.custom, id, prerender, self.custom_numbers())
}

///|
/// The custom layers' `prerender`, before the frame is drawn (MapLibre's
/// offscreen pass).
fn Map::prerender_custom(self : Map) -> Unit {
  let zoom = self.transform.camera.zoom
  for layer in self.style.layers {
    if layer.kind is Custom && zoom >= layer.min_zoom && zoom < layer.max_zoom {
      self.draw_custom(layer.id, prerender=true)
    }
  }
}
