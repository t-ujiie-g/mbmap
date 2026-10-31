///|
fn Map::render(self : Map) -> Unit {
  self.frame = -1
  if self.destroyed {
    return
  }
  self.frame_count += 1
  let dpr = device_pixel_ratio()
  let w = css_width(self.canvas)
  let h = css_height(self.canvas)
  let pw = (w * dpr).round().to_int()
  let ph = (h * dpr).round().to_int()
  if pw <= 0 || ph <= 0 {
    return
  }
  set_canvas_size(self.canvas, pw, ph)
  self.renderer.set_viewport(pw, ph)
  self.transform = self.transform.resize(w, h)
  let t = self.transform
  // Per source: its covering tiles, and where their meshes go this frame
  // (computed once for all of the source's layers).
  let mut settled = true
  let draws_of : @hashmap.HashMap[
    String,
    Array[(@render_webgl2.Placement, Array[LayerMesh])],
  ] = @hashmap.HashMap([])
  for src in self.sources {
    let s = src.source
    let z = t.tile_zoom(s.min_zoom, s.max_zoom)
    let cover = if t.camera.zoom < s.min_zoom.to_double() {
      []
    } else {
      t.covering_tiles(s.min_zoom, z)
    }
    self.update_tiles(src, cover)
    let draws = []
    for id in cover {
      match src.fallback(id) {
        Own(id, meshes) => draws.push((self.placement(id, None, dpr), meshes))
        Ancestor(id, meshes, clip~) =>
          draws.push((self.placement(id, Some(clip), dpr), meshes))
        Children(kids) =>
          for kid in kids {
            draws.push((self.placement(kid.0, None, dpr), kid.1))
          }
        Nothing => ()
      }
      settled = settled && src.settled(id)
    }
    draws_of.set(s.id, draws)
  }
  let (r, g, b) = self.background()
  self.renderer.clear(r, g, b)
  let zoom = t.camera.zoom
  for index, layer in self.style.layers {
    if layer.kind is Background ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    // Paint that does not read feature data is the same for every mesh.
    let shared = paint_of(layer, zoom, JsProps::none())
    for d in draws_of.get(layer.source).unwrap_or([]) {
      self.draw_layer(index, layer, shared, d.0, d.1, dpr)
    }
  }
  if settled {
    if !self.idle_fired {
      self.idle_fired = true
      for _, f in self.idle_listeners {
        f()
      }
    }
  } else {
    self.idle_fired = false
  }
}

///|
/// The first visible background layer's color, premultiplied onto white.
fn Map::background(self : Map) -> (Double, Double, Double) {
  let zoom = self.transform.camera.zoom
  for l in self.style.layers {
    if l.kind is Background && zoom >= l.min_zoom && zoom < l.max_zoom {
      let p = paint_of(l, zoom, JsProps::none())
      return (
        p.r * p.a + 1.0 - p.a,
        p.g * p.a + 1.0 - p.a,
        p.b * p.a + 1.0 - p.a,
      )
    }
  }
  (1.0, 1.0, 1.0)
}

///|
/// Draws `index`'s meshes of one tile; `shared` is the layer's paint for
/// meshes without group properties.
fn Map::draw_layer(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  shared : Paint,
  at : @render_webgl2.Placement,
  meshes : Array[LayerMesh],
  dpr : Double,
) -> Unit {
  let zoom = self.transform.camera.zoom
  for m in meshes {
    if m.layer != index {
      continue
    }
    let p = match (m.props, m.paint) {
      (None, _) => shared
      (Some(_), Some((z, p))) if z == zoom => p
      (Some(props), _) => {
        let p = paint_of(layer, zoom, props)
        m.paint = Some((zoom, p))
        p
      }
    }
    if m.kind == KIND_LINE {
      self.renderer.draw_line(m.mesh, at, p.r, p.g, p.b, p.a, p.width * dpr)
    } else if m.kind == KIND_CIRCLE {
      self.renderer.draw_circle(
        m.mesh,
        at,
        [p.r, p.g, p.b, p.a],
        p.stroke,
        p.radius * dpr,
        p.stroke_width * dpr,
      )
    } else {
      self.renderer.draw_fill(m.mesh, at, p.r, p.g, p.b, p.a)
    }
  }
}

///|
/// Where `id`'s meshes are drawn: only the part over the tile itself, or with
/// `clip` over that descendant tile (an ancestor standing in for it).
fn Map::placement(
  self : Map,
  id : @core.TileId,
  clip : @core.TileId?,
  dpr : Double,
) -> @render_webgl2.Placement {
  let t = self.transform
  let extent = @core.TILE_EXTENT
  let rect : FixedArray[Double] = match clip {
    // A tile draws only within itself: features reach into the buffer
    // around it, which its neighbors draw too (twice blended otherwise).
    None => [0.0, 0.0, extent.to_double(), extent.to_double()]
    Some(c) => {
      let dz = c.z - id.z
      let size = (extent >> dz).to_double()
      let x0 = (c.x - (id.x << dz)).to_double() * size
      let y0 = (c.y - (id.y << dz)).to_double() * size
      [x0, y0, x0 + size, y0 + size]
    }
  }
  {
    matrix: t.tile_matrix(id, extent),
    units_per_pixel: 1.0 / (t.tile_scale(id, extent) * dpr),
    center_depth: t.center_depth(),
    clip: rect,
  }
}
