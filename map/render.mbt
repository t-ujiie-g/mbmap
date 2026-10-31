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
  let z = t.tile_zoom(self.source.min_zoom, self.source.max_zoom)
  let cover = if t.camera.zoom < self.source.min_zoom.to_double() {
    []
  } else {
    t.covering_tiles(z)
  }
  self.update_tiles(cover)
  let sources = cover.map(id => self.source_for(id))
  let (r, g, b) = self.background()
  self.renderer.clear(r, g, b)
  let zoom = t.camera.zoom
  for index, layer in self.style.layers {
    // Paint that does not read feature data is the same for every mesh.
    let shared = paint_of(layer, zoom, JsProps::none())
    if layer.kind is Background ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    for s in sources {
      match s {
        Own(id, meshes) =>
          self.draw_layer(index, layer, shared, id, meshes, dpr)
        Ancestor(id, meshes, clip~) => {
          self.clip_to(clip, dpr, ph)
          self.draw_layer(index, layer, shared, id, meshes, dpr)
          self.renderer.no_scissor()
        }
        Children(kids) =>
          for kid in kids {
            self.draw_layer(index, layer, shared, kid.0, kid.1, dpr)
          }
        Nothing => ()
      }
    }
  }
  if cover.iter().all(id => self.settled(id)) {
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
  id : @core.TileId,
  meshes : Array[LayerMesh],
  dpr : Double,
) -> Unit {
  for m in meshes {
    if m.layer != index {
      continue
    }
    let tt = self.transform.tile_transform(id, @core.TILE_EXTENT)
    let p = match m.props {
      Some(props) => paint_of(layer, self.transform.camera.zoom, props)
      None => shared
    }
    if m.line {
      self.renderer.draw_line(m.mesh, tt, p.r, p.g, p.b, p.a, p.width * dpr)
    } else {
      self.renderer.draw_fill(m.mesh, tt, p.r, p.g, p.b, p.a)
    }
  }
}

///|
/// Scissors drawing to `id`'s area on screen.
fn Map::clip_to(
  self : Map,
  id : @core.TileId,
  dpr : Double,
  ph : Int32,
) -> Unit {
  let b = id.mercator_bounds()
  let (x0, y0) = self.transform.mercator_to_screen({ x: b.min_x, y: b.min_y, })
  let (x1, y1) = self.transform.mercator_to_screen({ x: b.max_x, y: b.max_y, })
  let left = (x0 * dpr).floor().to_int()
  let right = (x1 * dpr).ceil().to_int()
  let top = (y0 * dpr).floor().to_int()
  let bottom = (y1 * dpr).ceil().to_int()
  self.renderer.scissor(left, ph - bottom, right - left, bottom - top)
}
