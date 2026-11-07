// Ported from concaveman 2.0.0 (ISC, (c) 2025 Mapbox), tinyqueue 3.0.0 (ISC,
// (c) 2017 Vladimir Agafonkin) and point-in-polygon 1.1.0 (MIT, (c) 2016 James
// Halliday); see NOTICE.

///|
/// What `findCandidate`'s queue holds: an rbush node or a point.
priv enum Entry {
  Tree(Node)
  Pt(Int32)
}

///|
/// tinyqueue 3.0.0's binary heap, ordered by `dist[a] - dist[b]`.
priv struct Queue {
  entries : Array[Entry]
  dists : Array[Double]
}

///|
fn Queue::push(self : Queue, e : Entry, dist : Double) -> Unit {
  self.entries.push(e)
  self.dists.push(dist)
  let mut pos = self.entries.length() - 1
  while pos > 0 {
    let parent = (pos - 1) >> 1
    if dist - self.dists[parent] >= 0.0 {
      break
    }
    self.entries[pos] = self.entries[parent]
    self.dists[pos] = self.dists[parent]
    pos = parent
  }
  self.entries[pos] = e
  self.dists[pos] = dist
}

///|
fn Queue::pop(self : Queue) -> (Entry, Double)? {
  let n = self.entries.length()
  if n == 0 {
    return None
  }
  let top = (self.entries[0], self.dists[0])
  let bottom = self.entries.unsafe_pop()
  let bottom_dist = self.dists.unsafe_pop()
  let len = n - 1
  if len > 0 {
    let half = len >> 1
    let mut pos = 0
    while pos < half {
      let mut best = (pos << 1) + 1
      let right = best + 1
      if right < len && self.dists[right] - self.dists[best] < 0.0 {
        best = right
      }
      if self.dists[best] - bottom_dist >= 0.0 {
        break
      }
      self.entries[pos] = self.entries[best]
      self.dists[pos] = self.dists[best]
      pos = best
    }
    self.entries[pos] = bottom
    self.dists[pos] = bottom_dist
  }
  Some(top)
}

///|
/// The points and the doubly linked hull concaveman builds over them; list
/// node `k` stands at point `node_p[k]` with its edge's box in `boxes`.
priv struct Hull {
  xs : Array[Double]
  ys : Array[Double]
  node_p : Array[Int32]
  prev : Array[Int32]
  next : Array[Int32]
  boxes : Array[Double]
}

///|
fn Hull::cross(self : Hull, p1 : Int32, p2 : Int32, p3 : Int32) -> Double {
  @robust.orient2d(
    self.xs[p1],
    self.ys[p1],
    self.xs[p2],
    self.ys[p2],
    self.xs[p3],
    self.ys[p3],
  )
}

///|
/// concaveman's `insertNode`: a new list node at point `p` after `prev`.
fn Hull::insert_node(self : Hull, p : Int32, prev : Int32?) -> Int32 {
  let node = self.node_p.length()
  self.node_p.push(p)
  for _ in 0..<4 {
    self.boxes.push(0.0)
  }
  match prev {
    None => {
      self.prev.push(node)
      self.next.push(node)
    }
    Some(prev) => {
      self.next.push(self.next[prev])
      self.prev.push(prev)
      self.prev[self.next[prev]] = node
      self.next[prev] = node
    }
  }
  node
}

///|
fn Hull::update_box(self : Hull, node : Int32) -> Int32 {
  let p1 = self.node_p[node]
  let p2 = self.node_p[self.next[node]]
  self.boxes[4 * node] = js_min(self.xs[p1], self.xs[p2])
  self.boxes[4 * node + 1] = js_min(self.ys[p1], self.ys[p2])
  self.boxes[4 * node + 2] = js_max(self.xs[p1], self.xs[p2])
  self.boxes[4 * node + 3] = js_max(self.ys[p1], self.ys[p2])
  node
}

///|
fn Hull::sq_dist(self : Hull, p1 : Int32, p2 : Int32) -> Double {
  let dx = self.xs[p1] - self.xs[p2]
  let dy = self.ys[p1] - self.ys[p2]
  dx * dx + dy * dy
}

///|
/// Square distance from point `p` to the segment `p1`, `p2`.
fn Hull::sq_seg_dist(self : Hull, p : Int32, p1 : Int32, p2 : Int32) -> Double {
  let mut x = self.xs[p1]
  let mut y = self.ys[p1]
  let mut dx = self.xs[p2] - x
  let mut dy = self.ys[p2] - y
  if dx != 0.0 || dy != 0.0 {
    let t = ((self.xs[p] - x) * dx + (self.ys[p] - y) * dy) /
      (dx * dx + dy * dy)
    if t > 1.0 {
      x = self.xs[p2]
      y = self.ys[p2]
    } else if t > 0.0 {
      x += dx * t
      y += dy * t
    }
  }
  dx = self.xs[p] - x
  dy = self.ys[p] - y
  dx * dx + dy * dy
}

///|
/// Square distance between segments (x0, y0)-(x1, y1) and (x2, y2)-(x3, y3),
/// Dan Sunday's, as concaveman writes it.
fn sq_seg_seg_dist(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  x3 : Double,
  y3 : Double,
) -> Double {
  let ux = x1 - x0
  let uy = y1 - y0
  let vx = x3 - x2
  let vy = y3 - y2
  let wx = x0 - x2
  let wy = y0 - y2
  let a = ux * ux + uy * uy
  let b = ux * vx + uy * vy
  let c = vx * vx + vy * vy
  let d = ux * wx + uy * wy
  let e = vx * wx + vy * wy
  let dd = a * c - b * b
  let mut s_n = 0.0
  let mut t_n = 0.0
  let mut s_d = dd
  let mut t_d = dd
  if dd == 0.0 {
    s_n = 0.0
    s_d = 1.0
    t_n = e
    t_d = c
  } else {
    s_n = b * e - c * d
    t_n = a * e - b * d
    if s_n < 0.0 {
      s_n = 0.0
      t_n = e
      t_d = c
    } else if s_n > s_d {
      s_n = s_d
      t_n = e + b
      t_d = c
    }
  }
  if t_n < 0.0 {
    t_n = 0.0
    if -d < 0.0 {
      s_n = 0.0
    } else if -d > a {
      s_n = s_d
    } else {
      s_n = -d
      s_d = a
    }
  } else if t_n > t_d {
    t_n = t_d
    if -d + b < 0.0 {
      s_n = 0.0
    } else if -d + b > a {
      s_n = s_d
    } else {
      s_n = -d + b
      s_d = a
    }
  }
  let sc = if s_n == 0.0 { 0.0 } else { s_n / s_d }
  let tc = if t_n == 0.0 { 0.0 } else { t_n / t_d }
  let cx = (1.0 - sc) * x0 + sc * x1
  let cy = (1.0 - sc) * y0 + sc * y1
  let cx2 = (1.0 - tc) * x2 + tc * x3
  let cy2 = (1.0 - tc) * y2 + tc * y3
  let dx = cx2 - cx
  let dy = cy2 - cy
  dx * dx + dy * dy
}

///|
fn inside(x : Double, y : Double, b : Node) -> Bool {
  x >= b.min_x && x <= b.max_x && y >= b.min_y && y <= b.max_y
}

///|
/// Square distance from the segment `a`, `b` to the box of `n`.
fn Hull::sq_seg_box_dist(self : Hull, a : Int32, b : Int32, n : Node) -> Double {
  let ax = self.xs[a]
  let ay = self.ys[a]
  let bx = self.xs[b]
  let by = self.ys[b]
  if inside(ax, ay, n) || inside(bx, by, n) {
    return 0.0
  }
  let d1 = sq_seg_seg_dist(ax, ay, bx, by, n.min_x, n.min_y, n.max_x, n.min_y)
  if d1 == 0.0 {
    return 0.0
  }
  let d2 = sq_seg_seg_dist(ax, ay, bx, by, n.min_x, n.min_y, n.min_x, n.max_y)
  if d2 == 0.0 {
    return 0.0
  }
  let d3 = sq_seg_seg_dist(ax, ay, bx, by, n.max_x, n.min_y, n.max_x, n.max_y)
  if d3 == 0.0 {
    return 0.0
  }
  let d4 = sq_seg_seg_dist(ax, ay, bx, by, n.min_x, n.max_y, n.max_x, n.max_y)
  if d4 == 0.0 {
    return 0.0
  }
  js_min(js_min(js_min(d1, d2), d3), d4)
}

///|
/// Whether the edges `p1`-`q1` and `p2`-`q2` cross (points by identity).
fn Hull::edges_cross(
  self : Hull,
  p1 : Int32,
  q1 : Int32,
  p2 : Int32,
  q2 : Int32,
) -> Bool {
  p1 != q2 &&
  q1 != p2 &&
  (self.cross(p1, q1, p2) > 0.0) != (self.cross(p1, q1, q2) > 0.0) &&
  (self.cross(p2, q2, p1) > 0.0) != (self.cross(p2, q2, q1) > 0.0)
}

///|
/// Whether the edge `a`-`b` crosses no edge of the hull.
fn Hull::no_intersections(
  self : Hull,
  a : Int32,
  b : Int32,
  seg_tree : RBush,
) -> Bool {
  let bbox = {
    min_x: js_min(self.xs[a], self.xs[b]),
    min_y: js_min(self.ys[a], self.ys[b]),
    max_x: js_max(self.xs[a], self.xs[b]),
    max_y: js_max(self.ys[a], self.ys[b]),
  }
  !seg_tree.search_any(bbox, e => {
    self.edges_cross(self.node_p[e], self.node_p[self.next[e]], a, b)
  })
}

///|
fn Hull::find_candidate(
  self : Hull,
  tree : RBush,
  a : Int32,
  b : Int32,
  c : Int32,
  d : Int32,
  max_dist : Double,
  seg_tree : RBush,
) -> Int32? {
  let queue : Queue = { entries: [], dists: [], }
  let mut node = Some(tree.data)
  while node is Some(n) {
    if n.leaf {
      for p in n.items {
        let dist = self.sq_seg_dist(p, b, c)
        if !(dist > max_dist) {
          queue.push(Pt(p), dist)
        }
      }
    } else {
      for child in n.nodes {
        let dist = self.sq_seg_box_dist(b, c, child)
        if !(dist > max_dist) {
          queue.push(Tree(child), dist)
        }
      }
    }
    while queue.entries.length() > 0 && queue.entries[0] is Pt(_) {
      guard queue.pop() is Some((Pt(p), dist)) else { break }
      let d0 = self.sq_seg_dist(p, a, b)
      let d1 = self.sq_seg_dist(p, c, d)
      if dist < d0 &&
        dist < d1 &&
        self.no_intersections(b, p, seg_tree) &&
        self.no_intersections(c, p, seg_tree) {
        return Some(p)
      }
    }
    node = match queue.pop() {
      Some((Tree(t), _)) => Some(t)
      _ => None
    }
  }
  None
}

///|
/// point-in-polygon 1.1.0's `nested`: whether point `p` is inside `vs`.
fn Hull::point_in_polygon(self : Hull, p : Int32, vs : Array[Int32]) -> Bool {
  let x = self.xs[p]
  let y = self.ys[p]
  let mut in_ = false
  let len = vs.length()
  let mut j = len - 1
  for i in 0..<len {
    let xi = self.xs[vs[i]]
    let yi = self.ys[vs[i]]
    let xj = self.xs[vs[j]]
    let yj = self.ys[vs[j]]
    if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
      in_ = !in_
    }
    j = i
  }
  in_
}

///|
/// concaveman's `fastConvexHull` over points 0 to n - 1.
fn Hull::fast_convex_hull(self : Hull, n : Int32) -> Array[Int32] {
  let mut left = 0
  let mut top = 0
  let mut right = 0
  let mut bottom = 0
  for i in 0..<n {
    if self.xs[i] < self.xs[left] {
      left = i
    }
    if self.xs[i] > self.xs[right] {
      right = i
    }
    if self.ys[i] < self.ys[top] {
      top = i
    }
    if self.ys[i] > self.ys[bottom] {
      bottom = i
    }
  }
  let cull = [left, top, right, bottom]
  let filtered = cull.copy()
  for i in 0..<n {
    if !self.point_in_polygon(i, cull) {
      filtered.push(i)
    }
  }
  self.convex_hull(filtered)
}

///|
fn Hull::convex_hull(self : Hull, points : Array[Int32]) -> Array[Int32] {
  stable_sort(points, (a, b) => {
    if self.xs[a] == self.xs[b] {
      self.ys[a] - self.ys[b]
    } else {
      self.xs[a] - self.xs[b]
    }
  })
  let lower : Array[Int32] = []
  for p in points {
    while lower.length() >= 2 &&
          self.cross(lower[lower.length() - 2], lower[lower.length() - 1], p) <=
          0.0 {
      lower.unsafe_pop() |> ignore
    }
    lower.push(p)
  }
  let upper : Array[Int32] = []
  for i = points.length() - 1; i >= 0; i = i - 1 {
    let p = points[i]
    while upper.length() >= 2 &&
          self.cross(upper[upper.length() - 2], upper[upper.length() - 1], p) <=
          0.0 {
      upper.unsafe_pop() |> ignore
    }
    upper.push(p)
  }
  upper.unsafe_pop() |> ignore
  lower.unsafe_pop() |> ignore
  lower.append(upper)
  lower
}

///|
/// concaveman 2.0.0 over the points `xs`, `ys` (at least one): the hull's
/// points, closed (the first again at the end).
fn concaveman(
  xs : Array[Double],
  ys : Array[Double],
  concavity : Double,
  length_threshold : Double,
  trig : @core.Trig,
) -> Array[Int32] {
  let n = xs.length()
  let concavity = js_max(0.0, concavity)
  let length_threshold = if length_threshold.is_nan() {
    0.0
  } else {
    length_threshold
  }
  let h : Hull = { xs, ys, node_p: [], prev: [], next: [], boxes: [], }
  let hull = h.fast_convex_hull(n)
  let point_boxes = Array::make(4 * n, 0.0)
  for i in 0..<n {
    point_boxes[4 * i] = xs[i]
    point_boxes[4 * i + 1] = ys[i]
    point_boxes[4 * i + 2] = xs[i]
    point_boxes[4 * i + 3] = ys[i]
  }
  let tree = RBush::new(16, point_boxes, trig)
  tree.load(Array::makei(n, i => i))
  let queue : Array[Int32] = []
  let mut last : Int32? = None
  for p in hull {
    tree.remove(p) |> ignore
    last = Some(h.insert_node(p, last))
    queue.push(last.unwrap())
  }
  let seg_tree = RBush::new(16, h.boxes, trig)
  for node in queue {
    seg_tree.insert(h.update_box(node))
  }
  let sq_concavity = concavity * concavity
  let sq_len_threshold = length_threshold * length_threshold
  // Every point joins at most once; the cap stops input that would make
  // concaveman find a point it cannot remove from the tree again.
  let mut joined = 0
  let mut head = 0
  while head < queue.length() && joined <= n {
    let node = queue[head]
    head += 1
    let a = h.node_p[node]
    let b = h.node_p[h.next[node]]
    let sq_len = h.sq_dist(a, b)
    if sq_len < sq_len_threshold {
      continue
    }
    let max_sq_len = sq_len / sq_concavity
    let candidate = h.find_candidate(
      tree,
      h.node_p[h.prev[node]],
      a,
      b,
      h.node_p[h.next[h.next[node]]],
      max_sq_len,
      seg_tree,
    )
    if candidate is Some(p) &&
      js_min(h.sq_dist(p, a), h.sq_dist(p, b)) <= max_sq_len {
      queue.push(node)
      queue.push(h.insert_node(p, Some(node)))
      tree.remove(p) |> ignore
      seg_tree.remove(node) |> ignore
      seg_tree.insert(h.update_box(node))
      seg_tree.insert(h.update_box(h.next[node]))
      joined += 1
    }
  }
  let out = []
  guard last is Some(last) else { return out }
  let mut node = last
  while true {
    out.push(h.node_p[node])
    node = h.next[node]
    if node == last {
      break
    }
  }
  out.push(h.node_p[node])
  out
}
