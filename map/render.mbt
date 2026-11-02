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
  let resized = self.transform.resize(w, h)
  if resized.camera != self.transform.camera {
    // The limits moved the camera to fit the new size.
    self.transform = resized
    self.fire_move(resized.camera)
  } else {
    self.transform = resized
  }
  self.step_animation()
  let terrain = self.terrain_source()
  if terrain is Some(src) &&
    elevation_at(src, self.transform.camera.center.to_mercator()) is Some(e) {
    self.transform = self.transform.with_elevation(e * self.exaggeration())
  }
  let t = self.transform
  // Per source: its covering tiles, and where their meshes go this frame
  // (computed once for all of the source's layers).
  let mut settled = true
  let draws_of : @hashmap.HashMap[String, Array[Draw]] = @hashmap.HashMap([])
  for src in self.sources {
    let s = src.source
    let z = t.tile_zoom(s.min_zoom, s.max_zoom, tile_size=s.tile_size)
    let cover = if t.camera.zoom + @core.zoom_shift(s.tile_size).to_double() <
      s.min_zoom.to_double() {
      []
    } else {
      t.covering_tiles(s.min_zoom, z)
    }
    self.update_tiles(src, cover)
    let draws = []
    for id in cover {
      match src.fallback(id) {
        Own(id, meshes) =>
          draws.push({ id, at: self.placement(id, None, dpr), meshes, })
        Ancestor(id, meshes, clip~) =>
          draws.push({ id, at: self.placement(id, Some(clip), dpr), meshes, })
        Children(kids) =>
          for kid in kids {
            draws.push({
              id: kid.0,
              at: self.placement(kid.0, None, dpr),
              meshes: kid.1,
            })
          }
        Nothing => ()
      }
      settled = settled && src.settled(id)
    }
    draws_of.set(s.id, draws)
  }
  self.drawn = draws_of
  if self.placement_due() {
    self.place_labels(draws_of)
  }
  let (r, g, b) = self.background()
  self.renderer.clear(r, g, b)
  self.draw_sky(dpr)
  let zoom = t.camera.zoom
  if terrain is Some(src) {
    self.render_terrain(src, draws_of, dpr)
  } else {
    self.renderer.reset_depth()
  }
  let height_scale = if terrain is Some(_) { self.terrain_scale() } else { 0.0 }
  let light = self.extrusion_light()
  for index, layer in self.style.layers {
    // With terrain, all but symbols and extrusions are drawn onto it.
    if layer.kind is Background ||
      (terrain is Some(_) && !(layer.kind is (Symbol | FillExtrusion))) ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    // Paint that does not read feature data is the same for every mesh.
    let shared = paint_of(layer, zoom, JsProps::none())
    for d in draws_of.get(layer.source).unwrap_or([]) {
      if layer.extrusion is Some(e) {
        if terrain is Some(src) {
          self.ground_extrusions(src, d)
        }
        self.draw_extrusions(
          index,
          layer,
          e,
          shared,
          d,
          light,
          terrain is Some(_),
        )
      } else {
        self.draw_layer(
          index,
          layer,
          shared,
          d.at,
          d.meshes,
          dpr,
          height_scale~,
        )
      }
    }
  }
  if settled {
    if !self.idle_fired {
      self.idle_fired = true
      for _, l in self.listeners {
        if l is Idle(f) {
          f()
        }
      }
    }
  } else {
    self.idle_fired = false
  }
}

///|
/// `m`'s paint at `zoom`: `shared` unless its features carry their own inputs.
fn mesh_paint(
  m : LayerMesh,
  layer : @style.StyleLayer,
  shared : Paint,
  zoom : Double,
) -> Paint {
  match (m.props, m.paint) {
    (None, _) => shared
    (Some(_), Some((z, p))) if z == zoom => p
    (Some(props), _) => {
      let p = paint_of(layer, zoom, props)
      m.paint = Some((zoom, p))
      p
    }
  }
}

///|
/// Draws `index`'s extrusion meshes of one tile, raised onto terrain if any.
fn Map::draw_extrusions(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  e : @style.ExtrusionPaint,
  shared : Paint,
  d : Draw,
  light : @render_webgl2.ExtrusionLight,
  on_terrain : Bool,
) -> Unit {
  let t = self.transform
  let zoom = t.camera.zoom
  // Heights were taken at the tile's zoom and one deeper.
  let mix = @cmp.maximum(0.0, @cmp.minimum(1.0, zoom - d.id.z.to_double()))
  let exaggeration = if on_terrain { self.exaggeration() } else { 0.0 }
  for m in d.meshes {
    if m.layer != index || m.ground is None {
      continue
    }
    let p = mesh_paint(m, layer, shared, zoom)
    self.renderer.draw_extrusion(
      m.mesh,
      d.at,
      (p.r, p.g, p.b),
      p.a,
      light,
      e.vertical_gradient,
      mix,
      t.pixels_per_meter(),
      exaggeration,
    )
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
/// meshes without group properties; `height_scale` raises labels on terrain.
fn Map::draw_layer(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  shared : Paint,
  at : @render_webgl2.Placement,
  meshes : Array[LayerMesh],
  dpr : Double,
  height_scale~ : Double = 0.0,
) -> Unit {
  let zoom = self.transform.camera.zoom
  for m in meshes {
    if m.kind == KIND_HILLSHADE && layer.hillshade is Some(h) {
      self.draw_hillshade(h, m.mesh, at)
      continue
    }
    if m.layer != index {
      continue
    }
    let p = mesh_paint(m, layer, shared, zoom)
    if m.labels is Some(s) {
      // An ancestor standing in for several tiles is drawn once.
      if s.drawn != self.frame_count {
        s.drawn = self.frame_count
        self.renderer.draw_symbols(
          m.mesh,
          at,
          dpr,
          [p.r, p.g, p.b, p.a],
          p.halo,
          p.halo_width * dpr,
          height_scale~,
        )
      }
    } else if m.kind == KIND_LINE {
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
/// Draws a tile's hillshade with a layer's paint at the current zoom (MapLibre's
/// `standard` method); a light anchored to the viewport turns with the map.
fn Map::draw_hillshade(
  self : Map,
  h : @style.HillshadePaint,
  mesh : @render_webgl2.Mesh,
  at : @render_webgl2.Placement,
) -> Unit {
  let zoom = self.transform.camera.zoom
  let ctx = JsProps::none()
  let direction = number_or(h.direction.eval(zoom, ctx), 335.0) +
    (if h.viewport { self.transform.camera.bearing } else { 0.0 })
  fn rgba(e : @style.Expr) -> FixedArray[Double] {
    let c = color_of(e, zoom, ctx)
    [c.r, c.g, c.b, c.a]
  }
  self.renderer.draw_hillshade(
    mesh,
    at,
    direction * @math.PI / 180.0,
    number_or(h.exaggeration.eval(zoom, ctx), 0.5),
    rgba(h.shadow),
    rgba(h.highlight),
    rgba(h.accent),
  )
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
    latitudes: (id.lnglat_bounds().max_y, id.lnglat_bounds().min_y),
  }
}
