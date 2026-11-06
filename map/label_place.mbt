///|
/// Whether labels should be placed this frame: new ones arrived, or the camera
/// moved and the last placement is `PLACEMENT_INTERVAL` old. Never without
/// symbol layers.
fn Map::placement_due(self : Map) -> Bool {
  if !self.has_labels {
    return false
  }
  if self.labels_dirty {
    return true
  }
  if self.placed_camera == Some(self.transform.camera) {
    return false
  }
  if now() - self.placed_at >= PLACEMENT_INTERVAL {
    return true
  }
  // Come back for the move that is still unplaced.
  self.request_render()
  false
}

///|
/// The tiles of `draws` in the order MapLibre places their labels (its
/// `Style._updatePlacement`): deeper tiles first, then by x and y.
fn placement_order(draws : Array[Draw]) -> Array[Draw] {
  let before = (a : Draw, b : Draw) => {
    let (p, q) = (a.id, b.id)
    p.z > q.z || (p.z == q.z && (p.x < q.x || (p.x == q.x && p.y < q.y)))
  }
  // An insertion sort: a few dozen tiles, and no sort instantiated for `Draw`.
  let out : Array[Draw] = []
  for d in draws {
    let mut k = out.length()
    while k > 0 && before(d, out[k - 1]) {
      k -= 1
    }
    out.insert(k, d)
  }
  out
}

///|
/// One symbol mesh of a tile, as placement walks it: `next` is its next label,
/// `at` and `icon_at` where its text and icons lie (moved by `*-translate`).
priv struct Pending {
  draw : Draw
  at : @render_webgl2.Placement
  icon_at : @render_webgl2.Placement
  mesh : LayerMesh
  set : LabelSet
  mut next : Int32
  order : FixedArray[Int32]
}

///|
/// Shows the labels that fit, as MapLibre's `Placement` does: symbol layers
/// from the top down, tiles in `placement_order` (labels by sort key across
/// them, if the layer has one), each in the screen grid (`place_label`).
fn Map::place_labels(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  let t = self.transform
  let grid = self.grid
  grid.reset(
    t.width + 2.0 * VIEWPORT_PADDING,
    t.height + 2.0 * VIEWPORT_PADDING,
  )
  let terrain = self.terrain_source()
  let height_scale = if terrain is Some(_) { self.terrain_scale() } else { 0.0 }
  self.placement_round += 1
  let round = self.placement_round
  let zoom = t.camera.zoom
  for k in 0..<self.style.layers.length() {
    let index = self.style.layers.length() - 1 - k
    let layer = self.style.layers[index]
    if !(layer.kind is Symbol) ||
      zoom < layer.min_zoom ||
      zoom >= layer.max_zoom {
      continue
    }
    let pending = []
    let by_y = layer.text is Some({ z_order: ViewportY, .. })
    let draws = draws_of.get(layer.source).unwrap_or([])
    for d in placement_order(draws) {
      for m in d.meshes {
        guard m.layer == index && m.labels is Some(s) && s.round != round else {
          continue
        }
        s.round = round
        if terrain is Some(src) && s.heights_at != self.dem_version {
          s.heights_at = self.dem_version
          label_heights(src, d.id, s)
          self.renderer.set_heights(
            m.mesh,
            s.labels,
            LABEL_FLOATS,
            s.heights,
            col=LABEL_LAYOUTS,
          )
          if s.icon is Some(ic) {
            self.renderer.set_heights(
              ic.mesh,
              s.labels,
              LABEL_FLOATS,
              s.heights,
              col=ICON_LAYOUTS,
            )
          }
        }
        s.cooperative = layer.text.map_or(false, t => t.cooperative)
        if s.icon is Some(ic) {
          ic.cooperative = layer.icon.map_or(false, i => i.cooperative)
        }
        // MapLibre places a `viewport-y` layer's labels from the bottom up.
        let order = if by_y {
          y_order(s, @core.radians(-t.camera.bearing))
        } else {
          []
        }
        pending.push({
          draw: d,
          at: self.translated(d.at, layer, d.id),
          icon_at: self.icon_translated(d.at, layer, d.id),
          mesh: m,
          set: s,
          next: 0,
          order,
        })
      }
    }
    let by_key = layer.text is Some(text) && text.sort_key is Some(_)
    while next_label(pending, by_key) is Some(p) {
      let i = if p.order.is_empty() {
        p.next
      } else {
        p.order[p.set.count - 1 - p.next]
      }
      p.next += 1
      // MapLibre lays labels out in tiles of the display zoom, 512 px and
      // 8192 units wide, deeper than the source's (`overscaling`).
      let deeper = @cmp.maximum(0, zoom.to_int() - p.draw.id.z)
      let unit = (1 << deeper).to_double() / 16.0
      if p.set.line is Some(l) {
        let level = @cmp.minimum(deeper, LINE_LEVELS - 1)
        let tile_px = 1.0 / t.tile_scale(p.draw.id, @core.TILE_EXTENT)
        if l.meta[i * LINE_FLOATS].to_int() == level {
          self.place_line_symbol(
            grid,
            p.at,
            p.icon_at,
            p.set,
            l,
            i,
            height_scale,
            tile_px,
            unit,
          )
        } else {
          hide_label(p.set, i)
        }
        continue
      }
      self.place_label(grid, p.at, p.icon_at, p.set, i, height_scale, unit)
    }
    let sorts = sorts_by_y(layer)
    for p in pending {
      let s = p.set
      // Labels that may overlap are drawn from the top of the screen down.
      if sorts && s.line is None {
        let angle = @core.radians(-t.camera.bearing)
        if s.sorted_at != angle {
          s.order = y_order(s, angle)
          s.sorted_at = angle
          s.changed = true
          if s.icon is Some(ic) {
            ic.changed = true
          }
        }
      }
      if s.changed {
        self.renderer.show(
          p.mesh.mesh,
          s.labels,
          LABEL_FLOATS,
          s.shown,
          s.variant,
          col=LABEL_LAYOUTS,
          order=s.order,
        )
      }
      if s.moved {
        self.renderer.set_shifts(
          p.mesh.mesh,
          s.labels,
          LABEL_FLOATS,
          s.shifts,
          col=LABEL_LAYOUTS,
        )
      }
      if s.icon is Some(ic) {
        if ic.changed {
          self.renderer.show(
            ic.mesh,
            s.labels,
            LABEL_FLOATS,
            ic.shown,
            s.variant,
            col=ICON_LAYOUTS,
            order=s.order,
          )
        }
        // With `icon-text-fit` the icon moves with its text.
        if s.moved && ic.text_fit {
          self.renderer.set_shifts(
            ic.mesh,
            s.labels,
            LABEL_FLOATS,
            s.shifts,
            col=ICON_LAYOUTS,
          )
        }
        ic.changed = false
      }
      s.changed = false
      s.moved = false
    }
  }
  self.labels_dirty = false
  self.placed_camera = Some(t.camera)
  self.placed_at = now()
}

///|
/// Whether a symbol layer's labels are drawn in screen y order (MapLibre's
/// `sortFeaturesByY`): ordered by `viewport-y`, or `auto` without a sort key, and
/// allowed to overlap.
fn sorts_by_y(layer : @style.StyleLayer) -> Bool {
  guard layer.text is Some(t) else { return false }
  let by_y = t.z_order is ViewportY || (t.z_order is Auto && t.sort_key is None)
  let overlap = t.allow_overlap ||
    t.ignore_placement ||
    (match layer.icon {
      Some(i) => i.allow_overlap || i.ignore_placement
      None => false
    })
  by_y && overlap
}

///|
/// MapLibre's `getSortedSymbolIndexes`: labels by their anchors' y on the map
/// turned by `angle` (in its 8192-unit tiles, rounded as `Math.round`), the later
/// feature first on ties.
fn y_order(s : LabelSet, angle : Double) -> FixedArray[Int32] {
  let sin = @math.sin(angle)
  let cos = @math.cos(angle)
  let at = (i : Int32, col : Int32) => f32_at(s.labels, i * LABEL_FLOATS + col)
  // Rounded y first, then the feature index backwards (below 2^24).
  let keys = Array::makei(s.count, i => {
    let y = (sin * 2.0 * at(i, LABEL_X) + cos * 2.0 * at(i, LABEL_Y) + 0.5).floor()
    y * 16777216.0 - at(i, LABEL_FEATURE)
  })
  @core.stable_order(keys[:])
}

///|
/// The mesh whose label goes next: tile by tile, or with `by_key` the lowest
/// sort key of all (each mesh's labels come sorted), the earlier tile on ties.
fn next_label(pending : Array[Pending], by_key : Bool) -> Pending? {
  let mut best : Pending? = None
  for p in pending {
    if p.next >= p.set.count {
      continue
    }
    if !by_key {
      return Some(p)
    }
    match best {
      Some(b) if label_key(b) <= label_key(p) => ()
      _ => best = Some(p)
    }
  }
  best
}

///|
fn label_key(p : Pending) -> Double {
  f32_at(p.set.labels, p.next * LABEL_FLOATS + LABEL_KEY)
}

///|
/// Places label `i` of `s` as MapLibre's `placeLayerBucketPart` does: its text box by `at` (variable
/// anchors as `attemptAnchorPlacement`, its last one first), then its icon's by `icon_at`, combined
/// by `text-optional` and `icon-optional` before either goes in the grid.
fn Map::place_label(
  self : Map,
  grid : @label.Grid,
  at : @render_webgl2.Placement,
  icon_at : @render_webgl2.Placement,
  s : LabelSet,
  i : Int32,
  height_scale : Double,
  unit : Double,
) -> Unit {
  let row = i * LABEL_FLOATS
  let (sx, sy, ratio, visible) = self.grid_point(at, s, i, height_scale)
  let (ix, iy, icon_ratio, icon_visible) = self.grid_point(
    icon_at, s, i, height_scale,
  )
  let has_text = f32_at(s.labels, row + LABEL_COUNT) > 0.0
  let icon = icon_of(s, i)
  // With `icon-text-fit` an icon that may not overlap must fit at each anchor tried.
  let fitted = match icon {
    Some(ic) if ic.text_fit && !ic.allow_overlap => true
    _ => false
  }
  let tries = s.anchors.length() / 3
  let mut shifted = false
  let mut place_text = has_text &&
    tries == 0 &&
    visible &&
    fits_box(
      grid,
      s,
      i,
      0,
      LABEL_BOX,
      s.padding,
      sx,
      sy,
      ratio,
      unit,
      0.0,
      0.0,
      s.allow_overlap,
      s.cooperative,
    )
  if has_text && tries > 0 {
    let pad = s.padding
    let x0 = snap(f32_at(s.labels, row + LABEL_BOX) - pad, unit)
    let y0 = snap(f32_at(s.labels, row + LABEL_BOX + 1) - pad, unit)
    let x1 = snap(f32_at(s.labels, row + LABEL_BOX + 2) + pad, unit)
    let y1 = snap(f32_at(s.labels, row + LABEL_BOX + 3) + pad, unit)
    let size = f32_at(s.labels, row + LABEL_SIZE)
    let mut prev = if s.shown[i] { s.anchor[i] } else { -1 }
    let mut overlap = false
    let mut cooperative = false
    let passes = (if s.allow_overlap || s.cooperative { 2 } else { 1 }) +
      (if prev >= 0 { 1 } else { 0 })
    let mut placed = -1
    for _ in 0..<passes {
      for k in 0..<tries {
        if prev >= 0 && k != prev {
          continue
        }
        let (ha, va) = @style.TextAnchor::from_code(s.anchors[k * 3].to_int()).align()
        let dx = -(ha - 0.5) * (x1 - x0) + s.anchors[k * 3 + 1] * size
        let dy = -(va - 0.5) * (y1 - y0) + s.anchors[k * 3 + 2] * size
        if fitted &&
          !(icon_visible &&
          fits_box(
            grid,
            s,
            i,
            4,
            ICON_COLUMN,
            0.0,
            ix,
            iy,
            icon_ratio,
            unit,
            dx,
            dy,
            overlap,
            cooperative,
          )) {
          continue
        }
        if visible &&
          fits_box(
            grid,
            s,
            i,
            0,
            LABEL_BOX,
            pad,
            sx,
            sy,
            ratio,
            unit,
            dx,
            dy,
            overlap,
            cooperative,
          ) {
          placed = k
          shifted = true
          if s.shifts[i * 2] != dx || s.shifts[i * 2 + 1] != dy {
            s.shifts[i * 2] = dx
            s.shifts[i * 2 + 1] = dy
            s.moved = true
          }
          let v = text_layout(s.labels, i, ha)
          if v != s.variant[i] {
            s.variant[i] = v
            s.changed = true
          }
          break
        }
      }
      if placed >= 0 {
        break
      }
      if prev >= 0 {
        prev = -1
      } else {
        overlap = s.allow_overlap
        cooperative = s.cooperative
      }
    }
    s.anchor[i] = placed
    place_text = placed >= 0
  }
  let mut place_icon = false
  if icon is Some(ic) {
    let (dx, dy) = if ic.text_fit && shifted {
      (s.shifts[i * 2], s.shifts[i * 2 + 1])
    } else {
      (0.0, 0.0)
    }
    place_icon = icon_visible &&
      fits_box(
        grid,
        s,
        i,
        4,
        ICON_COLUMN,
        0.0,
        ix,
        iy,
        icon_ratio,
        unit,
        dx,
        dy,
        ic.allow_overlap,
        ic.cooperative,
      )
    let (text, icon) = joint(ic, has_text, place_text, place_icon)
    place_text = text
    place_icon = icon
  }
  if place_text && !s.ignore_placement {
    insert_box(grid, s, i, 0, !(s.allow_overlap || s.cooperative))
  }
  if icon is Some(ic) {
    show_icon(grid, s, ic, i, place_icon, icon_visible)
  }
  let always = s.allow_overlap &&
    (match s.icon {
      Some(ic) => ic.allow_overlap || !ic.has_icons || ic.optional
      None => true
    })
  let show = has_text &&
    (place_text || (tries == 0 && always && visible && nan_box(s, i, 0)))
  if show != s.shown[i] {
    s.shown[i] = show
    s.changed = true
  }
}

///|
/// Which of label `i`'s text layouts shows at horizontal alignment `ha` (0
/// left, 0.5 center, 1 right): a multi-line label has one per justification.
fn text_layout(
  labels : @render_webgl2.JsBuffer,
  i : Int32,
  ha : Double,
) -> Int32 {
  if f32_at(labels, i * LABEL_FLOATS + LABEL_LAYOUTS) > 1.0 {
    (ha * 2.0).to_int()
  } else {
    0
  }
}

///|
/// Hides label `i` of `s`, text and icon.
fn hide_label(s : LabelSet, i : Int32) -> Unit {
  if s.shown[i] {
    s.shown[i] = false
    s.changed = true
  }
  if s.icon is Some(ic) && ic.shown[i] {
    ic.shown[i] = false
    ic.changed = true
  }
}

///|
/// Marks box `k` of label `i` as none (queries skip it); true.
fn nan_box(s : LabelSet, i : Int32, k : Int32) -> Bool {
  s.boxes[i * BOX_FLOATS + k] = @double.not_a_number
  true
}

///|
/// Looks up the terrain height under each anchor of `s`, labels of tile `id`.
fn label_heights(src : SourceTiles, id : @core.TileId, s : LabelSet) -> Unit {
  let n = (1 << id.z).to_double()
  let extent = @core.TILE_EXTENT.to_double()
  for i in 0..<s.count {
    let at = i * LABEL_FLOATS
    let m : @core.MercatorCoord = {
      x: (id.x.to_double() + f32_at(s.labels, at) / extent) / n,
      y: (id.y.to_double() + f32_at(s.labels, at + LABEL_Y) / extent) / n,
    }
    s.heights[i] = elevation_at(src, m).unwrap_or(0.0)
  }
}
