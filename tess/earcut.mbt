// Port of earcut 3.2.4 (https://github.com/mapbox/earcut), ISC License,
// Copyright (c) 2026 Mapbox; see NOTICE. Operations follow src/earcut.js in
// order so triangles match exactly (no `refine`); nodes are parallel arrays.

///|
/// Polygon triangulator. Reuse one instance: its node pool and scratch
/// buffers keep their capacity between calls, so steady-state triangulation
/// does not allocate.
struct Earcut {
  mut nodes : Int32
  mut vi : FixedArray[Int32]
  mut xs : FixedArray[Double]
  mut ys : FixedArray[Double]
  mut prev : FixedArray[Int32]
  mut next : FixedArray[Int32]
  mut z : FixedArray[Int32]
  mut prev_z : FixedArray[Int32]
  mut next_z : FixedArray[Int32]
  mut steiner : FixedArray[Bool]
  mut has_steiners : Bool
  mut filtered_out : Bool
  mut index_active : Bool
  block_bbox : Array[Double]
  block_head : Array[Int32]
  block_stop : Array[Int32]
  sort_arr : Array[Int32]
  sort_buf : Array[Int32]
  z_arr : Array[Int32]
  z_buf : Array[Int32]
  counts : FixedArray[Int32]
  queue : Array[Int32]
}

///|
fn Earcut::new() -> Earcut {
  {
    nodes: 0,
    vi: [],
    xs: [],
    ys: [],
    prev: [],
    next: [],
    z: [],
    prev_z: [],
    next_z: [],
    steiner: [],
    has_steiners: false,
    filtered_out: false,
    index_active: false,
    block_bbox: [],
    block_head: [],
    block_stop: [],
    sort_arr: [],
    sort_buf: [],
    z_arr: [],
    z_buf: [],
    counts: FixedArray::make(256, 0),
    queue: [],
  }
}

///|
/// Above this many coordinates the z-order hash is used to find ears.
const HASH_THRESHOLD : Int32 = 80 * 2

///|
/// Triangulates the polygon whose vertices are the x, y pairs of `coords`;
/// holes start at the vertex indices in `hole_starts`. Appends the triangles
/// as vertex index triples to `out`.
fn Earcut::triangulate(
  self : Earcut,
  coords : ArrayView[Int32],
  hole_starts : ArrayView[Int32],
  out : Array[Int32],
) -> Unit {
  self.reset()
  let has_holes = hole_starts.length() > 0
  let outer_len = if has_holes { hole_starts[0] * 2 } else { coords.length() }
  let mut outer = self.linked_list(coords, 0, outer_len, true)
  if outer < 0 || self.next[outer] == self.prev[outer] {
    return
  }
  let mut min_x = 0.0
  let mut min_y = 0.0
  let mut inv_size = 0.0
  if has_holes {
    outer = self.eliminate_holes(coords, hole_starts, outer)
  }
  if coords.length() > HASH_THRESHOLD {
    min_x = coords[0].to_double()
    min_y = coords[1].to_double()
    let mut max_x = min_x
    let mut max_y = min_y
    for i = 2; i < outer_len; i = i + 2 {
      let x = coords[i].to_double()
      let y = coords[i + 1].to_double()
      if x < min_x {
        min_x = x
      }
      if y < min_y {
        min_y = y
      }
      if x > max_x {
        max_x = x
      }
      if y > max_y {
        max_y = y
      }
    }
    let size = @cmp.maximum(max_x - min_x, max_y - min_y)
    inv_size = if size != 0.0 { Z_RANGE / size } else { 0.0 }
  }
  self.earcut_linked(outer, out, min_x, min_y, inv_size)
}

///|
fn Earcut::reset(self : Earcut) -> Unit {
  self.nodes = 0
  self.has_steiners = false
}

///|
/// Doubles the node pool's capacity, keeping the first `nodes` entries.
fn Earcut::grow(self : Earcut) -> Unit {
  let cap = @cmp.maximum(64, self.vi.length() * 2)
  let n = self.nodes
  fn copy_int(a : FixedArray[Int32]) -> FixedArray[Int32] {
    let b = FixedArray::make(cap, 0)
    FixedArray::blit_to(a, b, len=n)
    b
  }
  let xs = FixedArray::make(cap, 0.0)
  let ys = FixedArray::make(cap, 0.0)
  let steiner = FixedArray::make(cap, false)
  FixedArray::blit_to(self.xs, xs, len=n)
  FixedArray::blit_to(self.ys, ys, len=n)
  FixedArray::blit_to(self.steiner, steiner, len=n)
  self.vi = copy_int(self.vi)
  self.prev = copy_int(self.prev)
  self.next = copy_int(self.next)
  self.z = copy_int(self.z)
  self.prev_z = copy_int(self.prev_z)
  self.next_z = copy_int(self.next_z)
  self.xs = xs
  self.ys = ys
  self.steiner = steiner
}

///|
fn Earcut::create_node(
  self : Earcut,
  i : Int32,
  x : Double,
  y : Double,
) -> Int32 {
  let p = self.nodes
  if p == self.vi.length() {
    self.grow()
  }
  self.nodes = p + 1
  self.vi[p] = i
  self.xs[p] = x
  self.ys[p] = y
  self.prev[p] = -1
  self.next[p] = -1
  self.z[p] = 0
  self.prev_z[p] = -1
  self.next_z[p] = -1
  self.steiner[p] = false
  p
}

///|
fn Earcut::insert_node(
  self : Earcut,
  i : Int32,
  x : Double,
  y : Double,
  last : Int32,
) -> Int32 {
  let p = self.create_node(i, x, y)
  if last < 0 {
    self.prev[p] = p
    self.next[p] = p
  } else {
    let ln = self.next[last]
    self.next[p] = ln
    self.prev[p] = last
    self.prev[ln] = p
    self.next[last] = p
  }
  p
}

///|
fn Earcut::remove_node(self : Earcut, p : Int32) -> Unit {
  let pp = self.prev[p]
  let pn = self.next[p]
  self.prev[pn] = pp
  self.next[pp] = pn
  let pz = self.prev_z[p]
  let nz = self.next_z[p]
  if pz >= 0 {
    self.next_z[pz] = nz
  }
  if nz >= 0 {
    self.prev_z[nz] = pz
  }
  if self.index_active {
    self.grow_block(pp, pn)
  }
}

///|
/// Signed area of triangle (p, q, r); negative for earcut's ear orientation.
fn Earcut::area(self : Earcut, p : Int32, q : Int32, r : Int32) -> Double {
  let xs = self.xs
  let ys = self.ys
  (ys[q] - ys[p]) * (xs[r] - xs[q]) - (xs[q] - xs[p]) * (ys[r] - ys[q])
}

///|
fn Earcut::equals(self : Earcut, a : Int32, b : Int32) -> Bool {
  self.xs[a] == self.xs[b] && self.ys[a] == self.ys[b]
}

///|
fn signed_area(data : ArrayView[Int32], start : Int32, end : Int32) -> Double {
  for i = start, j = end - 2, sum = 0.0; i < end; i = i + 2 {
    let d = (data[j].to_double() - data[i].to_double()) *
      (data[i + 1].to_double() + data[j + 1].to_double())
    continue i + 2, i, sum + d
  } nobreak {
    sum
  }
}

///|
/// Builds a circular list over `[start, end)` of `data` in the requested winding.
fn Earcut::linked_list(
  self : Earcut,
  data : ArrayView[Int32],
  start : Int32,
  end : Int32,
  clockwise : Bool,
) -> Int32 {
  let mut last = -1
  if clockwise == (signed_area(data, start, end) > 0.0) {
    for i = start; i < end; i = i + 2 {
      last = self.insert_node(
        i / 2,
        data[i].to_double(),
        data[i + 1].to_double(),
        last,
      )
    }
  } else {
    for i = end - 2; i >= start; i = i - 2 {
      last = self.insert_node(
        i / 2,
        data[i].to_double(),
        data[i + 1].to_double(),
        last,
      )
    }
  }
  if last >= 0 && self.equals(last, self.next[last]) {
    self.remove_node(last)
    last = self.next[last]
  }
  last
}

///|
/// Removes collinear or coincident points. With `end == start` the whole ring
/// is swept until nothing is removable; otherwise only up to `end`.
fn Earcut::filter_points(self : Earcut, start : Int32, end : Int32) -> Int32 {
  let full = end == start
  let mut end = end
  let mut p = start
  while true {
    let mut again = false
    let pn = self.next[p]
    if p != pn &&
      (!self.has_steiners || !self.steiner[p]) &&
      (self.equals(p, pn) || self.area(self.prev[p], p, pn) == 0.0) {
      if full || p == end {
        end = self.prev[p]
      }
      self.filtered_out = true
      self.remove_node(p)
      p = self.prev[p]
      again = true
    } else if full || p != end {
      p = pn
      again = !full
    }
    if !again && p == end {
      break
    }
  }
  end
}

///|
fn Earcut::earcut_linked(
  self : Earcut,
  ear : Int32,
  out : Array[Int32],
  min_x : Double,
  min_y : Double,
  inv_size : Double,
) -> Unit {
  if inv_size != 0.0 {
    self.index_curve(ear, min_x, min_y, inv_size)
  }
  let mut ear = ear
  let mut stop = ear
  let mut cured = false
  while self.prev[ear] != self.next[ear] {
    let prev = self.prev[ear]
    let next = self.next[ear]
    if self.area(prev, ear, next) < 0.0 &&
      (if inv_size != 0.0 {
        self.is_ear_hashed(ear, min_x, min_y, inv_size)
      } else {
        self.is_ear(ear)
      }) {
      out.push(self.vi[prev])
      out.push(self.vi[ear])
      out.push(self.vi[next])
      self.remove_node(ear)
      ear = next
      stop = next
      continue
    }
    ear = next
    if ear == stop {
      self.filtered_out = false
      ear = self.filter_points(ear, ear)
      if self.filtered_out {
        stop = ear
        continue
      }
      if !cured {
        ear = self.cure_local_intersections(ear, out)
        stop = ear
        cured = true
        continue
      }
      self.split_earcut(ear, out, min_x, min_y, inv_size)
      break
    }
  }
}

///|
fn point_in_triangle(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
  px : Double,
  py : Double,
) -> Bool {
  (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
  (ax - px) * (by - py) >= (bx - px) * (ay - py) &&
  (bx - px) * (cy - py) >= (cx - px) * (by - py)
}

///|
fn min3(a : Double, b : Double, c : Double) -> Double {
  @cmp.minimum(a, @cmp.minimum(b, c))
}

///|
fn max3(a : Double, b : Double, c : Double) -> Double {
  @cmp.maximum(a, @cmp.maximum(b, c))
}

///|
/// Whether `ear` is an ear; the reflex check is done by the caller.
fn Earcut::is_ear(self : Earcut, ear : Int32) -> Bool {
  let xs = self.xs
  let ys = self.ys
  let a = self.prev[ear]
  let c = self.next[ear]
  let (ax, bx, cx) = (xs[a], xs[ear], xs[c])
  let (ay, by, cy) = (ys[a], ys[ear], ys[c])
  let x0 = min3(ax, bx, cx)
  let y0 = min3(ay, by, cy)
  let x1 = max3(ax, bx, cx)
  let y1 = max3(ay, by, cy)
  let mut p = self.next[c]
  while p != a {
    let px = xs[p]
    let py = ys[p]
    if px >= x0 &&
      px <= x1 &&
      py >= y0 &&
      py <= y1 &&
      !(ax == px && ay == py) &&
      point_in_triangle(ax, ay, bx, by, cx, cy, px, py) &&
      self.area(self.prev[p], p, self.next[p]) >= 0.0 {
      return false
    }
    p = self.next[p]
  }
  true
}

///|
fn Earcut::is_ear_hashed(
  self : Earcut,
  ear : Int32,
  min_x : Double,
  min_y : Double,
  inv_size : Double,
) -> Bool {
  let xs = self.xs
  let ys = self.ys
  let a = self.prev[ear]
  let c = self.next[ear]
  let (ax, bx, cx) = (xs[a], xs[ear], xs[c])
  let (ay, by, cy) = (ys[a], ys[ear], ys[c])
  let x0 = min3(ax, bx, cx)
  let y0 = min3(ay, by, cy)
  let x1 = max3(ax, bx, cx)
  let y1 = max3(ay, by, cy)
  let min_z = z_order(x0, y0, min_x, min_y, inv_size)
  let max_z = z_order(x1, y1, min_x, min_y, inv_size)
  let mut p = self.prev_z[ear]
  while p >= 0 && self.z[p] >= min_z {
    let px = xs[p]
    let py = ys[p]
    if px >= x0 &&
      px <= x1 &&
      py >= y0 &&
      py <= y1 &&
      p != c &&
      !(ax == px && ay == py) &&
      point_in_triangle(ax, ay, bx, by, cx, cy, px, py) &&
      self.area(self.prev[p], p, self.next[p]) >= 0.0 {
      return false
    }
    p = self.prev_z[p]
  }
  let mut n = self.next_z[ear]
  while n >= 0 && self.z[n] <= max_z {
    let nx = xs[n]
    let ny = ys[n]
    if nx >= x0 &&
      nx <= x1 &&
      ny >= y0 &&
      ny <= y1 &&
      n != c &&
      !(ax == nx && ay == ny) &&
      point_in_triangle(ax, ay, bx, by, cx, cy, nx, ny) &&
      self.area(self.prev[n], n, self.next[n]) >= 0.0 {
      return false
    }
    n = self.next_z[n]
  }
  true
}

///|
fn Earcut::cure_local_intersections(
  self : Earcut,
  start : Int32,
  out : Array[Int32],
) -> Int32 {
  let mut start = start
  let mut p = start
  let mut cured = false
  while true {
    let a = self.prev[p]
    let b = self.next[self.next[p]]
    if self.intersects(a, p, self.next[p], b, false) &&
      self.locally_inside(a, b) &&
      self.locally_inside(b, a) {
      out.push(self.vi[a])
      out.push(self.vi[p])
      out.push(self.vi[b])
      self.remove_node(p)
      self.remove_node(self.next[p])
      p = b
      start = b
      cured = true
    }
    p = self.next[p]
    if p == start {
      break
    }
  }
  if cured {
    self.filter_points(p, p)
  } else {
    p
  }
}

///|
fn Earcut::split_earcut(
  self : Earcut,
  start : Int32,
  out : Array[Int32],
  min_x : Double,
  min_y : Double,
  inv_size : Double,
) -> Unit {
  let mut a = start
  while true {
    let mut b = self.next[self.next[a]]
    while b != self.prev[a] {
      if self.vi[a] != self.vi[b] && self.is_valid_diagonal(a, b) {
        let c = self.split_polygon(a, b)
        let a = self.filter_points(a, self.next[a])
        let c = self.filter_points(c, self.next[c])
        self.earcut_linked(a, out, min_x, min_y, inv_size)
        self.earcut_linked(c, out, min_x, min_y, inv_size)
        return
      }
      b = self.next[b]
    }
    a = self.next[a]
    if a == start {
      break
    }
  }
}

///|
fn Earcut::is_valid_diagonal(self : Earcut, a : Int32, b : Int32) -> Bool {
  let zero_length = self.equals(a, b) &&
    self.area(self.prev[a], a, self.next[a]) > 0.0 &&
    self.area(self.prev[b], b, self.next[b]) > 0.0
  self.vi[self.next[a]] != self.vi[b] &&
  (
    zero_length ||
    (
      self.locally_inside(a, b) &&
      self.locally_inside(b, a) &&
      (
        self.area(self.prev[a], a, self.prev[b]) != 0.0 ||
        self.area(a, self.prev[b], b) != 0.0
      )
    )
  ) &&
  !self.intersects_polygon(a, b) &&
  (zero_length || self.middle_inside(a, b))
}

///|
fn Earcut::intersects(
  self : Earcut,
  p1 : Int32,
  q1 : Int32,
  p2 : Int32,
  q2 : Int32,
  include_boundary : Bool,
) -> Bool {
  let o1 = self.area(p1, q1, p2)
  let o2 = self.area(p1, q1, q2)
  let o3 = self.area(p2, q2, p1)
  let o4 = self.area(p2, q2, q1)
  if ((o1 > 0.0 && o2 < 0.0) || (o1 < 0.0 && o2 > 0.0)) &&
    ((o3 > 0.0 && o4 < 0.0) || (o3 < 0.0 && o4 > 0.0)) {
    return true
  }
  if !include_boundary {
    return false
  }
  (o1 == 0.0 && self.on_segment(p1, p2, q1)) ||
  (o2 == 0.0 && self.on_segment(p1, q2, q1)) ||
  (o3 == 0.0 && self.on_segment(p2, p1, q2)) ||
  (o4 == 0.0 && self.on_segment(p2, q1, q2))
}

///|
/// For collinear p, q, r: whether q lies on segment pr.
fn Earcut::on_segment(self : Earcut, p : Int32, q : Int32, r : Int32) -> Bool {
  let xs = self.xs
  let ys = self.ys
  xs[q] <= @cmp.maximum(xs[p], xs[r]) &&
  xs[q] >= @cmp.minimum(xs[p], xs[r]) &&
  ys[q] <= @cmp.maximum(ys[p], ys[r]) &&
  ys[q] >= @cmp.minimum(ys[p], ys[r])
}

///|
fn Earcut::intersects_polygon(self : Earcut, a : Int32, b : Int32) -> Bool {
  let xs = self.xs
  let ys = self.ys
  let min_x = @cmp.minimum(xs[a], xs[b])
  let max_x = @cmp.maximum(xs[a], xs[b])
  let min_y = @cmp.minimum(ys[a], ys[b])
  let max_y = @cmp.maximum(ys[a], ys[b])
  let vi = self.vi
  let mut p = a
  while true {
    let n = self.next[p]
    let outside = (xs[p] > max_x && xs[n] > max_x) ||
      (xs[p] < min_x && xs[n] < min_x) ||
      (ys[p] > max_y && ys[n] > max_y) ||
      (ys[p] < min_y && ys[n] < min_y)
    if !outside &&
      vi[p] != vi[a] &&
      vi[n] != vi[a] &&
      vi[p] != vi[b] &&
      vi[n] != vi[b] &&
      self.intersects(p, n, a, b, true) {
      return true
    }
    p = n
    if p == a {
      break
    }
  }
  false
}

///|
fn Earcut::locally_inside(self : Earcut, a : Int32, b : Int32) -> Bool {
  let ap = self.prev[a]
  let an = self.next[a]
  if self.area(ap, a, an) < 0.0 {
    self.area(a, b, an) >= 0.0 && self.area(a, ap, b) >= 0.0
  } else {
    self.area(a, b, ap) < 0.0 || self.area(a, an, b) < 0.0
  }
}

///|
fn Earcut::middle_inside(self : Earcut, a : Int32, b : Int32) -> Bool {
  let xs = self.xs
  let ys = self.ys
  let px = (xs[a] + xs[b]) / 2.0
  let py = (ys[a] + ys[b]) / 2.0
  let mut inside = false
  let mut p = a
  while true {
    let n = self.next[p]
    if (ys[p] > py) != (ys[n] > py) &&
      px < (xs[n] - xs[p]) * (py - ys[p]) / (ys[n] - ys[p]) + xs[p] {
      inside = !inside
    }
    p = n
    if p == a {
      break
    }
  }
  inside
}

///|
/// Links a and b with a bridge: splits a ring in two, or merges a hole into
/// the outer ring. Returns b's duplicate.
fn Earcut::split_polygon(self : Earcut, a : Int32, b : Int32) -> Int32 {
  let a2 = self.create_node(self.vi[a], self.xs[a], self.ys[a])
  let b2 = self.create_node(self.vi[b], self.xs[b], self.ys[b])
  let an = self.next[a]
  let bp = self.prev[b]
  self.next[a] = b
  self.prev[b] = a
  self.next[a2] = an
  self.prev[an] = a2
  self.next[b2] = a2
  self.prev[a2] = b2
  self.next[bp] = b2
  self.prev[b2] = bp
  b2
}
