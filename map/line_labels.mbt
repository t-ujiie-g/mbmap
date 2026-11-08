///|
/// Floats per label in a symbol entry's `lineLabels`: overscaling level, anchor
/// segment, first point and point count of its line in `lines`, first glyph in
/// `glyphOffsets`, collision circle diameter (px). Mirrors LINE_FLOATS in worker/js/symbols.mjs.
const LINE_FLOATS : Int32 = 6

///|
/// How many overscaling levels the worker finds labels along lines for (1, 2, 4
/// times the source's tile zoom); mirrors LINE_LEVELS in worker/js/symbols.mjs.
const LINE_LEVELS : Int32 = 3

///|
/// A glyph x below this hides the glyph (`Renderer::set_glyphs`).
const HIDDEN_GLYPH : Double = -1.0e9

///|
/// MapLibre's `ONE_EM`: glyph units per em, as `glyphOffsets` count them.
const ONE_EM : Double = 24.0

///|
/// How far past the viewport, in CSS px, an anchor may lie and still have its
/// glyphs laid (MapLibre's 256 px clipping buffer in `updateLineLabels`).
const CLIP_BUFFER_PX : Double = 256.0

///|
/// The labels along lines of a symbol mesh: `meta` (`LINE_FLOATS` per label), `lines` (x, y in tile
/// units), glyph `offsets` along them (`ONE_EM` an em) and `glyphs` (x, y, angle) laid out for camera
/// `laid` at round `laid_round`; `LineSet::along` leaves its point in `at_x`, `at_y`, `at_angle`.
priv struct LineSet {
  meta : FixedArray[Double]
  lines : FixedArray[Double]
  offsets : FixedArray[Double]
  keep_upright : Bool
  glyphs : FixedArray[Double]
  mut laid : @core.Camera?
  mut laid_round : Int32
  mut at_x : Double
  mut at_y : Double
  mut at_angle : Double
}

///|
/// The labels along lines of a symbol entry `l`, if it has them.
fn line_set(l : JsValue, quads : Int32) -> LineSet? {
  guard has(l, "lineLabels") else { return None }
  let copy = (key : String) => {
    let b = buffer_of(l, key)
    FixedArray::makei(length_of(b), i => f32_at(b, i))
  }
  Some({
    meta: copy("lineLabels"),
    lines: copy("lines"),
    offsets: copy("glyphOffsets"),
    keep_upright: get_bool(l, "keepUpright"),
    glyphs: FixedArray::make(quads * 3, HIDDEN_GLYPH),
    laid: None,
    laid_round: -1,
    at_x: 0.0,
    at_y: 0.0,
    at_angle: 0.0,
  })
}

///|
/// MapLibre's `placeGlyphAlongLine` in tile units: the point `offset` along label `i`'s line from its
/// anchor (x, y), backwards with `flip`, and the angle there, left in `at_x`, `at_y`, `at_angle`;
/// `path` gets the points walked past. False past the line's end.
fn LineSet::along(
  self : LineSet,
  i : Int32,
  x : Double,
  y : Double,
  offset : Double,
  flip : Bool,
  path : Array[Double]?,
) -> Bool {
  let m = i * LINE_FLOATS
  let start = self.meta[m + 2].to_int()
  let end = start + self.meta[m + 3].to_int()
  let mut dir = if offset > 0.0 { 1 } else { -1 }
  let mut angle = 0.0
  if flip {
    dir = -dir
    angle = @math.PI
  }
  if dir < 0 {
    angle += @math.PI
  }
  let mut index = start +
    self.meta[m + 1].to_int() +
    (if dir > 0 { 0 } else { 1 })
  let mut cx = x
  let mut cy = y
  let mut px = x
  let mut py = y
  let mut walked = 0.0
  let mut segment = 0.0
  let goal = offset.abs()
  while walked + segment <= goal {
    index += dir
    if index < start || index >= end {
      return false
    }
    walked += segment
    px = cx
    py = cy
    cx = self.lines[index * 2]
    cy = self.lines[index * 2 + 1]
    if path is Some(p) {
      p.push(px)
      p.push(py)
    }
    segment = ((cx - px) * (cx - px) + (cy - py) * (cy - py)).sqrt()
  }
  let t = (goal - walked) / segment
  let gx = (cx - px) * t + px
  let gy = (cy - py) * t + py
  if path is Some(p) {
    p.push(gx)
    p.push(gy)
  }
  self.at_x = gx
  self.at_y = gy
  self.at_angle = angle + @math.atan2(cy - py, cx - px)
  true
}

///|
/// The normalized device x of point (x, y) at height `z` of tile `id` at `at`.
fn Map::ndc_x(
  self : Map,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  x : Double,
  y : Double,
  z : Double,
) -> Double {
  let (ex, _, ew, _) = self.label_clip(at, id, x, y, z)
  ex / ew
}

///|
/// Whether the line of label `i` of `l` runs right to left on screen at its
/// anchor (x, y) at height `z`: the anchor lies right of the line's next point.
fn Map::backwards(
  self : Map,
  l : LineSet,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  i : Int32,
  x : Double,
  y : Double,
  z : Double,
) -> Bool {
  let m = i * LINE_FLOATS
  let v = l.meta[m + 2].to_int() + l.meta[m + 1].to_int() + 1
  self.ndc_x(at, id, x, y, z) >
  self.ndc_x(at, id, l.lines[v * 2], l.lines[v * 2 + 1], z)
}

///|
/// Hides glyph quads `q0..<q0 + n` of `glyphs`.
fn hide_glyphs(glyphs : FixedArray[Double], q0 : Int32, n : Int32) -> Unit {
  for k in 0..<n {
    glyphs[(q0 + k) * 3] = HIDDEN_GLYPH
  }
}

///|
/// Appends the screen point (CSS px) of point `k` of `points` (tile `id`'s units)
/// at height `z` to `path`, its clip w to `depths` and whether the globe hides it
/// to `hidden`.
fn Map::push_screen(
  self : Map,
  path : Array[Double],
  depths : Array[Double],
  hidden : Array[Bool],
  at : @render_webgl2.Placement,
  id : @core.TileId,
  points : Array[Double],
  k : Int32,
  z : Double,
) -> Unit {
  let t = self.transform
  let (cx, cy, pw, behind) = self.label_clip(
    at,
    id,
    points[k * 2],
    points[k * 2 + 1],
    z,
  )
  path.push(screen_x(cx, pw, t.width))
  path.push(screen_y(cy, pw, t.height))
  depths.push(pw)
  hidden.push(behind)
}

///|
/// The longest run of `path`'s points (x, y pairs) the globe does not hide, as
/// MapLibre's `pathSlicedToLongestUnoccluded`; false if one of them lies behind
/// the camera (by its clip w in `depths`).
fn longest_unhidden(
  path : Array[Double],
  depths : Array[Double],
  hidden : Array[Bool],
) -> (Array[Double], Bool) {
  let mut start = 0
  let mut length = 0
  let mut run_start = 0
  let mut run = 0
  for k, h in hidden {
    if h {
      run_start = k + 1
      run = 0
    } else {
      run += 1
      if run > length {
        length = run
        start = run_start
      }
    }
  }
  let mut ahead = true
  for k in start..<(start + length) {
    ahead = ahead && depths[k] > 0.0
  }
  (path[start * 2:(start + length) * 2].to_owned(), ahead)
}

///|
/// MapLibre's `clipLine` of one path (x, y pairs): its parts inside the box,
/// new end points rounded.
fn clip_path(
  path : Array[Double],
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Array[Array[Double]] {
  let out : Array[Array[Double]] = []
  let mut part : Array[Double] = []
  for i = 0; i + 1 < path.length() / 2; i = i + 1 {
    let mut ax = path[i * 2]
    let mut ay = path[i * 2 + 1]
    let mut bx = path[i * 2 + 2]
    let mut by = path[i * 2 + 3]
    let cut = (v : Double) => v.round()
    if ax < x1 && bx < x1 {
      continue
    } else if ax < x1 {
      ay = cut(ay + (by - ay) * ((x1 - ax) / (bx - ax)))
      ax = x1
    } else if bx < x1 {
      by = cut(ay + (by - ay) * ((x1 - ax) / (bx - ax)))
      bx = x1
    }
    if ay < y1 && by < y1 {
      continue
    } else if ay < y1 {
      ax = cut(ax + (bx - ax) * ((y1 - ay) / (by - ay)))
      ay = y1
    } else if by < y1 {
      bx = cut(ax + (bx - ax) * ((y1 - ay) / (by - ay)))
      by = y1
    }
    if ax >= x2 && bx >= x2 {
      continue
    } else if ax >= x2 {
      ay = cut(ay + (by - ay) * ((x2 - ax) / (bx - ax)))
      ax = x2
    } else if bx >= x2 {
      by = cut(ay + (by - ay) * ((x2 - ax) / (bx - ax)))
      bx = x2
    }
    if ay >= y2 && by >= y2 {
      continue
    } else if ay >= y2 {
      ax = cut(ax + (bx - ax) * ((y2 - ay) / (by - ay)))
      ay = y2
    } else if by >= y2 {
      bx = cut(ax + (bx - ax) * ((y2 - ay) / (by - ay)))
      by = y2
    }
    let n = part.length()
    if n == 0 || ax != part[n - 2] || ay != part[n - 1] {
      part = [ax, ay]
      out.push(part)
    }
    part.push(bx)
    part.push(by)
  }
  out
}

///|
/// Circles along `path` (screen px, x, y pairs) as MapLibre's
/// `placeCollisionCircles` spaces them (its `PathInterpolator`): x, y, radius each.
fn circles_along(
  path : Array[Double],
  radius : Double,
  out : Array[Double],
) -> Unit {
  let n = path.length() / 2
  let dist = FixedArray::make(n, 0.0)
  for k in 1..<n {
    let dx = path[k * 2] - path[k * 2 - 2]
    let dy = path[k * 2 + 1] - path[k * 2 - 1]
    dist[k] = dist[k - 1] + (dx * dx + dy * dy).sqrt()
  }
  let length = dist[n - 1]
  let padding = @cmp.minimum(radius * 0.25, length * 0.5)
  let padded = length - padding * 2.0
  let count = if length <= 0.5 * radius {
    1
  } else {
    (padded / (radius * 2.5)).ceil().to_int() + 1
  }
  for c in 0..<count {
    let t = c.to_double() / @cmp.maximum(count - 1, 1).to_double()
    if n == 1 {
      out.push(path[0])
      out.push(path[1])
    } else {
      let goal = t * padded + padding
      let mut k = 1
      while k < n - 1 && dist[k] < goal {
        k += 1
      }
      let span = dist[k] - dist[k - 1]
      let s = if span > 0.0 { (goal - dist[k - 1]) / span } else { 0.0 }
      out.push(path[k * 2 - 2] * (1.0 - s) + path[k * 2] * s)
      out.push(path[k * 2 - 1] * (1.0 - s) + path[k * 2 + 1] * s)
    }
    out.push(radius)
  }
}

///|
/// Places the text of label `i` of `s` along its line as MapLibre's
/// `placeCollisionCircles`: `circles` (x, y, radius in grid px) over the path from
/// its first glyph to its last, which must meet nothing placed unless it may overlap.
fn Map::place_line_label(
  self : Map,
  grid : @label.Grid,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  s : LabelSet,
  l : LineSet,
  i : Int32,
  height_scale : Double,
  tile_px : Double,
  circles : Array[Double],
) -> Bool {
  let t = self.transform
  let (w, h) = (t.width, t.height)
  let row = i * LABEL_FLOATS
  let (x, y) = (f32_at(s.labels, row), f32_at(s.labels, row + LABEL_Y))
  let z = s.heights[i] * height_scale
  let (_, _, cw, _) = self.label_clip(at, id, x, y, z)
  let ratio = perspective_ratio(at, cw)
  let m = i * LINE_FLOATS
  let first = l.meta[m + 4].to_int()
  let glyphs = quad_at(s.labels, row + LABEL_COUNT)
  let scale = f32_at(s.labels, row + LABEL_SIZE) *
    self.text_correction(id, y) /
    ratio /
    ONE_EM *
    tile_px
  let (head, tail) = ([], [])
  let mut collided = false
  let mut in_grid = false
  if cw > 0.0 &&
    l.along(i, x, y, l.offsets[first] * scale, false, Some(head)) &&
    l.along(i, x, y, l.offsets[first + glyphs - 1] * scale, false, Some(tail)) {
    // From the first glyph back past the anchor's vertices to the last.
    let (path, depths, hidden) = ([], [], [])
    for k = head.length() / 2 - 1; k >= 1; k = k - 1 {
      self.push_screen(path, depths, hidden, at, id, head, k, z)
    }
    for k in 1..<(tail.length() / 2) {
      self.push_screen(path, depths, hidden, at, id, tail, k, z)
    }
    let (path, ahead) = longest_unhidden(path, depths, hidden)
    let radius = l.meta[m + 5] * 0.5 * ratio + s.padding
    let (lo_x, lo_y) = (-VIEWPORT_PADDING, -VIEWPORT_PADDING)
    let (hi_x, hi_y) = (w + VIEWPORT_PADDING, h + VIEWPORT_PADDING)
    let parts = if !ahead || path.is_empty() {
      []
    } else {
      let mut x0 = path[0]
      let mut y0 = path[1]
      let mut x1 = path[0]
      let mut y1 = path[1]
      for k in 1..<(path.length() / 2) {
        x0 = @cmp.minimum(x0, path[k * 2])
        y0 = @cmp.minimum(y0, path[k * 2 + 1])
        x1 = @cmp.maximum(x1, path[k * 2])
        y1 = @cmp.maximum(y1, path[k * 2 + 1])
      }
      if x0 >= lo_x && x1 <= hi_x && y0 >= lo_y && y1 <= hi_y {
        [path]
      } else if x1 < lo_x || x0 > hi_x || y1 < lo_y || y0 > hi_y {
        []
      } else {
        clip_path(path, lo_x, lo_y, hi_x, hi_y)
      }
    }
    for part in parts {
      circles_along(part, radius, circles)
    }
    for k = 0; k < circles.length(); k = k + 3 {
      let (cx, cy) = (
        circles[k] + VIEWPORT_PADDING,
        circles[k + 1] + VIEWPORT_PADDING,
      )
      circles[k] = cx
      circles[k + 1] = cy
      in_grid = in_grid ||
        grid.inside(cx - radius, cy - radius, cx + radius, cy + radius)
      if !s.allow_overlap &&
        grid.hits_circle(cx, cy, radius, cooperative=s.cooperative) {
        collided = true
        break
      }
    }
  }
  if collided || !in_grid || ratio < MIN_PERSPECTIVE_RATIO {
    circles.clear()
  }
  s.allow_overlap || (!circles.is_empty() && !collided)
}

///|
/// Places label `i` of `s` along its line: its text by its circles, then its
/// icon's box laid on the map (`fits_on_map`, by `icon_at`), shown jointly as on
/// points.
fn Map::place_line_symbol(
  self : Map,
  grid : @label.Grid,
  at : @render_webgl2.Placement,
  icon_at : @render_webgl2.Placement,
  id : @core.TileId,
  s : LabelSet,
  l : LineSet,
  i : Int32,
  height_scale : Double,
  tile_px : Double,
  unit : Double,
) -> Unit {
  let row = i * LABEL_FLOATS
  let has_text = f32_at(s.labels, row + LABEL_COUNT) > 0.0
  let z = s.heights[i] * height_scale
  let (_, _, cw, _) = self.label_clip(
    at,
    id,
    f32_at(s.labels, row),
    f32_at(s.labels, row + LABEL_Y),
    z,
  )
  let mut visible = cw > 0.0 &&
    perspective_ratio(at, cw) >= MIN_PERSPECTIVE_RATIO
  let circles = []
  let mut place_text = has_text &&
    self.place_line_label(grid, at, id, s, l, i, height_scale, tile_px, circles)
  let icon = icon_of(s, i)
  let mut place_icon = false
  if icon is Some(ic) {
    // An icon whose box the globe hides entirely is not shown, even if it may overlap.
    let (fits, hidden) = if visible {
      self.fits_on_map(grid, icon_at, id, s, i, z, tile_px, unit, ic)
    } else {
      (false, false)
    }
    place_icon = fits
    visible = visible && !hidden
    let (text, icon) = joint(ic, has_text, place_text, place_icon)
    place_text = text
    place_icon = icon
  }
  // Queries find the text by its circles' bounds.
  let b = s.boxes
  let o = i * BOX_FLOATS
  b[o] = @double.not_a_number
  if place_text && !circles.is_empty() {
    b[o] = @double.infinity
    b[o + 1] = @double.infinity
    b[o + 2] = @double.neg_infinity
    b[o + 3] = @double.neg_infinity
    for k = 0; k < circles.length(); k = k + 3 {
      let (cx, cy, r) = (circles[k], circles[k + 1], circles[k + 2])
      if !s.ignore_placement {
        grid.insert_circle(cx, cy, r, never=!(s.allow_overlap || s.cooperative))
      }
      b[o] = @cmp.minimum(b[o], cx - r - VIEWPORT_PADDING)
      b[o + 1] = @cmp.minimum(b[o + 1], cy - r - VIEWPORT_PADDING)
      b[o + 2] = @cmp.maximum(b[o + 2], cx + r - VIEWPORT_PADDING)
      b[o + 3] = @cmp.maximum(b[o + 3], cy + r - VIEWPORT_PADDING)
    }
  }
  if icon is Some(ic) {
    show_icon(grid, s, ic, i, place_icon, visible)
  }
  let show = has_text && place_text
  if show != s.shown[i] {
    s.shown[i] = show
    s.changed = true
  }
}

///|
/// Whether label `i`'s icon box fits the grid laid on the map at its anchor (z its height) as
/// MapLibre's `_projectCollisionBox` lays boxes of text pitched and turned with the map, recorded in
/// `s.boxes` if so; and whether the globe hides all of it.
fn Map::fits_on_map(
  self : Map,
  grid : @label.Grid,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  s : LabelSet,
  i : Int32,
  z : Double,
  tile_px : Double,
  unit : Double,
  ic : IconSet,
) -> (Bool, Bool) {
  let t = self.transform
  let row = i * LABEL_FLOATS
  let (x, y) = (f32_at(s.labels, row), f32_at(s.labels, row + LABEL_Y))
  let (_, _, cw, _) = self.label_clip(at, id, x, y, z)
  // Tile units per CSS px of the box, which grows with distance as the text does.
  let k = @cmp.minimum(@cmp.maximum(0.5 + 0.5 * cw / at.center_depth, 0.0), 4.0) *
    tile_px *
    self.text_correction(id, y)
  let box = row + ICON_COLUMN
  let left = snap(f32_at(s.labels, box), unit) * k
  let top = snap(f32_at(s.labels, box + 1), unit) * k
  let right = snap(f32_at(s.labels, box + 2), unit) * k
  let bottom = snap(f32_at(s.labels, box + 3), unit) * k
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  let mut seen = false
  for a in 0..<3 {
    for c in 0..<3 {
      guard a != 1 || c != 1 else { continue }
      let (px, py, pw, hidden) = self.label_clip(
        at,
        id,
        x + third(a, left, right),
        y + third(c, top, bottom),
        z,
      )
      seen = seen || !hidden
      let sx = screen_x(px, pw, t.width) + VIEWPORT_PADDING
      let sy = screen_y(py, pw, t.height) + VIEWPORT_PADDING
      x0 = @cmp.minimum(x0, sx)
      y0 = @cmp.minimum(y0, sy)
      x1 = @cmp.maximum(x1, sx)
      y1 = @cmp.maximum(y1, sy)
    }
  }
  guard seen &&
    grid.inside(x0, y0, x1, y1) &&
    (ic.allow_overlap || !grid.hits(x0, y0, x1, y1, cooperative=ic.cooperative)) else {
    return (false, !seen)
  }
  let b = i * BOX_FLOATS + 4
  s.boxes[b] = x0 - VIEWPORT_PADDING
  s.boxes[b + 1] = y0 - VIEWPORT_PADDING
  s.boxes[b + 2] = x1 - VIEWPORT_PADDING
  s.boxes[b + 3] = y1 - VIEWPORT_PADDING
  (true, false)
}

///|
/// `lo`, the middle of `lo` and `hi`, or `hi` for `k` 0, 1 or 2.
fn third(k : Int32, lo : Double, hi : Double) -> Double {
  match k {
    0 => lo
    1 => (lo + hi) / 2.0
    _ => hi
  }
}

///|
/// Lays the glyphs of the shown labels of `s` along their lines for this frame,
/// and the icons turned with them, as MapLibre's `updateLineLabels` (turned to
/// read upright with `*-keep-upright`; hidden where the line ends first).
fn Map::lay_line_glyphs(
  self : Map,
  mesh : @render_webgl2.Mesh,
  at : @render_webgl2.Placement,
  id : @core.TileId,
  s : LabelSet,
  l : LineSet,
  tile_px : Double,
  height_scale : Double,
) -> Unit {
  let t = self.transform
  if l.laid == Some(t.camera) && l.laid_round == s.round {
    return
  }
  l.laid = Some(t.camera)
  l.laid_round = s.round
  let clip_x = CLIP_BUFFER_PX / t.width * 2.0 + 1.0
  let clip_y = CLIP_BUFFER_PX / t.height * 2.0 + 1.0
  for i in 0..<s.count {
    guard s.shown[i] else { continue }
    let row = i * LABEL_FLOATS
    let q0 = quad_at(s.labels, row + LABEL_FIRST)
    let n = quad_at(s.labels, row + LABEL_COUNT)
    let x = f32_at(s.labels, row)
    let y = f32_at(s.labels, row + LABEL_Y)
    let z = s.heights[i] * height_scale
    let (cx, cy, cw, _) = self.label_clip(at, id, x, y, z)
    if cw <= 0.0 || (cx / cw).abs() > clip_x || (cy / cw).abs() > clip_y {
      hide_glyphs(l.glyphs, q0, n)
      continue
    }
    let ratio = perspective_ratio(at, cw)
    let scale = f32_at(s.labels, row + LABEL_SIZE) *
      self.text_correction(id, y) /
      ratio /
      ONE_EM *
      tile_px
    let g0 = l.meta[i * LINE_FLOATS + 4].to_int()
    // Text reading right to left on screen is laid out backwards instead.
    let mut flip = false
    if l.keep_upright && n > 1 {
      guard l.along(i, x, y, l.offsets[g0] * scale, false, None) else {
        hide_glyphs(l.glyphs, q0, n)
        continue
      }
      let (ax, ay) = (l.at_x, l.at_y)
      guard l.along(i, x, y, l.offsets[g0 + n - 1] * scale, false, None) else {
        hide_glyphs(l.glyphs, q0, n)
        continue
      }
      flip = self.ndc_x(at, id, ax, ay, z) >
        self.ndc_x(at, id, l.at_x, l.at_y, z)
    } else if l.keep_upright {
      flip = self.backwards(l, at, id, i, x, y, z)
    }
    for k in 0..<n {
      guard l.along(i, x, y, l.offsets[g0 + k] * scale, flip, None) else {
        hide_glyphs(l.glyphs, q0, n)
        break
      }
      let g = (q0 + k) * 3
      l.glyphs[g] = l.at_x
      l.glyphs[g + 1] = l.at_y
      l.glyphs[g + 2] = l.at_angle
    }
  }
  self.renderer.set_glyphs(mesh, l.glyphs)
  guard s.icon is Some(ic) && ic.rotate_with_map else { return }
  // An icon is one glyph at its anchor, turned to its segment.
  for i in 0..<s.count {
    guard ic.shown[i] else { continue }
    let row = i * LABEL_FLOATS
    let g = quad_at(s.labels, row + ICON_FIRST) * 3
    let x = f32_at(s.labels, row)
    let y = f32_at(s.labels, row + LABEL_Y)
    let z = s.heights[i] * height_scale
    let flip = ic.keep_upright && self.backwards(l, at, id, i, x, y, z)
    ic.glyphs[g] = HIDDEN_GLYPH
    if l.along(i, x, y, 0.0, flip, None) {
      ic.glyphs[g] = l.at_x
      ic.glyphs[g + 1] = l.at_y
      ic.glyphs[g + 2] = l.at_angle
    }
  }
  self.renderer.set_glyphs(ic.mesh, ic.glyphs)
}
