///|
/// Pixels per side of a heatmap's density texture on a terrain tile, as
/// MapLibre's (the tile size).
const HEATMAP_TILE_SIZE : Double = 512.0

///|
/// Draws heatmap layer `index` as MapLibre does: each point's kernel added into
/// a density texture `scale` times the viewport's size, then colored through
/// the layer's ramp; `px` device (or texture) pixels per CSS pixel.
fn Map::draw_heatmap(
  self : Map,
  index : Int32,
  h : @style.HeatmapPaint,
  shared : Paint,
  draws : Array[Draw],
  px : Double,
  scale : Double,
) -> Unit {
  if shared.opacity == 0.0 {
    return
  }
  let zoom = self.transform.camera.zoom
  let intensity = number_or(h.intensity.eval(zoom, JsProps::none()), 1.0)
  self.renderer.begin_heatmap(scale)
  for i, d in draws {
    // Kernels reach across tiles, so a tile is drawn once and whole, and an
    // ancestor standing in for some of its children draws instead of them all.
    let skip = draws[:i].iter().any(o => o.id == d.id) ||
      draws.iter().any(o => o.id.z < d.id.z && overlap(o.id, d.id))
    if skip {
      continue
    }
    for m in d.meshes {
      if m.layer == index && m.kind == KIND_CIRCLE {
        self.renderer.draw_heatmap(
          m.mesh,
          d.at,
          self.slots(index, m, shared, zoom),
          intensity,
          px,
        )
      }
    }
  }
  self.renderer.end_heatmap(self.heatmap_ramp(h.color), shared.opacity)
}

///|
/// The 256-pixel color ramp of `heatmap-color` `e` over density (MapLibre's
/// `renderColorRamp`), made once per expression.
fn Map::heatmap_ramp(self : Map, e : @style.Expr) -> @render_webgl2.Gradient {
  match self.ramps.search_by(r => r.0 == e) {
    Some(i) => self.ramps[i].1
    None => {
      let pixels = @render_webgl2.color_ramp([], 256, d => {
        match e.eval(0.0, { ..JsProps::none(), density: d, }) {
          Color(c) => (c.r, c.g, c.b, c.a)
          _ => (0.0, 0.0, 0.0, 0.0)
        }
      })
      let g = self.renderer.upload_gradient(pixels, 256, 1, nearest=false)
      self.ramps.push((e, g))
      g
    }
  }
}

///|
/// Frees the heatmap ramps no layer of the current style uses.
fn Map::prune_ramps(self : Map) -> Unit {
  let used = (e : @style.Expr) => {
    self.style.layers.iter().any(l => l.heatmap is Some(h) && h.color == e)
  }
  for r in self.ramps {
    if !used(r.0) {
      self.renderer.release_gradient(r.1)
    }
  }
  self.ramps.retain(r => used(r.0))
}
