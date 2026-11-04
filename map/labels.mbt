///|
/// `@worker.KIND_SYMBOL`, mirrored like the other kinds.
const KIND_SYMBOL : Int32 = 4

///|
/// Columns of a label's floats in a symbol entry's `labels` (docs/FORMATS.md
/// "Symbol vertices"); mirrored in worker/js/symbols.mjs.
const LABEL_Y : Int32 = 1

///|
/// The text box: min x, min y, max x, max y.
const LABEL_BOX : Int32 = 2

///|
const LABEL_FEATURE : Int32 = 6

///|
const LABEL_SIZE : Int32 = 7

///|
const LABEL_KEY : Int32 = 8

///|
/// The icon's box (four floats), then its layouts (1), first index and index
/// count. Mirrors ICON_COLUMN in worker/js/symbols.mjs.
const ICON_COLUMN : Int32 = 9

///|
const ICON_LAYOUTS : Int32 = ICON_COLUMN + 4

///|
const ICON_FIRST : Int32 = ICON_LAYOUTS + 1

///|
const ICON_COUNT : Int32 = ICON_LAYOUTS + 2

///|
/// The text's layouts, then the first index and index count of each.
const LABEL_LAYOUTS : Int32 = 16

///|
const LABEL_FIRST : Int32 = LABEL_LAYOUTS + 1

///|
const LABEL_COUNT : Int32 = LABEL_LAYOUTS + 2

///|
/// Floats per label. Mirrors LABEL_FLOATS in worker/js/symbols.mjs.
const LABEL_FLOATS : Int32 = LABEL_COUNT + 1

///|
/// Floats per label in `LabelSet::boxes`: its text box, then its icon's.
const BOX_FLOATS : Int32 = 8

///|
/// Labels below this perspective ratio (MapLibre's: 0.5 + 0.5 x the center's
/// distance over the anchor's), beyond 5 camera distances, are not placed
/// (MapLibre's `perspectiveRatioCutoff`).
const MIN_PERSPECTIVE_RATIO : Double = 0.6

///|
/// How far past the viewport labels are placed, in CSS pixels, so that they
/// change mostly offscreen (MapLibre's `viewportPadding`).
const VIEWPORT_PADDING : Double = 100.0

///|
/// How often labels are placed again while the camera moves, in milliseconds.
const PLACEMENT_INTERVAL : Double = 100.0

///|
/// A symbol mesh's labels as the worker sent them, whose text shows (`boxes`:
/// min x, min y, max x, max y in CSS px, the text's then the icon's, as of placement
/// `round`), their anchors' terrain heights in meters as of DEM version `heights_at`.
/// With variable anchors (`anchors`: code and offset x, y in ems each), `anchor` is
/// the one each label took, `variant` its layout and `shifts` its move in CSS px as
/// uploaded. Labels along lines have `line`, those with `icon-image` `icon`; `cooperative` the layer's.
priv struct LabelSet {
  labels : @render_webgl2.JsBuffer
  count : Int32
  allow_overlap : Bool
  mut cooperative : Bool
  ignore_placement : Bool
  padding : Double
  anchors : FixedArray[Double]
  line : LineSet?
  icon : IconSet?
  has_text : Bool
  shown : FixedArray[Bool]
  anchor : FixedArray[Int32]
  variant : FixedArray[Int32]
  shifts : FixedArray[Double]
  boxes : FixedArray[Double]
  heights : FixedArray[Double]
  mut heights_at : Int32
  mut round : Int32
  mut drawn : Int32
  mut changed : Bool
  mut moved : Bool
}

///|
extern "js" fn glyphs_of(msg : JsValue) -> Int32 =
  #|(m) => Array.isArray(m.glyphs) ? m.glyphs.length : 0

///|
extern "js" fn glyph_at(msg : JsValue, i : Int32) -> JsValue =
  #|(m, i) => m.glyphs[i]

///|
extern "js" fn now() -> Double =
  #|() => performance.now()

///|
extern "js" fn fonts_of(msg : JsValue) -> Int32 =
  #|(m) => Array.isArray(m.fonts) ? m.fonts.length : 0

///|
extern "js" fn font_at(msg : JsValue, i : Int32) -> String =
  #|(m, i) => String(m.fonts[i])

///|
/// A glyph key's code point bits; the bits above name its font
/// (worker/js/symbols.mjs `FONT_KEY`).
const FONT_SHIFT : Int32 = 21

///|
/// Most fonts the atlas tells apart; glyphs of others take the map's own.
const MAX_FONT_IDS : Int32 = 1023

///|
/// A worker's glyph key as the atlas's: each worker numbers its fonts (the
/// tile message's `fonts`), the map gives each its own id (0 the map's font).
fn Map::glyph_key(self : Map, key : Int32) -> Int32 {
  let f = key >> FONT_SHIFT
  if f == 0 {
    return key
  }
  let id = self.tile_fonts.get(f).unwrap_or(0)
  (id << FONT_SHIFT) | (key & ((1 << FONT_SHIFT) - 1))
}

///|
/// Adds the glyphs a worker drew for the first time to the atlas, after
/// numbering the fonts the tile message names.
fn Map::take_glyphs(self : Map, msg : JsValue) -> Unit {
  self.tile_fonts.clear()
  for i in 0..<fonts_of(msg) {
    let name = font_at(msg, i)
    let id = match self.fonts.get(name) {
      Some(id) => id
      None if name == "" || self.fonts.length() >= MAX_FONT_IDS => 0
      None => {
        self.fonts[name] = self.fonts.length() + 1
        self.fonts.length()
      }
    }
    self.tile_fonts.push(id)
  }
  for i in 0..<glyphs_of(msg) {
    let g = glyph_at(msg, i)
    let cp = self.glyph_key(get_int(g, "cp"))
    let w = get_int(g, "width")
    let h = get_int(g, "height")
    match self.atlas.place(cp, w, h) {
      Some((x, y)) =>
        self.renderer.upload_glyph(buffer_of(g, "data"), x, y, w, h)
      None =>
        if self.atlas.rect(cp) is None && !self.atlas_full {
          self.atlas_full = true
          console_warn("the glyph atlas is full; some labels miss characters")
        }
    }
  }
}

///|
/// Uploads a symbol entry and its labels, none shown yet.
fn Map::symbol_mesh(self : Map, l : JsValue) -> (@render_webgl2.Mesh, LabelSet) {
  let codepoints = buffer_of(l, "codepoints")
  let rects = FixedArray::make(length_of(codepoints) * 4, 0)
  for i in 0..<length_of(codepoints) {
    if self.atlas.rect(self.glyph_key(u32_at(codepoints, i)))
      is Some((x, y, w, h)) {
      rects[i * 4] = x
      rects[i * 4 + 1] = y
      rects[i * 4 + 2] = w
      rects[i * 4 + 3] = h
    }
  }
  let mesh = self.renderer.upload_symbols(
    buffer_of(l, "vertices"),
    buffer_of(l, "indices"),
    get_int(l, "indexBytes"),
    rects,
    colors=buffer_of(l, "colors"),
  )
  let labels = buffer_of(l, "labels")
  let count = length_of(labels) / LABEL_FLOATS
  let anchors = buffer_of(l, "anchors")
  self.labels_dirty = true
  (
    mesh,
    {
      labels,
      count,
      allow_overlap: get_bool(l, "allowOverlap"),
      cooperative: false,
      ignore_placement: get_bool(l, "ignorePlacement"),
      padding: get_double(l, "padding"),
      anchors: FixedArray::makei(length_of(anchors), i => f32_at(anchors, i)),
      line: line_set(l, get_int(l, "count") / QUAD_INDICES),
      icon: self.icon_set(l, count),
      has_text: get_int(l, "count") > 0,
      shown: FixedArray::make(count, false),
      anchor: FixedArray::make(count, -1),
      variant: FixedArray::make(count, 0),
      shifts: FixedArray::make(count * 2, 0.0),
      boxes: FixedArray::make(count * BOX_FLOATS, 0.0),
      heights: FixedArray::make(count, 0.0),
      heights_at: 0,
      round: -1,
      drawn: -1,
      changed: false,
      moved: false,
    },
  )
}

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
        pending.push({
          draw: d,
          at: self.translated(d.at, layer, d.id),
          icon_at: self.icon_translated(d.at, layer, d.id),
          mesh: m,
          set: s,
          next: 0,
        })
      }
    }
    let by_key = layer.text is Some(text) && text.sort_key is Some(_)
    while next_label(pending, by_key) is Some(p) {
      let i = p.next
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
    for p in pending {
      let s = p.set
      if s.changed {
        self.renderer.show(
          p.mesh.mesh,
          s.labels,
          LABEL_FLOATS,
          s.shown,
          s.variant,
          col=LABEL_LAYOUTS,
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
/// Indices per glyph or icon quad (two triangles); mirrored in
/// worker/js/symbols.mjs.
const QUAD_INDICES : Int32 = 6

///|
/// Float `at` of `labels`, an index count or first index, in quads.
fn quad_at(labels : @render_webgl2.JsBuffer, at : Int32) -> Int32 {
  (f32_at(labels, at) / QUAD_INDICES.to_double()).to_int()
}

///|
/// MapLibre's perspective ratio of a label whose anchor has clip w `cw`: 0.5 +
/// 0.5 x the center's distance over the anchor's.
fn perspective_ratio(at : @render_webgl2.Placement, cw : Double) -> Double {
  0.5 + 0.5 * at.center_depth / cw
}

///|
/// The CSS px x of clip x `cx`, w `cw` on a screen `width` wide.
fn screen_x(cx : Double, cw : Double, width : Double) -> Double {
  (cx / cw + 1.0) * 0.5 * width
}

///|
/// The CSS px y of clip y `cy`, w `cw` on a screen `height` high.
fn screen_y(cy : Double, cw : Double, height : Double) -> Double {
  (1.0 - cy / cw) * 0.5 * height
}

///|
/// `v` CSS px in whole units of MapLibre's tile, `unit` CSS px each: it keeps
/// collision boxes as Int16 (`CollisionBox`).
fn snap(v : Double, unit : Double) -> Double {
  (v / unit).to_int().to_double() * unit
}

///|
/// Whether box `k` of label `i` (0 its text's, padded by `pad`; 4 its icon's, from floats `col` on)
/// fits the grid at grid point (sx, sy), scaled by `ratio` and moved by (dx, dy) CSS px, unless it may
/// `overlap` (`cooperative`: meeting only symbols that may); recorded in `s.boxes` if so.
fn fits_box(
  grid : @label.Grid,
  s : LabelSet,
  i : Int32,
  k : Int32,
  col : Int32,
  pad : Double,
  sx : Double,
  sy : Double,
  ratio : Double,
  unit : Double,
  dx : Double,
  dy : Double,
  overlap : Bool,
  cooperative : Bool,
) -> Bool {
  let at = i * LABEL_FLOATS + col
  let bx0 = sx + (snap(f32_at(s.labels, at) - pad, unit) + dx) * ratio
  let by0 = sy + (snap(f32_at(s.labels, at + 1) - pad, unit) + dy) * ratio
  let bx1 = sx + (snap(f32_at(s.labels, at + 2) + pad, unit) + dx) * ratio
  let by1 = sy + (snap(f32_at(s.labels, at + 3) + pad, unit) + dy) * ratio
  guard grid.inside(bx0, by0, bx1, by1) &&
    (overlap || !grid.hits(bx0, by0, bx1, by1, cooperative~)) else {
    return false
  }
  let b = i * BOX_FLOATS + k
  s.boxes[b] = bx0 - VIEWPORT_PADDING
  s.boxes[b + 1] = by0 - VIEWPORT_PADDING
  s.boxes[b + 2] = bx1 - VIEWPORT_PADDING
  s.boxes[b + 3] = by1 - VIEWPORT_PADDING
  true
}

///|
/// Puts box `k` of label `i` (0 its text's, 4 its icon's) in the grid as
/// recorded in `s.boxes`, of a symbol that `never` overlaps others or not.
fn insert_box(
  grid : @label.Grid,
  s : LabelSet,
  i : Int32,
  k : Int32,
  never : Bool,
) -> Unit {
  let b = i * BOX_FLOATS + k
  grid.insert(
    s.boxes[b] + VIEWPORT_PADDING,
    s.boxes[b + 1] + VIEWPORT_PADDING,
    s.boxes[b + 2] + VIEWPORT_PADDING,
    s.boxes[b + 3] + VIEWPORT_PADDING,
    never~,
  )
}

///|
/// Where label `i` of `s` lies on the grid by `at`: its anchor's grid point, its
/// perspective ratio and whether it is near enough to be placed.
fn Map::grid_point(
  self : Map,
  at : @render_webgl2.Placement,
  s : LabelSet,
  i : Int32,
  height_scale : Double,
) -> (Double, Double, Double, Bool) {
  let t = self.transform
  let row = i * LABEL_FLOATS
  let (cx, cy, _, cw) = at.matrix.apply(
    f32_at(s.labels, row),
    f32_at(s.labels, row + LABEL_Y),
    s.heights[i] * height_scale,
    1.0,
  )
  let ratio = perspective_ratio(at, cw)
  (
    screen_x(cx, cw, t.width) + VIEWPORT_PADDING,
    screen_y(cy, cw, t.height) + VIEWPORT_PADDING,
    ratio,
    cw > 0.0 && ratio >= MIN_PERSPECTIVE_RATIO,
  )
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
/// The labels shown at the last placement, for tests, a line each: layer id, tile z, x, y, feature, anchor
/// x, y (8192 units), variable anchor code (or -1), text and icon shown (1, 0), the text's layout (0-2: left,
/// center, right; -1 with one), their boxes (CSS px) and, along lines, each glyph's screen x:y:angle.
pub fn Map::placed_labels(self : Map) -> String {
  let out = StringBuilder()
  for _, draws in self.drawn {
    for d in draws {
      for m in d.meshes {
        guard m.labels is Some(s) && s.round == self.placement_round else {
          continue
        }
        for i in 0..<s.count {
          let icon = match s.icon {
            Some(ic) => ic.shown[i]
            None => false
          }
          guard s.shown[i] || icon else { continue }
          let row = i * LABEL_FLOATS
          let code = if s.anchor[i] >= 0 {
            s.anchors[s.anchor[i] * 3].to_int()
          } else {
            -1
          }
          let b = s.boxes
          out.write_string(
            "\{self.style.layers[m.layer].id},\{d.id.z},\{d.id.x},\{d.id.y},\{f32_at(s.labels, row + LABEL_FEATURE).to_int()},",
          )
          let ax = (f32_at(s.labels, row) * 2.0).to_int()
          let ay = (f32_at(s.labels, row + LABEL_Y) * 2.0).to_int()
          let flag = (v : Bool) => if v { 1 } else { 0 }
          let layout = if s.shown[i] &&
            f32_at(s.labels, row + LABEL_LAYOUTS) > 1.0 {
            s.variant[i]
          } else {
            -1
          }
          out.write_string(
            "\{ax},\{ay},\{code},\{flag(s.shown[i])},\{flag(icon)},\{layout}",
          )
          for k in 0..<BOX_FLOATS {
            out.write_string(",\{b[i * BOX_FLOATS + k]}")
          }
          // Along lines, each glyph's place on screen and angle.
          if s.line is Some(l) {
            let q0 = quad_at(s.labels, row + LABEL_FIRST)
            let n = quad_at(s.labels, row + LABEL_COUNT)
            out.write_string(",")
            for k in 0..<n {
              let g = (q0 + k) * 3
              let (cx, cy, _, cw) = d.at.matrix.apply(
                l.glyphs[g],
                l.glyphs[g + 1],
                0.0,
                1.0,
              )
              let sx = screen_x(cx, cw, self.transform.width)
              let sy = screen_y(cy, cw, self.transform.height)
              out.write_string("\{sx}:\{sy}:\{l.glyphs[g + 2]} ")
            }
          }
          out.write_string("\n")
        }
      }
    }
  }
  out.to_string()
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
