///|
fn premultiplied(c : @style.Color) -> FixedArray[Double] {
  [c.r * c.a, c.g * c.a, c.b * c.a, c.a]
}

///|
fn blend_of(e : @style.Expr, zoom : Double, default : Double) -> Double {
  @cmp.maximum(
    0.0,
    @cmp.minimum(1.0, number_or(e.eval(zoom, JsProps::none()), default)),
  )
}

///|
/// How much fog terrain gets at `pitch` degrees: none up to 60°, all from 70°
/// (MapLibre's `calculateFogBlendOpacity`).
fn fog_opacity(pitch : Double) -> Double {
  @cmp.maximum(0.0, @cmp.minimum(1.0, (pitch - 60.0) / 10.0))
}

///|
/// Draws the style's sky above the horizon line, if it has one and the line is
/// on screen.
fn Map::draw_sky(self : Map, dpr : Double) -> Unit {
  let t = self.transform
  guard self.style.sky is Some(sky) && t.horizon() < t.height / 2.0 else {
    return
  }
  let zoom = t.camera.zoom
  self.renderer.draw_sky(
    (t.height / 2.0 + t.horizon()) * dpr,
    blend_of(sky.sky_horizon_blend, zoom, 0.8) * t.height / 2.0 * dpr,
    premultiplied(color_of(sky.sky, zoom, JsProps::none())),
    premultiplied(color_of(sky.horizon, zoom, JsProps::none())),
  )
}

///|
/// The terrain fog of the style's sky at the current camera (none without one).
fn Map::fog(self : Map) -> @render_webgl2.Fog {
  let t = self.transform
  let zoom = t.camera.zoom
  let (near, far) = t.fog_range()
  guard self.style.sky is Some(sky) else {
    let none : FixedArray[Double] = [0.0, 0.0, 0.0, 0.0]
    return {
      near,
      far,
      ground_blend: 1.0,
      opacity: 0.0,
      horizon_blend: 1.0,
      color: none,
      horizon: none,
    }
  }
  {
    near,
    far,
    ground_blend: blend_of(sky.fog_ground_blend, zoom, 0.5),
    opacity: fog_opacity(t.camera.pitch),
    horizon_blend: blend_of(sky.horizon_fog_blend, zoom, 0.8),
    color: premultiplied(color_of(sky.fog, zoom, JsProps::none())),
    horizon: premultiplied(color_of(sky.horizon, zoom, JsProps::none())),
  }
}
