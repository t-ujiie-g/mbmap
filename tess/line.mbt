///|
pub(all) enum LineJoin {
  Miter
  Bevel
  Round
} derive(Debug, Eq)

///|
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
/// Longest miter that still fits an Int8 extrusion component.
pub const MAX_MITER_LIMIT : Double = 2.0

///|
/// MapLibre's sharp corners for dashes: a corner whose half angle's cosine is
/// below this (75°) gets a point `SHARP_CORNER_OFFSET` px (of a 512 px tile)
/// along each side, so less of the line has its dashes tilted.
const COS_HALF_SHARP_CORNER : Double = 0.7933533402912352

///|
const SHARP_CORNER_OFFSET : Double = 15.0

///|
/// Distances along a line are kept in `@core.TILE_EXTENT` units (MapLibre's
/// `linesofar` halved, in its 8192-unit tile) and start again from 0 past this.
pub const MAX_LINE_DISTANCE : Int32 = 8192

///|
/// Fan segments per half turn of a round join.
const ROUND_SEGMENTS : Int32 = 8

///|
/// Line geometry: `vertices` holds `LINE_VERTEX_STRIDE` ints per vertex,
/// `indices` triangles, and per vertex `distances` along its line when dashed,
/// `progress` (MapLibre's `line-progress`) and `offsets` (x, y at `EXTRUDE_SCALE`:
/// MapLibre's `a_offset_normal`), docs/FORMATS.md "Packed tile".
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
  extent~ : Int32 = 4096,
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
    let offset = SHARP_CORNER_OFFSET * extent.to_double() / 512.0
    let m = self.split_corners(n, closed, offset)
    self.compute_normals(m, if closed { m } else { m - 1 })
    m
  } else {
    n
  }
  let miter_limit = @cmp.minimum(miter_limit, MAX_MITER_LIMIT)
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

///|
/// Writes vertices: dashed, `along` units so far (`scale` stored units per unit);
/// with `progress`, `whole` units of `total`; with `offset`, (`ox`, `oy`), at a join
/// its offset normal (`jx`, `jy`) eased `fallback` toward the vertex's normal.
priv struct Emitter {
  trig : @core.Trig
  out : LineBuffers
  join : LineJoin
  miter_limit : Double
  round_limit : Double
  dashed : Bool
  progress : Bool
  offset : Bool
  total : Double
  scale : Double
  mut along : Double
  mut whole : Double
  mut distance : Int32
  mut ox : Double
  mut oy : Double
  mut jx : Double
  mut jy : Double
  mut fallback : Double
}

///|
/// Longest offset normal at a join (MapLibre's `MAX_OFFSET_MITER_LENGTH`: what
/// a byte at `EXTRUDE_SCALE` holds).
const MAX_OFFSET_MITER : Double = 2.0

///|
/// Offset normals follow a join's miter vector at a line end's normal.
fn Emitter::end_offset(self : Emitter, nx : Double, ny : Double) -> Unit {
  self.ox = nx
  self.oy = ny
}

///|
/// The offset normal of the join between normals a and b (MapLibre's
/// `offsetNormal` and `offsetFallback`, easing from miter length 3 to 8).
fn Emitter::join_offset(
  self : Emitter,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
) -> Unit {
  let mx = ax + bx
  let my = ay + by
  let len = (mx * mx + my * my).sqrt()
  if len == 0.0 {
    self.jx = bx
    self.jy = by
    self.fallback = 1.0
    return
  }
  let ux = mx / len
  let uy = my / len
  let cos_half = ux * bx + uy * by
  let miter = if cos_half != 0.0 { 1.0 / cos_half } else { @double.infinity }
  let k = @cmp.minimum(miter, MAX_OFFSET_MITER)
  self.jx = ux * k
  self.jy = uy * k
  self.fallback = @cmp.maximum(0.0, @cmp.minimum(1.0, (miter - 3.0) / 5.0))
  self.ox = self.jx
  self.oy = self.jy
}

///|
/// Sets the offset normal of the next vertices to the join's, eased toward the
/// normal (nx, ny).
fn Emitter::offset_toward(self : Emitter, nx : Double, ny : Double) -> Unit {
  self.ox = self.jx + (nx - self.jx) * self.fallback
  self.oy = self.jy + (ny - self.jy) * self.fallback
}

///|
/// Moves the distance along the segment from (x0, y0) to (x1, y1).
fn Emitter::advance(
  self : Emitter,
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
) -> Unit {
  if self.dashed || self.progress {
    let dx = x1.to_double() - x0.to_double()
    let dy = y1.to_double() - y0.to_double()
    let d = (dx * dx + dy * dy).sqrt()
    self.whole += d
    self.along += d
    self.distance = @cmp.minimum(
      0xffff,
      (self.along * self.scale).floor().to_int(),
    )
  }
}

///|
/// Past `MAX_LINE_DISTANCE`, repeats pair `p` at distance 0 (as MapLibre does,
/// unless the line has progress) and returns the copy; otherwise `p`.
fn Emitter::restart(self : Emitter, p : Int32) -> Int32 {
  guard self.dashed && !self.progress && self.distance > MAX_LINE_DISTANCE else {
    return p
  }
  self.along = 0.0
  self.distance = 0
  let v = self.out.vertices
  let id = v.length() / LINE_VERTEX_STRIDE
  for k in 0..<(2 * LINE_VERTEX_STRIDE) {
    v.push(v[p * LINE_VERTEX_STRIDE + k])
  }
  if self.offset {
    let o = self.out.offsets
    for k in 0..<4 {
      o.push(o[p * 2 + k])
    }
  }
  self.out.distances.push(0)
  self.out.distances.push(0)
  id
}

///|
fn Emitter::vertex(
  self : Emitter,
  x : Int32,
  y : Int32,
  ex : Double,
  ey : Double,
  side : Int32,
  along~ : Int32 = 0,
) -> Int32 {
  let v = self.out.vertices
  let id = v.length() / LINE_VERTEX_STRIDE
  v.push(x)
  v.push(y)
  v.push((ex * EXTRUDE_SCALE.to_double()).round().to_int())
  v.push((ey * EXTRUDE_SCALE.to_double()).round().to_int())
  v.push(side)
  v.push(along)
  if self.dashed {
    self.out.distances.push(self.distance)
  }
  if self.offset {
    self.out.offsets.push(
      (self.ox * EXTRUDE_SCALE.to_double()).round().to_int(),
    )
    self.out.offsets.push(
      (self.oy * EXTRUDE_SCALE.to_double()).round().to_int(),
    )
  }
  if self.progress {
    self.out.progress.push(
      if self.total > 0.0 {
        self.whole / self.total
      } else {
        0.0
      },
    )
  }
  id
}

///|
/// Emits the left (+e) and right (-e) outline vertices at a point; returns the
/// left one's id, the right one follows it.
fn Emitter::pair(
  self : Emitter,
  x : Int32,
  y : Int32,
  ex : Double,
  ey : Double,
) -> Int32 {
  let left = self.vertex(x, y, ex, ey, 1)
  ignore(self.vertex(x, y, -ex, -ey, -1))
  left
}

///|
fn Emitter::triangle(self : Emitter, a : Int32, b : Int32, c : Int32) -> Unit {
  self.out.indices.push(a)
  self.out.indices.push(b)
  self.out.indices.push(c)
}

///|
/// Connects two outline pairs with a quad.
fn Emitter::quad(self : Emitter, from : Int32, to : Int32) -> Unit {
  self.triangle(from, from + 1, to)
  self.triangle(from + 1, to + 1, to)
}

///|
/// Fills the arc around (x, y) from rim vertex `from` to `to` with `steps`
/// triangles, rotating (vx, vy) by the step's cosine `c` and sine `s`.
fn Emitter::fan(
  self : Emitter,
  x : Int32,
  y : Int32,
  center : Int32,
  from : Int32,
  to : Int32,
  vx : Double,
  vy : Double,
  c : Double,
  s : Double,
  steps : Int32,
  side : Int32,
) -> Unit {
  let mut prev = from
  let mut vx = vx
  let mut vy = vy
  for _ in 1..<steps {
    let rx = vx * c - vy * s
    vy = vx * s + vy * c
    vx = rx
    let rim = self.vertex(x, y, vx, vy, side)
    self.triangle(center, prev, rim)
    prev = rim
  }
  self.triangle(center, prev, to)
}

///|
/// Emits the outline pair at a line end whose segment has normal (nx, ny); a
/// square cap pushes it half a width past the end.
fn Emitter::pair_for_cap(
  self : Emitter,
  x : Int32,
  y : Int32,
  nx : Double,
  ny : Double,
  cap : LineCap,
  start~ : Bool,
) -> Int32 {
  match cap {
    Square => {
      // Direction pointing away from the line, past this end.
      let (ox, oy) = if start { (-ny, nx) } else { (ny, -nx) }
      let left = self.vertex(x, y, nx + ox, ny + oy, 1)
      ignore(self.vertex(x, y, -nx + ox, -ny + oy, -1))
      left
    }
    Butt | Round => self.pair(x, y, nx, ny)
  }
}

///|
/// For a round cap, extends the line by half a width past the end with a quad
/// whose far edge has `along` 1; the shader cuts it to a half disk.
fn Emitter::cap_extension(
  self : Emitter,
  x : Int32,
  y : Int32,
  nx : Double,
  ny : Double,
  cap : LineCap,
  pair : Int32,
  start~ : Bool,
) -> Unit {
  if cap is Round {
    // Direction pointing away from the line, past this end.
    let (ox, oy) = if start { (-ny, nx) } else { (ny, -nx) }
    let far = self.vertex(x, y, nx + ox, ny + oy, 1, along=1)
    ignore(self.vertex(x, y, -nx + ox, -ny + oy, -1, along=1))
    self.quad(pair, far)
  }
}

///|
/// Emits the join at (x, y) between normals a and b after the segment from
/// `prev`, returning the outgoing pair (`close_to` when closing a ring); nearly
/// straight joins share one pair.
fn Emitter::join_at(
  self : Emitter,
  x : Int32,
  y : Int32,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  prev : Int32,
  close_to? : Int32,
) -> Int32 {
  let mx = ax + bx
  let my = ay + by
  let mlen = (mx * mx + my * my).sqrt()
  // Miter length in half widths: 1 / cos(half the turn angle).
  let miter = if mlen > 0.0 { 2.0 / mlen } else { @double.infinity }
  let use_miter = match self.join {
    Miter => miter <= self.miter_limit
    // MapLibre draws a bevel join as a miter below the miter limit.
    Bevel => miter < self.miter_limit
    Round => miter < self.round_limit
  }
  if close_to is None {
    self.join_offset(ax, ay, bx, by)
  }
  if use_miter && close_to is None {
    self.ox = self.jx
    self.oy = self.jy
    let pair = self.pair(x, y, mx / mlen * miter, my / mlen * miter)
    self.quad(prev, pair)
    return pair
  }
  self.offset_toward(ax, ay)
  let end_pair = self.pair(x, y, ax, ay)
  self.quad(prev, end_pair)
  let start_pair = match close_to {
    Some(p) => p
    None => {
      self.offset_toward(bx, by)
      self.pair(x, y, bx, by)
    }
  }
  self.ox = self.jx
  self.oy = self.jy
  let cross = ax * by - ay * bx
  if cross == 0.0 && ax * bx + ay * by > 0.0 {
    return start_pair
  }
  // Turning toward +a (cross > 0) opens the gap on the -a outline.
  let s = if cross > 0.0 { -1 } else { 1 }
  let (from, to) = if s < 0 {
    (end_pair + 1, start_pair + 1)
  } else {
    (end_pair, start_pair)
  }
  let sd = s.to_double()
  let center = self.vertex(x, y, 0.0, 0.0, 0)
  if use_miter {
    let tip = self.vertex(
      x,
      y,
      sd * mx / mlen * miter,
      sd * my / mlen * miter,
      s,
    )
    self.triangle(center, from, tip)
    self.triangle(center, tip, to)
  } else if self.join is Round {
    // Signed angle from s·a to s·b; the sign flip cancels in the cross product.
    let sweep = self.trig.atan2(cross, ax * bx + ay * by)
    let steps = @cmp.maximum(
      1,
      (sweep.abs() / @math.PI * ROUND_SEGMENTS.to_double()).ceil().to_int(),
    )
    let step = sweep / steps.to_double()
    self.fan(
      x,
      y,
      center,
      from,
      to,
      sd * ax,
      sd * ay,
      self.trig.cos(step),
      self.trig.sin(step),
      steps,
      s,
    )
  } else {
    self.triangle(center, from, to)
  }
  start_pair
}
