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
  let k = @cmp.minimum(miter, MAX_MITER_LIMIT)
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
