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
  let resized = match self.globe {
    Some(g) => {
      if w != self.transform.width || h != self.transform.height {
        g.resize(w, h)
      }
      g.mercator()
    }
    None => self.transform.resize(w, h)
  }
  if resized.camera != self.transform.camera {
    // The limits moved the camera to fit the new size.
    self.transform = resized
    self.fire_move(resized.camera)
  } else {
    self.transform = resized
  }
  self.step_animation()
  if self.globe is Some(g) {
    // MapLibre takes the projection's transition from the zoom of each frame.
    g.update_transition()
  }
  // The center stands on the terrain, at 0 m where no DEM tile has loaded.
  let elevation = match self.terrain_source() {
    Some(src) if !self.on_globe() =>
      elevation_at(src, self.transform.camera.center.to_mercator()).unwrap_or(
        0.0,
      ) *
      self.exaggeration()
    _ => 0.0
  }
  self.transform = self.transform.with_elevation(elevation)
  self.send_images()
  let (draws_of, settled) = self.draws(dpr, load=true)
  self.drawn = draws_of
  if self.placement_due() {
    self.place_labels(draws_of)
  }
  self.draw_frame(draws_of, dpr)
  if self.media_playing() {
    self.request_render()
  }
  for _, l in self.listeners {
    if l is Render(f) {
      f()
    }
  }
  // Feature states still being placed by the workers.
  if settled && self.ranges_waiting == 0 {
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
/// `at` moved by `layer`'s `*-translate` (MapLibre's `translatePosition`): CSS px
/// in tile `id`'s units at the camera's zoom, turned with the camera when
/// anchored to the viewport.
fn Map::translated(
  self : Map,
  at : @render_webgl2.Placement,
  layer : @style.StyleLayer,
  id : @core.TileId,
) -> @render_webgl2.Placement {
  self.translate_by(at, id, layer.translate, layer.translate_viewport)
}

///|
/// `at` moved by a symbol layer's `icon-translate`.
fn Map::icon_translated(
  self : Map,
  at : @render_webgl2.Placement,
  layer : @style.StyleLayer,
  id : @core.TileId,
) -> @render_webgl2.Placement {
  match layer.icon_paint {
    Some(p) => self.translate_by(at, id, p.translate, p.translate_viewport)
    None => at
  }
}

///|
/// `at` moved by `translate` CSS px, turned with the camera when `viewport`
/// (MapLibre's `translatePosition`).
fn Map::translate_by(
  self : Map,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  translate : @style.Expr,
  viewport : Bool,
) -> @render_webgl2.Placement {
  let (x, y) = @style.translate_at(
    translate,
    self.transform.camera.zoom,
    JsProps::none(),
  )
  if x == 0.0 && y == 0.0 {
    return at
  }
  let (x, y) = if viewport {
    let a = @core.radians(self.transform.camera.bearing)
    let c = @math.cos(a)
    let s = @math.sin(a)
    (x * c - y * s, x * s + y * c)
  } else {
    (x, y)
  }
  let k = 1.0 / self.transform.tile_scale(id, @core.TILE_EXTENT)
  {
    ..at,
    matrix: at.matrix.translate(x * k, y * k, 0.0),
    raster_matrix: at.raster_matrix.translate(x * k, y * k, 0.0),
  }
}

///|
/// Whether a symbol layer's halo goes in a pass of its own, as MapLibre draws it
/// when glyphs may overlap: halos wider than 1 px (or by feature), or letters
/// spaced closer.
fn Map::halo_apart(
  self : Map,
  layer : @style.StyleLayer,
  halo_width : Double,
) -> Bool {
  let by_feature = (e : @style.Expr) => {
    let (keys, geometry) = e.feature_inputs()
    keys.length() > 0 || geometry || e.reads_state()
  }
  let spacing = match layer.text {
    Some(t) if !by_feature(t.letter_spacing) =>
      number_or(
        t.letter_spacing.eval(self.transform.camera.zoom, JsProps::none()),
        0.0,
      )
    _ => 0.0
  }
  halo_width > 1.0 || by_feature(layer.halo_width) || spacing < 0.0
}

///|
/// Draws a circle layer with a sort key as MapLibre does: every tile's runs of
/// equal keys together, in key order (tiles, then runs, in order on ties).
fn Map::draw_circles_by_key(
  self : Map,
  index : Int32,
  layer : @style.StyleLayer,
  shared : Paint,
  draws : Array[Draw],
  dpr : Double,
) -> Unit {
  let zoom = self.transform.camera.zoom
  let runs : Array[(Double, Draw, LayerMesh, Int32, Int32)] = []
  for d in draws {
    for m in d.meshes {
      guard m.layer == index && m.kind == @core.KIND_CIRCLE else { continue }
      match m.key_runs {
        Some(r) if m.states.is_empty() =>
          for k in 0..<(r.length() / 3) {
            runs.push(
              (r[k * 3], d, m, r[k * 3 + 1].to_int(), r[k * 3 + 2].to_int()),
            )
          }
        _ => self.draw_layer(index, layer, shared, d.id, d.at, [m], dpr)
      }
    }
  }
  let keys = runs.map(r => r.0)
  for k in @core.stable_order(keys[:]) {
    let (_, d, m, first, count) = runs[k]
    let at = self.translated(d.at, layer, d.id)
    let p = mesh_paint(m, layer, shared, zoom)
    self.renderer.set_range(m.mesh, first, count)
    self.renderer.draw_circle(
      m.mesh,
      at,
      self.slots(index, m, p, zoom),
      dpr,
      scale_with_map=layer.scale_with_map,
      pitch_with_map=layer.pitch_with_map,
      blur=p.blur,
    )
  }
  for r in runs {
    self.renderer.whole_mesh(r.2.mesh)
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
  pass : Int32,
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
    // A pattern draws nothing while its image is missing, as in MapLibre.
    let pattern = match p.pattern {
      Some(name) =>
        match self.pattern(name) {
          Some(pos) => Some(pos)
          None => continue
        }
      None => None
    }
    let at = self.translated(d.at, layer, d.id)
    self.draw_by_state(m, layer, p, zoom, p => {
      self.renderer.draw_extrusion(
        m.mesh,
        at,
        (p.r, p.g, p.b),
        if pattern is Some(_) {
          p.opacity
        } else {
          p.a
        },
        light,
        e.vertical_gradient,
        mix,
        t.pixels_per_meter(),
        exaggeration,
        pattern~,
        pass~,
      )
    })
  }
}

///|
/// The first visible background layer's color, premultiplied onto white (white
/// when it is a pattern, drawn over the tiles).
fn Map::background(self : Map) -> (Double, Double, Double) {
  let zoom = self.transform.camera.zoom
  for l in self.style.layers {
    if l.kind is Background && zoom >= l.min_zoom && zoom < l.max_zoom {
      // A pattern is drawn over the tiles instead.
      if l.pattern is Some(_) {
        return (1.0, 1.0, 1.0)
      }
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
  id : @core.TileId,
  at : @render_webgl2.Placement,
  meshes : Array[LayerMesh],
  dpr : Double,
  height_scale~ : Double = 0.0,
) -> Unit {
  let at = self.translated(at, layer, id)
  let zoom = self.transform.camera.zoom
  // Dashes and the width they are measured in are taken at the integer zoom.
  let floor_zoom = @cmp.maximum(0.0, zoom.floor())
  let by_feature = layer.feature_dashes() is Some(_)
  let dash = match layer.dasharray {
    Some(e) if !by_feature => self.dash_of(e, zoom, layer.cap is Round)
    _ => None
  }
  // Fill outlines go after every fill of the tile, as MapLibre draws them.
  let outlines : Array[() -> Unit] = []
  for m in meshes {
    if m.kind == @core.KIND_HILLSHADE && layer.hillshade is Some(h) {
      self.draw_hillshade(h, m.mesh, at)
      continue
    }
    if m.kind == @core.KIND_HILLSHADE && layer.relief is Some(r) {
      self.draw_relief(layer, r, m, at)
      continue
    }
    if m.kind == @core.KIND_RASTER && layer.raster is Some(r) {
      self.draw_raster(r, m.mesh, at)
      continue
    }
    if m.layer != index {
      continue
    }
    let p = mesh_paint(m, layer, shared, zoom)
    if m.labels is Some(s) {
      // An ancestor standing in for several tiles is drawn once; MapLibre hides
      // text below 0.1 opacity.
      if s.drawn != self.frame_count && p.opacity >= 0.1 {
        s.drawn = self.frame_count
        if s.line is Some(l) {
          let tile_px = at.units_per_pixel * dpr
          self.lay_line_glyphs(m.mesh, at, s, l, tile_px, height_scale)
        }
        self.renderer.draw_symbols(
          m.mesh,
          at,
          dpr,
          p.rgba(),
          p.halo,
          p.halo_width,
          halo_blur=p.blur,
          two_pass=self.halo_apart(layer, p.halo_width),
          opacity=p.opacity,
          gamma_scale=@math.cos(@core.radians(self.transform.camera.pitch)) *
            at.center_depth,
          height_scale~,
        )
      }
    } else if m.kind == @core.KIND_LINE &&
      layer.gradient is Some(e) &&
      self.gradient_of(m, e) is Some(g) {
      self.draw_by_state(m, layer, p, zoom, p => {
        self.renderer.draw_line_gradient(
          m.mesh,
          at,
          self.slots(index, m, p, zoom),
          dpr,
          g,
          blur=p.blur,
        )
      })
    } else if m.kind == @core.KIND_LINE && layer.pattern is Some(_) {
      guard p.pattern is Some(name) && self.pattern(name) is Some(pos) else {
        continue
      }
      let (floor_width, floor_t) = self.floor_width(index, layer, m, zoom)
      self.draw_by_state(m, layer, p, zoom, p => {
        self.renderer.draw_line_pattern(
          m.mesh,
          at,
          self.slots(index, m, p, zoom),
          dpr,
          pos,
          floor_width~,
          floor_t~,
          blur=p.blur,
        )
      })
    } else if m.kind == @core.KIND_LINE && by_feature {
      let (floor_width, floor_t) = self.floor_width(index, layer, m, zoom)
      let px_per_unit = @math.pow(2.0, floor_zoom - zoom) /
        (at.units_per_pixel * dpr)
      self.draw_by_state(m, layer, p, zoom, p => {
        self.renderer.draw_line_dash_by_feature(
          m.mesh,
          at,
          self.slots(index, m, p, zoom),
          dpr,
          zoom_in=zoom > floor_zoom,
          px_per_unit~,
          floor_width~,
          floor_t~,
          blur=p.blur,
        )
      })
    } else if m.kind == @core.KIND_LINE {
      match dash {
        Some((entry, gamma_width)) => {
          let (floor_width, floor_t) = self.floor_width(index, layer, m, zoom)
          // CSS pixels per tile unit at the integer zoom.
          let px_per_unit = @math.pow(2.0, floor_zoom - zoom) /
            (at.units_per_pixel * dpr)
          self.draw_by_state(m, layer, p, zoom, p => {
            self.renderer.draw_line_dash(
              m.mesh,
              at,
              self.slots(index, m, p, zoom),
              dpr,
              entry,
              gamma_width~,
              px_per_unit~,
              floor_width~,
              floor_t~,
              blur=p.blur,
            )
          })
        }
        None =>
          self.draw_by_state(m, layer, p, zoom, p => {
            self.renderer.draw_line(
              m.mesh,
              at,
              self.slots(index, m, p, zoom),
              dpr,
              blur=p.blur,
            )
          })
      }
    } else if m.kind == @core.KIND_CIRCLE {
      self.draw_by_state(m, layer, p, zoom, p => {
        self.renderer.draw_circle(
          m.mesh,
          at,
          self.slots(index, m, p, zoom),
          dpr,
          scale_with_map=layer.scale_with_map,
          pitch_with_map=layer.pitch_with_map,
          blur=p.blur,
        )
      })
    } else if layer.pattern is Some(_) {
      self.draw_fill_pattern(index, layer, m, p, at, outlines)
    } else {
      self.draw_by_state(m, layer, p, zoom, p => {
        self.renderer.draw_fill(m.mesh, at, self.slots(index, m, p, zoom))
      })
      if layer.antialias {
        outlines.push(() => {
          self.draw_by_state(m, layer, p, zoom, outline=true, p => {
            self.renderer.draw_fill_outline(
              m.mesh,
              at,
              self.slots(index, m, p, zoom),
            )
          })
        })
      }
    }
  }
  for f in outlines {
    f()
  }
}

///|
/// Draws every layer of the frame into the current viewport.
fn Map::draw_frame(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
  dpr : Double,
) -> Unit {
  let t = self.transform
  let globe = self.on_globe()
  self.renderer.set_pitch(t.camera.pitch)
  // Terrain is not drawn on the globe yet.
  let terrain = if globe { None } else { self.terrain_source() }
  self.prerender_custom()
  self.prepare_relief(draws_of)
  if globe {
    // Space around the globe stays clear, as MapLibre leaves it.
    self.renderer.clear(0.0, 0.0, 0.0, alpha=0.0)
  } else {
    let (r, g, b) = self.background()
    self.renderer.clear(r, g, b)
    self.draw_sky(dpr)
  }
  let zoom = t.camera.zoom
  if terrain is Some(src) {
    self.render_terrain(src, draws_of, dpr)
  } else {
    self.renderer.reset_depth()
  }
  let height_scale = if terrain is Some(_) { self.terrain_scale() } else { 0.0 }
  let light = self.extrusion_light()
  for index, layer in self.style.layers {
    if globe {
      if zoom < layer.min_zoom || zoom >= layer.max_zoom {
        continue
      }
      // Vector layers come onto the globe once their geometry is subdivided.
      match layer.kind {
        Background if layer.pattern is Some(_) => {
          self.draw_background_pattern(layer)
          continue
        }
        Background => {
          self.draw_globe_background(layer)
          continue
        }
        Fill | Line | Circle | Symbol | Heatmap | FillExtrusion => continue
        _ => ()
      }
    }
    if layer.kind is Background &&
      layer.pattern is Some(_) &&
      terrain is None &&
      zoom >= layer.min_zoom &&
      zoom < layer.max_zoom {
      self.draw_background_pattern(layer)
      continue
    }
    // With terrain, all but symbols, extrusions and custom layers are drawn onto it.
    if layer.kind is Background ||
      (terrain is Some(_) && !(layer.kind is (Symbol | FillExtrusion | Custom))) ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    if layer.kind is Custom {
      self.draw_custom(layer.id, prerender=false)
      continue
    }
    // Paint that does not read feature data is the same for every mesh.
    let shared = paint_of(layer, zoom, JsProps::none())
    if layer.heatmap is Some(h) {
      let draws = draws_of.get(layer.source).unwrap_or([])
      self.draw_heatmap(index, h, shared, draws, dpr, HEATMAP_SCREEN_SCALE)
      continue
    }
    if layer.extrusion is Some(e) {
      let draws = draws_of.get(layer.source).unwrap_or([])
      if terrain is Some(src) {
        for d in draws {
          self.ground_extrusions(src, d)
        }
      }
      let on_terrain = terrain is Some(_)
      // MapLibre draws translucent or patterned extrusions in two passes over
      // all tiles: the nearest surfaces' depth, then their color.
      if shared.opacity < 1.0 || layer.pattern is Some(_) {
        for d in draws {
          self.draw_extrusions(index, layer, e, shared, d, light, on_terrain, 1)
        }
        self.renderer.begin_extrusion_color()
        for d in draws {
          self.draw_extrusions(index, layer, e, shared, d, light, on_terrain, 2)
        }
      } else {
        for d in draws {
          self.draw_extrusions(index, layer, e, shared, d, light, on_terrain, 0)
        }
      }
      continue
    }
    let draws = draws_of.get(layer.source).unwrap_or([])
    if layer.kind is Circle && layer.sort_key is Some(_) {
      self.draw_circles_by_key(index, layer, shared, draws, dpr)
      continue
    }
    self.draw_icons(index, layer, draws, dpr, height_scale)
    for d in draws {
      self.draw_layer(
        index,
        layer,
        shared,
        d.id,
        d.at,
        d.meshes,
        dpr,
        height_scale~,
      )
    }
  }
  self.draw_globe_atmosphere()
}

///|
/// The paint slots of one draw of mesh `m` of style layer `index`: the
/// layer's per-vertex values where it has them, else `p`'s.
fn Map::slots(
  self : Map,
  index : Int32,
  m : LayerMesh,
  p : Paint,
  zoom : Double,
) -> @render_webgl2.PaintSlots {
  let slots = @render_webgl2.PaintSlots::new()
  let color = (slot : Int32, c : @style.Color) => {
    slots.constant(slot, c.r, b=c.g, c=c.b, d=c.a)
  }
  color(@style.SLOT_COLOR, p.color)
  if self.style.layers[index].kind is Heatmap {
    slots.constant(@style.SLOT_WEIGHT, p.weight)
  } else {
    slots.constant(@style.SLOT_OPACITY, p.opacity)
  }
  slots.constant(
    @style.SLOT_SIZE,
    if m.kind == @core.KIND_CIRCLE {
      p.radius
    } else {
      p.width
    },
  )
  color(@style.SLOT_STROKE_COLOR, p.stroke_color)
  if m.kind == @core.KIND_LINE {
    slots.constant(@style.SLOT_GAP_WIDTH, p.gap_width)
    slots.constant(@style.SLOT_OFFSET, p.offset)
  } else {
    slots.constant(@style.SLOT_STROKE_OPACITY, p.stroke_opacity)
    slots.constant(@style.SLOT_STROKE_WIDTH, p.stroke_width)
  }
  // A fill's outline color is its own, or its fill color (slot by slot).
  let outline_follows = m.kind == @core.KIND_FILL &&
    self.style.layers[index].outline_color is None
  if m.vertex_paint is Some(buffer) {
    let paint = self.vertex_paint[index]
    let stride = @style.vertex_paint_words(paint) * 4
    let mut offset = 0
    for vp in paint {
      let (i, t) = vp.position(zoom)
      let single = vp.count() == 1
      slots.per_vertex(vp.slot, buffer, offset + i * 4, stride, t, single~)
      if outline_follows && vp.slot == @style.SLOT_COLOR {
        slots.per_vertex(
          @style.SLOT_STROKE_COLOR,
          buffer,
          offset + i * 4,
          stride,
          t,
          single~,
        )
      }
      offset += vp.count() * 4
    }
  }
  slots
}
