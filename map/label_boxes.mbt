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
/// Where label `i` of `s` in tile `id` lies on the grid by `at`: its anchor's grid point, its
/// perspective ratio and whether it is near enough to be placed and not behind the globe.
fn Map::grid_point(
  self : Map,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  s : LabelSet,
  i : Int32,
  height_scale : Double,
) -> (Double, Double, Double, Bool) {
  let t = self.transform
  let row = i * LABEL_FLOATS
  let (cx, cy, cw, hidden) = self.label_clip(
    at,
    id,
    f32_at(s.labels, row),
    f32_at(s.labels, row + LABEL_Y),
    s.heights[i] * height_scale,
  )
  let ratio = perspective_ratio(at, cw)
  (
    screen_x(cx, cw, t.width) + VIEWPORT_PADDING,
    screen_y(cy, cw, t.height) + VIEWPORT_PADDING,
    ratio,
    cw > 0.0 && ratio >= MIN_PERSPECTIVE_RATIO && !hidden,
  )
}
