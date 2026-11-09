///|
/// The JS function custom layers are drawn through (`npm/src/custom.ts`), or
/// JS null: `(id, mode, numbers)` with a `CUSTOM_*` mode and `Map::custom_numbers`.
/// It restores the GL state the renderer relies on after the layer's own code.
#external
pub type CustomRenderer

///|
extern "js" fn no_custom() -> CustomRenderer = "() => null"

///|
extern "js" fn call_custom(
  f : CustomRenderer,
  id : String,
  mode : Int32,
  numbers : FixedArray[Double],
) -> Unit =
  #|(f, id, mode, n) => { if (f) f(id, mode, n); }

///|
/// What `call_custom` asks of a layer: `render`, `prerender`, or its shadow
/// casters' depth (mbmap's `renderShadow`).
const CUSTOM_RENDER : Int32 = 0

///|
const CUSTOM_PRERENDER : Int32 = 1

///|
const CUSTOM_SHADOW : Int32 = 2

///|
/// Where `custom_numbers` puts the globe's transition (0 off the globe), its clipping plane, the lights (a
/// flag, then nine), the shadows, and how many numbers there are; `renderInput` in `npm/src/custom.ts` mirrors them.
const CUSTOM_TRANSITION : Int32 = 37

///|
const CUSTOM_PLANE : Int32 = 72

///|
const CUSTOM_LIGHTS : Int32 = 76

///|
const CUSTOM_SHADOWS : Int32 = 86

///|
const CUSTOM_NUMBERS : Int32 = 122

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
/// What a custom layer is drawn with: MapLibre's MVP and projection matrices (through the export window), fov,
/// near, far, world size, pixels per meter; the globe's transition, matrices, planes, clipping plane; the lights;
/// the shadows' mode, intensity, ground share, texel and the light's views over Mercator 0 to 1 and the sphere.
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
  } else {
    out.push_iter(
      FixedArray::make(CUSTOM_LIGHTS - CUSTOM_TRANSITION, 0.0).iter(),
    )
  }
  match self.lights() {
    Some((ambient, sun, direction)) => {
      out.push(1.0)
      out.push_iter(
        [ambient.0, ambient.1, ambient.2, sun.0, sun.1, sun.2].iter(),
      )
      out.push_iter([direction.0, direction.1, direction.2].iter())
    }
    None =>
      out.push_iter(
        FixedArray::make(CUSTOM_SHADOWS - CUSTOM_LIGHTS, 0.0).iter(),
      )
  }
  match self.shadows {
    Some(s) => {
      let (mode, texel) = match s.sphere {
        Some(v) => (2.0, v.texel)
        None => (if s.spot { 3.0 } else { 1.0 }, s.flat.texel)
      }
      let t = self.transform
      let ws = t.world_size()
      out.push_iter([mode, s.intensity, s.ground, texel].iter())
      out.push_iter(
        self.world_light(s).scale(ws, ws, ws / t.pixels_per_meter()).m.iter(),
      )
      out.push_iter(
        s.sphere.map(v => v.matrix).unwrap_or(@core.Mat4::identity()).m.iter(),
      )
    }
    None =>
      out.push_iter(
        FixedArray::make(CUSTOM_NUMBERS - CUSTOM_SHADOWS, 0.0).iter(),
      )
  }
  FixedArray::from_array(out)
}

///|
/// Calls custom layer `id` (its `prerender` or `render`).
fn Map::draw_custom(self : Map, id : String, prerender~ : Bool) -> Unit {
  let mode = if prerender { CUSTOM_PRERENDER } else { CUSTOM_RENDER }
  call_custom(self.custom, id, mode, self.custom_numbers())
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
