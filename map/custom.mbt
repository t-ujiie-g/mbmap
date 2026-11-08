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
/// far planes, the world size in pixels and the pixels per meter; on the globe then the transition,
/// the globe's matrix and projection, its near and far planes and its clipping plane.
fn Map::custom_numbers(self : Map) -> FixedArray[Double] {
  let t = self.transform
  let windowed = (m : @core.Mat4) => {
    match self.window {
      None => m
      Some(w) => w.matrix.mul(m)
    }
  }
  let (p, near, far) = t.projection()
  let out = [..windowed(t.world_matrix()).m, ..windowed(p).m]
  out.push(@core.FIELD_OF_VIEW)
  out.push(near)
  out.push(far)
  out.push(t.world_size())
  out.push(t.pixels_per_meter())
  if self.globe is Some(g) && g.is_globe() {
    let (p, near, far) = g.projection_matrix()
    let (a, b, c, d) = g.clipping_plane_of()
    out.push(g.transition())
    out.push_iter(windowed(g.globe_matrix()).m.iter())
    out.push_iter(windowed(p).m.iter())
    out.push(near)
    out.push(far)
    out.push_iter([a, b, c, d].iter())
  }
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
