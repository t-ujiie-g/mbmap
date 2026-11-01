///|
/// `@worker.KIND_SYMBOL`, mirrored like the other kinds.
const KIND_SYMBOL : Int32 = 4

///|
/// Floats per label in a symbol entry's `labels`: anchor x, y, box, first index
/// and index count. Mirrors LABEL_FLOATS in worker/js/symbols.mjs.
const LABEL_FLOATS : Int32 = 8

///|
/// Labels whose perspective ratio (MapLibre's: 0.5 + 0.5 x the center's
/// distance over the anchor's, the factor their size is scaled by) falls below
/// this are not placed: those beyond 5 camera distances (MapLibre's
/// `perspectiveRatioCutoff`).
const MIN_PERSPECTIVE_RATIO : Double = 0.6

///|
/// How often labels are placed again while the camera moves, in milliseconds.
const PLACEMENT_INTERVAL : Double = 100.0

///|
/// A symbol mesh's labels as the worker sent them, which of them show, and
/// their anchors' terrain heights in meters as of DEM version `heights_at`.
priv struct LabelSet {
  labels : @render_webgl2.JsBuffer
  count : Int32
  allow_overlap : Bool
  ignore_placement : Bool
  padding : Double
  shown : FixedArray[Bool]
  heights : FixedArray[Double]
  mut heights_at : Int32
  mut round : Int32
  mut drawn : Int32
}

///|
extern "js" fn f32_at(buffer : @render_webgl2.JsBuffer, i : Int32) -> Double =
  #|(b, i) => b[i]

///|
extern "js" fn length_of(buffer : @render_webgl2.JsBuffer) -> Int32 =
  #|(b) => b.length

///|
extern "js" fn u32_at(buffer : @render_webgl2.JsBuffer, i : Int32) -> Int32 =
  #|(b, i) => b[i] | 0

///|
extern "js" fn get_bool(v : JsValue, key : String) -> Bool =
  #|(v, k) => v[k] === true

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
/// Adds the glyphs a worker drew for the first time to the atlas.
fn Map::take_glyphs(self : Map, msg : JsValue) -> Unit {
  for i in 0..<glyphs_of(msg) {
    let g = glyph_at(msg, i)
    let cp = get_int(g, "cp")
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
    if self.atlas.rect(u32_at(codepoints, i)) is Some((x, y, w, h)) {
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
  )
  let labels = buffer_of(l, "labels")
  let count = length_of(labels) / LABEL_FLOATS
  self.labels_dirty = true
  (
    mesh,
    {
      labels,
      count,
      allow_overlap: get_bool(l, "allowOverlap"),
      ignore_placement: get_bool(l, "ignorePlacement"),
      padding: get_double(l, "padding"),
      shown: FixedArray::make(count, false),
      heights: FixedArray::make(count, 0.0),
      heights_at: 0,
      round: -1,
      drawn: -1,
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
/// Shows the labels that fit: symbol layers from the top of the style down,
/// tiles nearest the center first, each label in the screen grid unless it
/// may overlap or be overlapped.
fn Map::place_labels(
  self : Map,
  draws_of : @hashmap.HashMap[String, Array[Draw]],
) -> Unit {
  let t = self.transform
  let (w, h) = (t.width, t.height)
  let grid = @label.Grid::new(w, h)
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
    for d in draws_of.get(layer.source).unwrap_or([]) {
      for m in d.meshes {
        guard m.layer == index && m.labels is Some(s) && s.round != round else {
          continue
        }
        s.round = round
        if terrain is Some(src) && s.heights_at != self.dem_version {
          s.heights_at = self.dem_version
          label_heights(src, d.id, s)
          self.renderer.set_heights(m.mesh, s.labels, LABEL_FLOATS, s.heights)
        }
        let mut changed = false
        for i in 0..<s.count {
          let at = i * LABEL_FLOATS
          let ax = f32_at(s.labels, at)
          let ay = f32_at(s.labels, at + 1)
          let (cx, cy, _, cw) = d.at.matrix.apply(
            ax,
            ay,
            s.heights[i] * height_scale,
            1.0,
          )
          let ratio = 0.5 + 0.5 * d.at.center_depth / cw
          let mut show = false
          if cw > 0.0 && ratio >= MIN_PERSPECTIVE_RATIO {
            let sx = (cx / cw + 1.0) * 0.5 * w
            let sy = (1.0 - cy / cw) * 0.5 * h
            let pad = s.padding
            let x0 = sx + f32_at(s.labels, at + 2) * ratio - pad
            let y0 = sy + f32_at(s.labels, at + 3) * ratio - pad
            let x1 = sx + f32_at(s.labels, at + 4) * ratio + pad
            let y1 = sy + f32_at(s.labels, at + 5) * ratio + pad
            if x1 > 0.0 &&
              y1 > 0.0 &&
              x0 < w &&
              y0 < h &&
              (s.allow_overlap || !grid.hits(x0, y0, x1, y1)) {
              show = true
              if !s.ignore_placement {
                grid.insert(x0, y0, x1, y1)
              }
            }
          }
          if show != s.shown[i] {
            s.shown[i] = show
            changed = true
          }
        }
        if changed {
          self.renderer.show(m.mesh, s.labels, LABEL_FLOATS, s.shown)
        }
      }
    }
  }
  self.labels_dirty = false
  self.placed_camera = Some(t.camera)
  self.placed_at = now()
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
      y: (id.y.to_double() + f32_at(s.labels, at + 1) / extent) / n,
    }
    s.heights[i] = elevation_at(src, m).unwrap_or(0.0)
  }
}
