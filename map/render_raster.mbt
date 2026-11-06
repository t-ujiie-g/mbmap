///|
/// Draws a raster tile with a layer's paint at the current zoom.
fn Map::draw_raster(
  self : Map,
  r : @style.RasterPaint,
  mesh : @render_webgl2.Mesh,
  at : @render_webgl2.Placement,
) -> Unit {
  let zoom = self.transform.camera.zoom
  let ctx = JsProps::none()
  let n = (e : @style.Expr, d : Double) => number_or(e.eval(zoom, ctx), d)
  self.renderer.draw_raster(
    mesh,
    at,
    opacity=n(r.opacity, 1.0),
    hue_rotate=n(r.hue_rotate, 0.0),
    brightness_min=n(r.brightness_min, 0.0),
    brightness_max=n(r.brightness_max, 1.0),
    saturation=n(r.saturation, 0.0),
    contrast=n(r.contrast, 0.0),
    nearest=r.nearest,
  )
}

///|
/// Draws a tile's hillshade with a layer's paint at the current zoom; a light
/// anchored to the viewport turns with the map. Nothing is drawn without
/// exaggeration (MapLibre then prepares no slopes).
fn Map::draw_hillshade(
  self : Map,
  h : @style.HillshadePaint,
  mesh : @render_webgl2.Mesh,
  at : @render_webgl2.Placement,
) -> Unit {
  let zoom = self.transform.camera.zoom
  let ctx = JsProps::none()
  let exaggeration = number_or(h.exaggeration.eval(zoom, ctx), 0.5)
  if exaggeration == 0.0 {
    return
  }
  let turn = if h.viewport {
    @core.radians(self.transform.camera.bearing)
  } else {
    0.0
  }
  // Shorter lists repeat their last value (MapLibre's getIlluminationProperties).
  let pick = (list : Array[@style.Expr], i : Int32) => {
    list[@cmp.minimum(i, list.length() - 1)]
  }
  let n = h.highlight.length()
  let angles = FixedArray::make(n * 2, 0.0)
  let colors = FixedArray::make(n * 8, 0.0)
  for i in 0..<n {
    angles[i * 2] = @core.radians(
        number_or(pick(h.direction, i).eval(zoom, ctx), 335.0),
      ) +
      turn
    angles[i * 2 + 1] = @core.radians(
      number_or(pick(h.altitude, i).eval(zoom, ctx), 45.0),
    )
    let shadow = color_of(pick(h.shadow, i), zoom, ctx)
    let highlight = color_of(h.highlight[i], zoom, ctx)
    for
      k, v in [
        shadow.r,
        shadow.g,
        shadow.b,
        shadow.a,
        highlight.r,
        highlight.g,
        highlight.b,
        highlight.a,
      ] {
      colors[i * 8 + k] = v
    }
  }
  self.renderer.draw_hillshade(
    mesh,
    at,
    shading=match h.shading {
      Standard => 0
      Combined => 1
      Igor => 2
      Multidirectional => 3
      Basic => 4
    },
    exaggeration~,
    angles~,
    colors~,
    accent=rgba_of(color_of(h.accent, zoom, ctx)),
    nearest=h.nearest,
  )
}
