///|
/// How line segments meet (`line-join`).
pub(all) enum LineJoin {
  Miter
  Bevel
  Round
} derive(Debug, Eq)

///|
/// How a line ends (`line-cap`).
pub(all) enum LineCap {
  Butt
  Square
  Round
} derive(Debug, Eq)

///|
/// Extrusion vectors are stored as integers scaled by this, so a unit normal
/// fits in an Int8 component; the shader divides it back out.
pub const EXTRUDE_SCALE : Int32 = 63

///|
/// Ints per line vertex: x, y; extrusion x, y (`EXTRUDE_SCALE` per half width);
/// side (±1 at the outlines) and along (1 at a round cap's end). The shader
/// fades out where `length(side, along)` reaches 1, rounding the caps.
pub const LINE_VERTEX_STRIDE : Int32 = 6

///|
/// Longest miter, and longest offset normal at a join (MapLibre's
/// `MAX_OFFSET_MITER_LENGTH`), that still fits an Int8 extrusion component.
const MAX_MITER_LIMIT : Double = 2.0

///|
/// MapLibre's sharp corners for dashes: a corner whose half angle's cosine is
/// below this (75°) gets a point `SHARP_CORNER_OFFSET` px (of a 512 px tile)
/// along each side, so less of the line has its dashes tilted.
const COS_HALF_SHARP_CORNER : Double = 0.7933533402912352

///|
const SHARP_CORNER_OFFSET : Double = 15.0

///|
/// Distances along a line are kept in `@core.TILE_EXTENT` units (MapLibre's
/// `linesofar` halved, in `MAPLIBRE_EXTENT` units) and start again from 0 past this.
pub const MAX_LINE_DISTANCE : Int32 = 8192

///|
/// MapLibre's tile extent, whatever the source's.
const MAPLIBRE_EXTENT : Double = 8192.0

///|
/// Fan segments per half turn of a round join.
const ROUND_SEGMENTS : Int32 = 8

///|
/// Line geometry: `LINE_VERTEX_STRIDE` ints per vertex, triangle `indices`, and
/// per vertex `distances` (dashed), `progress` (`line-progress`) and `offsets`
/// (`a_offset_normal` at `EXTRUDE_SCALE`); docs/FORMATS.md "Packed tile".
pub struct LineBuffers {
  vertices : Array[Int32]
  indices : Array[Int32]
  distances : Array[Int32]
  progress : Array[Double]
  offsets : Array[Int32]
  priv mut max_length : Int32
}

///|
pub fn LineBuffers::new() -> LineBuffers {
  {
    vertices: [],
    indices: [],
    distances: [],
    progress: [],
    offsets: [],
    max_length: 0x7fffffff,
  }
}

///|
/// Stops `add_line` once the buffers hold more than `n` vertices (`full`):
/// a few points of a hostile tile can make millions of vertices.
pub fn LineBuffers::limit(self : LineBuffers, n : Int32) -> Unit {
  self.max_length = if n > 0x7fffffff / LINE_VERTEX_STRIDE {
    0x7fffffff
  } else {
    n * LINE_VERTEX_STRIDE
  }
}

///|
/// Whether the buffers hold more vertices than their `limit`.
pub fn LineBuffers::full(self : LineBuffers) -> Bool {
  self.vertices.length() > self.max_length
}

///|
pub fn LineBuffers::clear(self : LineBuffers) -> Unit {
  self.vertices.clear()
  self.indices.clear()
  self.distances.clear()
  self.progress.clear()
  self.offsets.clear()
  self.max_length = 0x7fffffff
}

///|
pub fn LineBuffers::num_vertices(self : LineBuffers) -> Int32 {
  self.vertices.length() / LINE_VERTEX_STRIDE
}

///|
/// Extrudes polylines into triangles. Reuse one instance; its scratch buffers
/// keep their capacity, so steady-state use does not allocate.
pub struct LineTessellator {
  priv trig : @core.Trig
  priv xs : Array[Int32]
  priv ys : Array[Int32]
  priv nx : Array[Double]
  priv ny : Array[Double]
  priv cx : Array[Int32]
  priv cy : Array[Int32]
}

///|
/// `trig` gives round joins their angles (a wasm build passes the host's).
pub fn LineTessellator::new(
  trig~ : @core.Trig = @core.Trig::moonbit(),
) -> LineTessellator {
  { trig, xs: [], ys: [], nx: [], ny: [], cx: [], cy: [], }
}

///|
/// Appends the line through points `[start, end)` of `coords` to `out` (equal ends
/// close it); `miter_limit` is in half widths. `dashed` (with `extent`), `progress`
/// and `offset` record `out`'s per-vertex arrays, the first two splitting sharp corners.
pub fn LineTessellator::add_line(
  self : LineTessellator,
  coords : ArrayView[Int32],
  start : Int32,
  end : Int32,
  out : LineBuffers,
  join~ : LineJoin = Miter,
  cap~ : LineCap = Butt,
  miter_limit~ : Double = 2.0,
  round_limit~ : Double = 1.05,
  dashed~ : Bool = false,
  progress~ : Bool = false,
  offset~ : Bool = false,
  extent~ : Int32 = @core.TILE_EXTENT,
) -> Unit {
  let n = self.load_points(coords, start, end)
  let closed = n > 2 &&
    self.xs[0] == self.xs[n - 1] &&
    self.ys[0] == self.ys[n - 1]
  let n = if closed { n - 1 } else { n }
  if n < 2 {
    return
  }
  let segments = if closed { n } else { n - 1 }
  self.compute_normals(n, segments)
  // MapLibre takes the length before splitting corners.
  let mut total = 0.0
  for i in 0..<segments {
    let j = (i + 1) % n
    let dx = self.xs[j].to_double() - self.xs[i].to_double()
    let dy = self.ys[j].to_double() - self.ys[i].to_double()
    total += (dx * dx + dy * dy).sqrt()
  }
  let n = if dashed || progress {
    let offset = SHARP_CORNER_OFFSET * extent.to_double() / @core.TILE_SIZE
    let m = self.split_corners(n, closed, offset)
    self.compute_normals(m, if closed { m } else { m - 1 })
    m
  } else {
    n
  }
  let miter_limit = @cmp.minimum(miter_limit, MAX_MITER_LIMIT)
  // A new emitter per line: reusing one was slower in V8 (PROGRESS.md, R3).
  let emitter : Emitter = {
    trig: self.trig,
    out,
    join,
    miter_limit,
    round_limit,
    dashed,
    progress,
    offset,
    total,
    scale: @core.TILE_EXTENT.to_double() / extent.to_double(),
    along: 0.0,
    whole: 0.0,
    distance: 0,
    ox: 0.0,
    oy: 0.0,
    jx: 0.0,
    jy: 0.0,
    fallback: 0.0,
  }
  let xs = self.xs
  let ys = self.ys
  let nx = self.nx
  let ny = self.ny
  if closed {
    // Start past the join at point 0; that join is drawn last, back into
    // `first`, or into a pair at the ring's full length when dashed.
    emitter.join_offset(nx[n - 1], ny[n - 1], nx[0], ny[0])
    emitter.offset_toward(nx[0], ny[0])
    let first = emitter.pair(xs[0], ys[0], nx[0], ny[0])
    let mut prev = first
    for i in 1..<n {
      if out.full() {
        return
      }
      emitter.advance(xs[i - 1], ys[i - 1], xs[i], ys[i])
      prev = emitter.join_at(
        xs[i],
        ys[i],
        nx[i - 1],
        ny[i - 1],
        nx[i],
        ny[i],
        prev,
      )
      prev = emitter.restart(prev)
    }
    emitter.advance(xs[n - 1], ys[n - 1], xs[0], ys[0])
    emitter.join_offset(nx[n - 1], ny[n - 1], nx[0], ny[0])
    emitter.offset_toward(nx[0], ny[0])
    let close_to = if dashed {
      emitter.pair(xs[0], ys[0], nx[0], ny[0])
    } else {
      first
    }
    ignore(
      emitter.join_at(
        xs[0],
        ys[0],
        nx[n - 1],
        ny[n - 1],
        nx[0],
        ny[0],
        prev,
        close_to~,
      ),
    )
    return
  }
  emitter.end_offset(nx[0], ny[0])
  let mut prev = emitter.pair_for_cap(
    xs[0],
    ys[0],
    nx[0],
    ny[0],
    cap,
    start=true,
  )
  emitter.cap_extension(xs[0], ys[0], nx[0], ny[0], cap, prev, start=true)
  for i in 1..<(n - 1) {
    if out.full() {
      return
    }
    emitter.advance(xs[i - 1], ys[i - 1], xs[i], ys[i])
    prev = emitter.join_at(
      xs[i],
      ys[i],
      nx[i - 1],
      ny[i - 1],
      nx[i],
      ny[i],
      prev,
    )
    prev = emitter.restart(prev)
  }
  let last = n - 1
  emitter.advance(xs[last - 1], ys[last - 1], xs[last], ys[last])
  emitter.end_offset(nx[last - 1], ny[last - 1])
  let end_pair = emitter.pair_for_cap(
    xs[last],
    ys[last],
    nx[last - 1],
    ny[last - 1],
    cap,
    start=false,
  )
  emitter.quad(prev, end_pair)
  emitter.cap_extension(
    xs[last],
    ys[last],
    nx[last - 1],
    ny[last - 1],
    cap,
    end_pair,
    start=false,
  )
}

///|
/// Copies the points without consecutive duplicates; returns their count.
fn LineTessellator::load_points(
  self : LineTessellator,
  coords : ArrayView[Int32],
  start : Int32,
  end : Int32,
) -> Int32 {
  self.xs.clear()
  self.ys.clear()
  for i in start..<end {
    let x = coords[i * 2]
    let y = coords[i * 2 + 1]
    let k = self.xs.length()
    if k == 0 || self.xs[k - 1] != x || self.ys[k - 1] != y {
      self.xs.push(x)
      self.ys.push(y)
    }
  }
  self.xs.length()
}

///|
/// Unit left normal of each segment (segment `i` runs from point `i` to `i + 1`,
/// wrapping for closed lines).
fn LineTessellator::compute_normals(
  self : LineTessellator,
  n : Int32,
  segments : Int32,
) -> Unit {
  self.nx.clear()
  self.ny.clear()
  for i in 0..<segments {
    let j = (i + 1) % n
    let dx = self.xs[j].to_double() - self.xs[i].to_double()
    let dy = self.ys[j].to_double() - self.ys[i].to_double()
    let len = (dx * dx + dy * dy).sqrt()
    self.nx.push(-dy / len)
    self.ny.push(dx / len)
  }
}

///|
/// Adds a point `offset` units from each side of every sharp corner of the
/// `n` points (whose normals are computed), on segments longer than twice
/// that, as MapLibre's line bucket does; returns the new count.
fn LineTessellator::split_corners(
  self : LineTessellator,
  n : Int32,
  closed : Bool,
  offset : Double,
) -> Int32 {
  let sharp = (i : Int32) => {
    guard closed || (i > 0 && i < n - 1) else { false }
    let a = (i + n - 1) % n
    let jx = self.nx[a] + self.nx[i]
    let jy = self.ny[a] + self.ny[i]
    let len = (jx * jx + jy * jy).sqrt()
    let cos_half = if len > 0.0 {
      (jx * self.nx[i] + jy * self.ny[i]) / len
    } else {
      0.0
    }
    cos_half < COS_HALF_SHARP_CORNER
  }
  let cx = self.cx
  let cy = self.cy
  cx.clear()
  cy.clear()
  // A point `offset` from (x, y) toward (tx, ty), on MapLibre's rounding.
  let toward = (x : Int32, y : Int32, tx : Int32, ty : Int32) => {
    let dx = tx.to_double() - x.to_double()
    let dy = ty.to_double() - y.to_double()
    let len = (dx * dx + dy * dy).sqrt()
    if len > 2.0 * offset {
      let k = offset / len
      cx.push(x + (dx * k + 0.5).floor().to_int())
      cy.push(y + (dy * k + 0.5).floor().to_int())
    }
  }
  // MapLibre moves a point toward the corner by the rounded difference.
  let before = (x : Int32, y : Int32) => {
    let k = cx.length() - 1
    let dx = x.to_double() - cx[k].to_double()
    let dy = y.to_double() - cy[k].to_double()
    let len = (dx * dx + dy * dy).sqrt()
    if len > 2.0 * offset {
      let f = offset / len
      cx.push(x - (dx * f + 0.5).floor().to_int())
      cy.push(y - (dy * f + 0.5).floor().to_int())
    }
  }
  for i in 0..<n {
    let s = sharp(i)
    if s && i > 0 {
      before(self.xs[i], self.ys[i])
    }
    cx.push(self.xs[i])
    cy.push(self.ys[i])
    if s {
      let j = (i + 1) % n
      toward(self.xs[i], self.ys[i], self.xs[j], self.ys[j])
    }
  }
  if closed && sharp(0) {
    before(self.xs[0], self.ys[0])
  }
  self.xs.clear()
  self.ys.clear()
  for i, x in cx {
    self.xs.push(x)
    self.ys.push(cy[i])
  }
  cx.length()
}
