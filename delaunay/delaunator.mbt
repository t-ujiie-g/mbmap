// Ported from delaunator 5.1.0: ISC License, Copyright (c) 2021, Mapbox.
// See NOTICE.

///|
let epsilon : Double = 2.220446049250313e-16

///|
let edge_stack_size = 512

///|
/// delaunator's triangulation of finite x, y pairs: `triangles` (three point
/// indices each, counter-clockwise), `halfedges` (the twin of each half-edge
/// or -1) and `hull` (counter-clockwise).
priv struct Delaunator {
  coords : FixedArray[Double]
  mut triangles : FixedArray[Int32]
  mut halfedges : FixedArray[Int32]
  mut hull : FixedArray[Int32]
  tri_buf : FixedArray[Int32]
  half_buf : FixedArray[Int32]
  hash_size : Int32
  hull_prev : FixedArray[Int32]
  hull_next : FixedArray[Int32]
  hull_tri : FixedArray[Int32]
  hull_hash : FixedArray[Int32]
  ids : FixedArray[Int32]
  dists : FixedArray[Double]
  edge_stack : FixedArray[Int32]
  mut triangles_len : Int32
  mut cx : Double
  mut cy : Double
  mut hull_start : Int32
}

///|
fn Delaunator::new(coords : FixedArray[Double]) -> Delaunator {
  let n = coords.length() >> 1
  let max_triangles = if 2 * n - 5 > 0 { 2 * n - 5 } else { 0 }
  let d : Delaunator = {
    coords,
    triangles: [],
    halfedges: [],
    hull: [],
    tri_buf: FixedArray::make(max_triangles * 3, 0),
    half_buf: FixedArray::make(max_triangles * 3, 0),
    hash_size: n.to_double().sqrt().ceil().to_int(),
    hull_prev: FixedArray::make(n, 0),
    hull_next: FixedArray::make(n, 0),
    hull_tri: FixedArray::make(n, 0),
    hull_hash: FixedArray::make(n.to_double().sqrt().ceil().to_int(), 0),
    ids: FixedArray::make(n, 0),
    dists: FixedArray::make(n, 0.0),
    edge_stack: FixedArray::make(edge_stack_size, 0),
    triangles_len: 0,
    cx: 0.0,
    cy: 0.0,
    hull_start: 0,
  }
  d.update()
  d
}

///|
fn Delaunator::update(self : Delaunator) -> Unit {
  let coords = self.coords
  let hull_prev = self.hull_prev
  let hull_next = self.hull_next
  let hull_tri = self.hull_tri
  let hull_hash = self.hull_hash
  let n = coords.length() >> 1
  let mut min_x = @double.infinity
  let mut min_y = @double.infinity
  let mut max_x = @double.neg_infinity
  let mut max_y = @double.neg_infinity
  for i in 0..<n {
    let x = coords[2 * i]
    let y = coords[2 * i + 1]
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
    self.ids[i] = i
  }
  let cx = (min_x + max_x) / 2.0
  let cy = (min_y + max_y) / 2.0
  let mut i0 = 0
  let mut i1 = 0
  let mut i2 = 0
  let mut min_dist = @double.infinity
  for i in 0..<n {
    let d = dist(cx, cy, coords[2 * i], coords[2 * i + 1])
    if d < min_dist {
      i0 = i
      min_dist = d
    }
  }
  let i0x = coords.get(2 * i0).unwrap_or(0.0)
  let i0y = coords.get(2 * i0 + 1).unwrap_or(0.0)
  min_dist = @double.infinity
  for i in 0..<n {
    if i == i0 {
      continue
    }
    let d = dist(i0x, i0y, coords[2 * i], coords[2 * i + 1])
    if d < min_dist && d > 0.0 {
      i1 = i
      min_dist = d
    }
  }
  let mut i1x = coords.get(2 * i1).unwrap_or(0.0)
  let mut i1y = coords.get(2 * i1 + 1).unwrap_or(0.0)
  let mut min_radius = @double.infinity
  for i in 0..<n {
    if i == i0 || i == i1 {
      continue
    }
    let r = circumradius(i0x, i0y, i1x, i1y, coords[2 * i], coords[2 * i + 1])
    if r < min_radius {
      i2 = i
      min_radius = r
    }
  }
  let mut i2x = coords.get(2 * i2).unwrap_or(0.0)
  let mut i2y = coords.get(2 * i2 + 1).unwrap_or(0.0)
  if min_radius == @double.infinity {
    // Collinear points ordered by dx (or dy if all x are equal): hull only.
    for i in 0..<n {
      let dx = coords[2 * i] - coords[0]
      self.dists[i] = if dx != 0.0 && !dx.is_nan() {
        dx
      } else {
        coords[2 * i + 1] - coords[1]
      }
    }
    quicksort(self.ids, self.dists, 0, n - 1)
    let hull = FixedArray::make(n, 0)
    let mut j = 0
    let mut d0 = @double.neg_infinity
    for i in 0..<n {
      let id = self.ids[i]
      let d = self.dists[id]
      if d > d0 {
        hull[j] = id
        j += 1
        d0 = d
      }
    }
    self.hull = FixedArray::makei(j, k => hull[k])
    self.triangles = []
    self.halfedges = []
    return
  }
  if @robust.orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0.0 {
    let i = i1
    let x = i1x
    let y = i1y
    i1 = i2
    i1x = i2x
    i1y = i2y
    i2 = i
    i2x = x
    i2y = y
  }
  let (ccx, ccy) = circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
  self.cx = ccx
  self.cy = ccy
  for i in 0..<n {
    self.dists[i] = dist(coords[2 * i], coords[2 * i + 1], ccx, ccy)
  }
  quicksort(self.ids, self.dists, 0, n - 1)
  self.hull_start = i0
  let mut hull_size = 3
  hull_next[i0] = i1
  hull_prev[i2] = i1
  hull_next[i1] = i2
  hull_prev[i0] = i2
  hull_next[i2] = i0
  hull_prev[i1] = i0
  hull_tri[i0] = 0
  hull_tri[i1] = 1
  hull_tri[i2] = 2
  hull_hash.fill(-1)
  self.set_hash(i0x, i0y, i0)
  self.set_hash(i1x, i1y, i1)
  self.set_hash(i2x, i2y, i2)
  self.triangles_len = 0
  let _ = self.add_triangle(i0, i1, i2, -1, -1, -1)
  let mut xp = 0.0
  let mut yp = 0.0
  for k in 0..<n {
    let i = self.ids[k]
    let x = coords[2 * i]
    let y = coords[2 * i + 1]
    // Skip near-duplicate points.
    if k > 0 && (x - xp).abs() <= epsilon && (y - yp).abs() <= epsilon {
      continue
    }
    xp = x
    yp = y
    if i == i0 || i == i1 || i == i2 {
      continue
    }
    // delaunator reads its hash at a NaN key (a point at the seed
    // circumcenter) as undefined and adds a broken triangle; skip it instead.
    let key = self.hash_key(x, y)
    if key < 0 || self.triangles_len + 3 > self.tri_buf.length() {
      continue
    }
    let mut start = 0
    for j in 0..<self.hash_size {
      start = hull_hash[(key + j) % self.hash_size]
      if start != -1 && start != hull_next[start] {
        break
      }
    }
    if start < 0 {
      continue
    }
    start = hull_prev[start]
    let mut e = start
    let mut steps = 0
    for ;; {
      let q = hull_next[e]
      if @robust.orient2d(
          x,
          y,
          coords[2 * e],
          coords[2 * e + 1],
          coords[2 * q],
          coords[2 * q + 1],
        ) <
        0.0 {
        break
      }
      e = q
      steps += 1
      if e == start || steps > n {
        e = -1
        break
      }
    }
    if e == -1 {
      continue
    }
    let mut t = self.add_triangle(e, i, hull_next[e], -1, -1, hull_tri[e])
    hull_tri[i] = self.legalize(t + 2)
    hull_tri[e] = t
    hull_size += 1
    let mut m = hull_next[e]
    for ;; {
      let q = hull_next[m]
      if !(@robust.orient2d(
          x,
          y,
          coords[2 * m],
          coords[2 * m + 1],
          coords[2 * q],
          coords[2 * q + 1],
        ) <
        0.0) ||
        self.triangles_len + 3 > self.tri_buf.length() {
        break
      }
      t = self.add_triangle(m, i, q, hull_tri[i], -1, hull_tri[m])
      hull_tri[i] = self.legalize(t + 2)
      hull_next[m] = m
      hull_size -= 1
      m = q
    }
    if e == start {
      for ;; {
        let q = hull_prev[e]
        if !(@robust.orient2d(
            x,
            y,
            coords[2 * q],
            coords[2 * q + 1],
            coords[2 * e],
            coords[2 * e + 1],
          ) <
          0.0) ||
          self.triangles_len + 3 > self.tri_buf.length() {
          break
        }
        t = self.add_triangle(q, i, e, -1, hull_tri[e], hull_tri[q])
        let _ = self.legalize(t + 2)
        hull_tri[q] = t
        hull_next[e] = e
        hull_size -= 1
        e = q
      }
    }
    self.hull_start = e
    hull_prev[i] = e
    hull_next[e] = i
    hull_prev[m] = i
    hull_next[i] = m
    self.set_hash(x, y, i)
    self.set_hash(coords[2 * e], coords[2 * e + 1], e)
  }
  let hull_size = if hull_size > n { n } else { hull_size }
  let hull = FixedArray::make(hull_size, 0)
  let mut e = self.hull_start
  for i in 0..<hull_size {
    hull[i] = e
    e = hull_next[e]
  }
  self.hull = hull
  let len = self.triangles_len
  self.triangles = FixedArray::makei(len, k => self.tri_buf[k])
  self.halfedges = FixedArray::makei(len, k => self.half_buf[k])
}

///|
/// The edge hash bucket of a point, or -1 where delaunator's is NaN.
fn Delaunator::hash_key(self : Delaunator, x : Double, y : Double) -> Int32 {
  let a = pseudo_angle(x - self.cx, y - self.cy)
  let k = (a * self.hash_size.to_double()).floor()
  if k.is_nan() || k < 0.0 || k > 2147483647.0 {
    -1
  } else {
    k.to_int() % self.hash_size
  }
}

///|
fn Delaunator::set_hash(
  self : Delaunator,
  x : Double,
  y : Double,
  i : Int32,
) -> Unit {
  let k = self.hash_key(x, y)
  if k >= 0 {
    self.hull_hash[k] = i
  }
}

///|
/// Flips edges from `a` until the Delaunay condition holds; a step cap stops
/// floating-point flip cycles.
fn Delaunator::legalize(self : Delaunator, a0 : Int32) -> Int32 {
  let triangles = self.tri_buf
  let halfedges = self.half_buf
  let coords = self.coords
  let mut a = a0
  let mut i = 0
  let mut ar = 0
  let max_steps = 4 * self.ids.length() + 64
  for steps = 0; steps < max_steps; steps = steps + 1 {
    let b = halfedges[a]
    let a0 = a - a % 3
    ar = a0 + (a + 2) % 3
    if b == -1 {
      if i == 0 {
        break
      }
      i -= 1
      a = self.edge_stack[i]
      continue
    }
    let b0 = b - b % 3
    let al = a0 + (a + 1) % 3
    let bl = b0 + (b + 2) % 3
    let p0 = triangles[ar]
    let pr = triangles[a]
    let pl = triangles[al]
    let p1 = triangles[bl]
    let illegal = in_circle(
      coords[2 * p0],
      coords[2 * p0 + 1],
      coords[2 * pr],
      coords[2 * pr + 1],
      coords[2 * pl],
      coords[2 * pl + 1],
      coords[2 * p1],
      coords[2 * p1 + 1],
    )
    if illegal {
      triangles[a] = p1
      triangles[b] = p0
      let hbl = halfedges[bl]
      // An edge swapped on the other side of the hull: fix the reference.
      if hbl == -1 {
        let mut e = self.hull_start
        for _ in 0..<self.ids.length() {
          if self.hull_tri[e] == bl {
            self.hull_tri[e] = a
            break
          }
          e = self.hull_prev[e]
          if e == self.hull_start {
            break
          }
        }
      }
      self.link(a, hbl)
      self.link(b, halfedges[ar])
      self.link(ar, bl)
      let br = b0 + (b + 1) % 3
      if i < edge_stack_size {
        self.edge_stack[i] = br
        i += 1
      }
    } else {
      if i == 0 {
        break
      }
      i -= 1
      a = self.edge_stack[i]
    }
  }
  ar
}

///|
fn Delaunator::link(self : Delaunator, a : Int32, b : Int32) -> Unit {
  self.half_buf[a] = b
  if b != -1 {
    self.half_buf[b] = a
  }
}

///|
fn Delaunator::add_triangle(
  self : Delaunator,
  i0 : Int32,
  i1 : Int32,
  i2 : Int32,
  a : Int32,
  b : Int32,
  c : Int32,
) -> Int32 {
  let t = self.triangles_len
  self.tri_buf[t] = i0
  self.tri_buf[t + 1] = i1
  self.tri_buf[t + 2] = i2
  self.link(t, a)
  self.link(t + 1, b)
  self.link(t + 2, c)
  self.triangles_len += 3
  t
}

///|
/// Monotonic in the angle of `dx, dy`, in [0, 1], without trigonometry.
fn pseudo_angle(dx : Double, dy : Double) -> Double {
  let p = dx / (dx.abs() + dy.abs())
  (if dy > 0.0 { 3.0 - p } else { 1.0 + p }) / 4.0
}

///|
fn dist(ax : Double, ay : Double, bx : Double, by : Double) -> Double {
  let dx = ax - bx
  let dy = ay - by
  dx * dx + dy * dy
}

///|
fn in_circle(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
  px : Double,
  py : Double,
) -> Bool {
  let dx = ax - px
  let dy = ay - py
  let ex = bx - px
  let ey = by - py
  let fx = cx - px
  let fy = cy - py
  let ap = dx * dx + dy * dy
  let bp = ex * ex + ey * ey
  let cp = fx * fx + fy * fy
  dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) <
  0.0
}

///|
fn circumradius(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> Double {
  let dx = bx - ax
  let dy = by - ay
  let ex = cx - ax
  let ey = cy - ay
  let bl = dx * dx + dy * dy
  let cl = ex * ex + ey * ey
  let d = 0.5 / (dx * ey - dy * ex)
  let x = (ey * bl - dy * cl) * d
  let y = (dx * cl - ex * bl) * d
  x * x + y * y
}

///|
fn circumcenter(
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
  cx : Double,
  cy : Double,
) -> (Double, Double) {
  let dx = bx - ax
  let dy = by - ay
  let ex = cx - ax
  let ey = cy - ay
  let bl = dx * dx + dy * dy
  let cl = ex * ex + ey * ey
  let d = 0.5 / (dx * ey - dy * ex)
  (ax + (ey * bl - dy * cl) * d, ay + (dx * cl - ex * bl) * d)
}

///|
/// delaunator's sort of point indices by distance. The ranges sorted are
/// disjoint, so recursing on the smaller side only keeps its result and bounds
/// the stack.
fn quicksort(
  ids : FixedArray[Int32],
  dists : FixedArray[Double],
  left0 : Int32,
  right0 : Int32,
) -> Unit {
  let mut left = left0
  let mut right = right0
  while right - left > 20 {
    let median = (left + right) >> 1
    let mut i = left + 1
    let mut j = right
    swap(ids, median, i)
    if dists[ids[left]] > dists[ids[right]] {
      swap(ids, left, right)
    }
    if dists[ids[i]] > dists[ids[right]] {
      swap(ids, i, right)
    }
    if dists[ids[left]] > dists[ids[i]] {
      swap(ids, left, i)
    }
    let temp = ids[i]
    let temp_dist = dists[temp]
    for ;; {
      i += 1
      while dists[ids[i]] < temp_dist {
        i += 1
      }
      j -= 1
      while dists[ids[j]] > temp_dist {
        j -= 1
      }
      if j < i {
        break
      }
      swap(ids, i, j)
    }
    ids[left + 1] = ids[j]
    ids[j] = temp
    if right - i + 1 >= j - left {
      quicksort(ids, dists, left, j - 1)
      left = i
    } else {
      quicksort(ids, dists, i, right)
      right = j - 1
    }
  }
  for i in (left + 1)..<=right {
    let temp = ids[i]
    let temp_dist = dists[temp]
    let mut j = i - 1
    while j >= left && dists[ids[j]] > temp_dist {
      ids[j + 1] = ids[j]
      j -= 1
    }
    ids[j + 1] = temp
  }
}

///|
fn swap(arr : FixedArray[Int32], i : Int32, j : Int32) -> Unit {
  let tmp = arr[i]
  arr[i] = arr[j]
  arr[j] = tmp
}
