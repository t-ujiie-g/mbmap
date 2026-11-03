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
/// The labels along lines of a symbol mesh: `meta` (`LINE_FLOATS` per label),
/// `lines` (x, y in tile units), each glyph's `offsets` along its line (glyph
/// units, 24 an em), and where each glyph quad is drawn (`glyphs`: x, y in tile
/// units, angle), laid out for camera `laid` at placement round `laid_round`.
priv struct LineSet {
  meta : FixedArray[Double]
  lines : FixedArray[Double]
  offsets : FixedArray[Double]
  keep_upright : Bool
  glyphs : FixedArray[Double]
  mut laid : @core.Camera?
  mut laid_round : Int32
}

///|
extern "js" fn has(v : JsValue, key : String) -> Bool =
  #|(v, k) => v[k] != null

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
  })
}

///|
/// MapLibre's `placeGlyphAlongLine` in tile units: the point `offset` along the
/// line of label `i` from its anchor (x, y), backwards with `flip`, and the
/// line's angle there; `path` gets the points walked past. None past the line's end.
fn LineSet::along(
  self : LineSet,
  i : Int32,
  x : Double,
  y : Double,
  offset : Double,
  flip : Bool,
  path : Array[Double]?,
) -> (Double, Double, Double)? {
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
      return None
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
  Some((gx, gy, angle + @math.atan2(cy - py, cx - px)))
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
/// Places label `i` of `s` along its line as MapLibre's
/// `placeCollisionCircles`: circles over the path from its first glyph to its
/// last, which must meet nothing placed unless it may overlap.
fn Map::place_line_label(
  self : Map,
  grid : @label.Grid,
  at : @render_webgl2.Placement,
  s : LabelSet,
  l : LineSet,
  i : Int32,
  height_scale : Double,
  tile_px : Double,
) -> Bool {
  let t = self.transform
  let (w, h) = (t.width, t.height)
  let row = i * LABEL_FLOATS
  let (x, y) = (f32_at(s.labels, row), f32_at(s.labels, row + 1))
  let z = s.heights[i] * height_scale
  let (_, _, _, cw) = at.matrix.apply(x, y, z, 1.0)
  let ratio = 0.5 + 0.5 * at.center_depth / cw
  let m = i * LINE_FLOATS
  let first = l.meta[m + 4].to_int()
  let glyphs = (f32_at(s.labels, row + LABEL_FLOATS - 1) / 6.0).to_int()
  let scale = f32_at(s.labels, row + LABEL_SIZE) / ratio / 24.0 * tile_px
  let (head, tail) = ([], [])
  let circles = []
  let mut collided = false
  let mut in_grid = false
  if cw > 0.0 &&
    l.along(i, x, y, l.offsets[first] * scale, false, Some(head)) is Some(_) &&
    l.along(i, x, y, l.offsets[first + glyphs - 1] * scale, false, Some(tail))
    is Some(_) {
    // From the first glyph back past the anchor's vertices to the last.
    let path = []
    let mut behind = false
    let screen = (k : Int32, p : Array[Double]) => {
      let (cx, cy, _, pw) = at.matrix.apply(p[k * 2], p[k * 2 + 1], z, 1.0)
      behind = behind || pw <= 0.0
      path.push((cx / pw + 1.0) * 0.5 * w)
      path.push((1.0 - cy / pw) * 0.5 * h)
    }
    for k = head.length() / 2 - 1; k >= 1; k = k - 1 {
      screen(k, head)
    }
    for k in 1..<(tail.length() / 2) {
      screen(k, tail)
    }
    let radius = l.meta[m + 5] * 0.5 * ratio + s.padding
    let (lo_x, lo_y) = (-VIEWPORT_PADDING, -VIEWPORT_PADDING)
    let (hi_x, hi_y) = (w + VIEWPORT_PADDING, h + VIEWPORT_PADDING)
    let parts = if behind || path.is_empty() {
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
      if !s.allow_overlap && grid.hits_circle(cx, cy, radius) {
        collided = true
        break
      }
    }
  }
  if collided || !in_grid || ratio < MIN_PERSPECTIVE_RATIO {
    circles.clear()
  }
  let placed = s.allow_overlap || (!circles.is_empty() && !collided)
  // Queries find the label by its circles' bounds.
  let b = s.boxes
  let o = i * BOX_FLOATS
  b[o] = @double.not_a_number
  if placed && !circles.is_empty() {
    b[o] = @double.infinity
    b[o + 1] = @double.infinity
    b[o + 2] = @double.neg_infinity
    b[o + 3] = @double.neg_infinity
    for k = 0; k < circles.length(); k = k + 3 {
      let (cx, cy, r) = (circles[k], circles[k + 1], circles[k + 2])
      if !s.ignore_placement {
        grid.insert_circle(cx, cy, r)
      }
      b[o] = @cmp.minimum(b[o], cx - r - VIEWPORT_PADDING)
      b[o + 1] = @cmp.minimum(b[o + 1], cy - r - VIEWPORT_PADDING)
      b[o + 2] = @cmp.maximum(b[o + 2], cx + r - VIEWPORT_PADDING)
      b[o + 3] = @cmp.maximum(b[o + 3], cy + r - VIEWPORT_PADDING)
    }
  }
  placed
}

///|
/// Lays the glyphs of the shown labels of `s` along their lines for this
/// frame, as MapLibre's `updateLineLabels` (turned to read upright with
/// `text-keep-upright`; hidden where the line ends first), and uploads them.
fn Map::lay_line_glyphs(
  self : Map,
  mesh : @render_webgl2.Mesh,
  at : @render_webgl2.Placement,
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
  let clip_x = 256.0 / t.width * 2.0 + 1.0
  let clip_y = 256.0 / t.height * 2.0 + 1.0
  for i in 0..<s.count {
    guard s.shown[i] else { continue }
    let row = i * LABEL_FLOATS
    let q0 = (f32_at(s.labels, row + LABEL_FLOATS - 2) / 6.0).to_int()
    let n = (f32_at(s.labels, row + LABEL_FLOATS - 1) / 6.0).to_int()
    let hide = () => {
      for k in 0..<n {
        l.glyphs[(q0 + k) * 3] = HIDDEN_GLYPH
      }
    }
    let (x, y) = (f32_at(s.labels, row), f32_at(s.labels, row + 1))
    let z = s.heights[i] * height_scale
    let (cx, cy, _, cw) = at.matrix.apply(x, y, z, 1.0)
    if cw <= 0.0 || (cx / cw).abs() > clip_x || (cy / cw).abs() > clip_y {
      hide()
      continue
    }
    let ratio = 0.5 + 0.5 * at.center_depth / cw
    let scale = f32_at(s.labels, row + LABEL_SIZE) / ratio / 24.0 * tile_px
    let g0 = l.meta[i * LINE_FLOATS + 4].to_int()
    let clip = (px : Double, py : Double) => {
      let (ex, _, _, ew) = at.matrix.apply(px, py, z, 1.0)
      ex / ew
    }
    // Text reading right to left on screen is laid out backwards instead.
    let flip = if !l.keep_upright {
      Some(false)
    } else if n > 1 {
      match
        (
          l.along(i, x, y, l.offsets[g0] * scale, false, None),
          l.along(i, x, y, l.offsets[g0 + n - 1] * scale, false, None),
        ) {
        (Some((ax, ay, _)), Some((bx, by, _))) =>
          Some(clip(ax, ay) > clip(bx, by))
        _ => None
      }
    } else {
      let v = l.meta[i * LINE_FLOATS + 2].to_int() +
        l.meta[i * LINE_FLOATS + 1].to_int() +
        1
      Some(clip(x, y) > clip(l.lines[v * 2], l.lines[v * 2 + 1]))
    }
    guard flip is Some(flip) else {
      hide()
      continue
    }
    for k in 0..<n {
      match l.along(i, x, y, l.offsets[g0 + k] * scale, flip, None) {
        Some((gx, gy, angle)) => {
          l.glyphs[(q0 + k) * 3] = gx
          l.glyphs[(q0 + k) * 3 + 1] = gy
          l.glyphs[(q0 + k) * 3 + 2] = angle
        }
        None => {
          hide()
          break
        }
      }
    }
  }
  self.renderer.set_glyphs(mesh, l.glyphs)
}
