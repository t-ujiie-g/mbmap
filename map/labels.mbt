///|
/// Columns of a label's floats in a symbol entry's `labels` (docs/FORMATS.md
/// "Symbol vertices"); mirrored in worker/js/symbols.mjs.
const LABEL_X : Int32 = 0

///|
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
/// A symbol mesh's labels and their placement state as of `round`: `boxes` (text then
/// icon, CSS px), terrain `heights` (DEM version `heights_at`), the `anchor`, `variant`
/// and `shifts` each label took, and the y `order` it is drawn in when sorted.
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
  mut order : FixedArray[Int32]
  mut sorted_at : Double
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
      order: [],
      sorted_at: @double.not_a_number,
    },
  )
}
