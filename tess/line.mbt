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
/// Ints per line vertex: x, y in tile units; extrusion x, y in `EXTRUDE_SCALE`
/// units of half the line width; side, ±1 on the outlines and 0 on the center
/// line; along, 1 at the far edge of a round cap and 0 elsewhere. The shader
/// fades out where `length(side, along)` reaches 1, which antialiases the
/// outlines and rounds the caps.
pub const LINE_VERTEX_STRIDE : Int32 = 6

///|
/// Longest miter that still fits an Int8 extrusion component.
pub const MAX_MITER_LIMIT : Double = 2.0

///|
/// Slack when deciding that a join is straight (miter length 1).
const STRAIGHT_EPSILON : Double = 1.0e-9

///|
/// Fan segments per half turn of a round join.
const ROUND_SEGMENTS : Int32 = 8

///|
/// Line geometry: `vertices` holds `LINE_VERTEX_STRIDE` ints per vertex and
/// `indices` holds triangles as vertex index triples.
pub struct LineBuffers {
  vertices : Array[Int32]
  indices : Array[Int32]
}

///|
pub fn LineBuffers::new() -> LineBuffers {
  { vertices: [], indices: [], }
}

///|
pub fn LineBuffers::clear(self : LineBuffers) -> Unit {
  self.vertices.clear()
  self.indices.clear()
}

///|
pub fn LineBuffers::num_vertices(self : LineBuffers) -> Int32 {
  self.vertices.length() / LINE_VERTEX_STRIDE
}

///|
/// Extrudes polylines into triangles. Reuse one instance; its scratch buffers
/// keep their capacity, so steady-state use does not allocate.
pub struct LineTessellator {
  priv xs : Array[Int32]
  priv ys : Array[Int32]
  priv nx : Array[Double]
  priv ny : Array[Double]
}

///|
pub fn LineTessellator::new() -> LineTessellator {
  { xs: [], ys: [], nx: [], ny: [], }
}

///|
/// Appends the line through points `[start, end)` of `coords` (x, y pairs) to
/// `out`. Repeated points are skipped; a line whose first and last points are
/// equal is closed (joined at the start, no caps). `miter_limit` is the longest
/// miter in half widths, clamped to `MAX_MITER_LIMIT`; round joins whose miter
/// would be shorter than `round_limit` are drawn as miters.
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
  let miter_limit = @cmp.minimum(miter_limit, MAX_MITER_LIMIT)
  let emitter = { out, join, miter_limit, round_limit, }
  let xs = self.xs
  let ys = self.ys
  let nx = self.nx
  let ny = self.ny
  if closed {
    // Start past the join at point 0; that join is drawn last, back into `first`.
    let first = emitter.pair(xs[0], ys[0], nx[0], ny[0])
    let mut prev = first
    for i in 1..<n {
      prev = emitter.join_at(
        xs[i],
        ys[i],
        nx[i - 1],
        ny[i - 1],
        nx[i],
        ny[i],
        prev,
      )
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
        close_to=first,
      ),
    )
    return
  }
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
    prev = emitter.join_at(
      xs[i],
      ys[i],
      nx[i - 1],
      ny[i - 1],
      nx[i],
      ny[i],
      prev,
    )
  }
  let last = n - 1
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
    let dx = (self.xs[j] - self.xs[i]).to_double()
    let dy = (self.ys[j] - self.ys[i]).to_double()
    let len = (dx * dx + dy * dy).sqrt()
    self.nx.push(-dy / len)
    self.ny.push(dx / len)
  }
}

///|
priv struct Emitter {
  out : LineBuffers
  join : LineJoin
  miter_limit : Double
  round_limit : Double
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
/// Fills the outer arc around (x, y) from rim vertex `from` to rim vertex `to`
/// with `steps` triangles centered on `center`. Intermediate rim vertices are
/// the unit vector (vx, vy) at `from`, rotated by the step angle given as its
/// cosine `c` and sine `s` each time.
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
/// Emits the join at (x, y) between a segment with normal a and the next with
/// normal b, attaching the incoming segment from `prev`, and returns the pair
/// the outgoing segment starts from. Nearly straight joins share one pair;
/// otherwise the gap on the outer side is filled per `join`. `close_to` is the
/// already emitted outgoing pair when closing a ring.
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
    Bevel => miter <= 1.0 + STRAIGHT_EPSILON
    Round => miter < self.round_limit
  }
  if use_miter && close_to is None {
    let pair = self.pair(x, y, mx / mlen * miter, my / mlen * miter)
    self.quad(prev, pair)
    return pair
  }
  let end_pair = self.pair(x, y, ax, ay)
  self.quad(prev, end_pair)
  let start_pair = match close_to {
    Some(p) => p
    None => self.pair(x, y, bx, by)
  }
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
    let sweep = @math.atan2(cross, ax * bx + ay * by)
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
      @math.cos(step),
      @math.sin(step),
      steps,
      s,
    )
  } else {
    self.triangle(center, from, to)
  }
  start_pair
}
