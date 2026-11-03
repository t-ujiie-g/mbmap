///|
/// Draws the shown icons of style layer `index` in one tile, before any of the
/// layer's text (MapLibre draws a symbol layer's icons, then its text).
fn Map::draw_icons(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  d : Draw,
  dpr : Double,
  height_scale : Double,
) -> Unit {
  guard layer.icon is Some(l) && layer.icon_paint is Some(paint) else { return }
  let t = self.transform
  let zoom = t.camera.zoom
  let (keys, geometry) = l.size.feature_inputs()
  let size = if keys.is_empty() && !geometry {
    number_or(l.size.eval(zoom, JsProps::none()), 1.0)
  } else {
    -1.0
  }
  let pitch = t.camera.pitch
  for m in d.meshes {
    guard m.layer == index &&
      m.labels is Some({ icon: Some(ic), .. }) &&
      ic.drawn != self.frame_count else {
      continue
    }
    // An ancestor standing in for several tiles is drawn once.
    ic.drawn = self.frame_count
    let s = m.labels.unwrap()
    let along = s.line is Some(_) && ic.rotate_with_map
    if s.line is Some(l) {
      let tile_px = d.at.units_per_pixel * dpr
      self.lay_line_glyphs(m.mesh, d.at, s, l, tile_px, height_scale)
    }
    let ctx = m.props.unwrap_or(JsProps::none())
    let c = fn(e : @style.Expr) -> FixedArray[Double] {
      let v = color_of(e, zoom, ctx)
      [v.r, v.g, v.b, v.a]
    }
    let n = (e : @style.Expr, d : Double) => number_or(e.eval(zoom, ctx), d)
    self.renderer.draw_icons(
      ic.mesh,
      d.at,
      dpr,
      size~,
      perspective=!ic.offset,
      pitch=ic.pitch_with_map,
      rotate=ic.rotate_with_map,
      angle=if ic.pitch_with_map && !ic.rotate_with_map {
        t.camera.bearing * @math.PI / 180.0
      } else {
        0.0
      },
      sdf=ic.sdf,
      // MapLibre samples icons as they are unless they are scaled or turned.
      linear=ic.sdf ||
        pitch != 0.0 ||
        ic.pitch_with_map ||
        size != 1.0 ||
        !ic.sharp,
      opacity=n(paint.opacity, 1.0),
      color=c(paint.color),
      halo=c(paint.halo_color),
      halo_width=n(paint.halo_width, 0.0),
      halo_blur=n(paint.halo_blur, 0.0),
      gamma_scale=if ic.pitch_with_map {
        @math.cos(pitch * @math.PI / 180.0) * d.at.center_depth
      } else {
        1.0
      },
      height_scale~,
      along~,
    )
  }
}
