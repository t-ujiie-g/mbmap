///|
/// A phantom vertex's edges (`compactNode` with `trackIncoming`), each with
/// the vertices walked to its end.
priv struct Phantom {
  ends : Array[Int32]
  weights : Array[Double]
  walks : Array[Array[Int32]]
}

///|
/// The vertex whose key `(x, y)` has, or -1.
fn Network::vertex_at(self : Network, x : Double, y : Double) -> Int32 {
  self.keys.get(key_bits(x, self.tolerance), key_bits(y, self.tolerance))
}

///|
/// `findNextFork(prev, v)`: the fork reached, the weight (incoming too: edges
/// weigh the same both ways) and the vertices passed. None for a walk with no
/// way on or a loop, which cannot happen: compaction leaves a fork on each loop.
fn Network::walk(
  self : Network,
  prev : Int32,
  v : Int32,
  weight : Double,
) -> (Int32, Double, Array[Int32])? {
  let mut prev = prev
  let mut v = v
  let mut weight = weight
  let passed = []
  while !self.in_compacted[v] {
    let mut next = -1
    for s in self.starts[v]..<self.starts[v + 1] {
      if self.nbrs[s] != prev {
        next = s
        break
      }
    }
    if next < 0 || passed.length() >= self.xs.length() {
      return None
    }
    weight += self.weights[next]
    passed.push(v)
    prev = v
    v = self.nbrs[next]
  }
  Some((v, weight, passed))
}

///|
/// `compactNode(n)`: the first lightest walk to each fork around `n`.
fn Network::phantom(self : Network, n : Int32) -> Phantom? {
  let p = { ends: [], weights: [], walks: [], }
  for s in self.starts[n]..<self.starts[n + 1] {
    guard self.walk(n, self.nbrs[s], self.weights[s]) is Some((end, w, passed)) else {
      return None
    }
    if end == n {
      continue
    }
    match p.ends.search(end) {
      None => {
        p.ends.push(end)
        p.weights.push(w)
        p.walks.push(passed)
      }
      Some(i) =>
        if p.weights[i] > w {
          p.weights[i] = w
          p.walks[i] = passed
        }
    }
  }
  Some(p)
}

///|
/// `_createPhantom(n)` for a vertex outside the compacted graph.
fn Network::add_phantom(self : Network, n : Int32, p : Phantom) -> Unit {
  self.in_compacted[n] = true
  for i, end in p.ends {
    self.put(n, end, p.weights[i], Run([n, ..p.walks[i]]))
  }
  for i, end in p.ends {
    let back = [end]
    for k = p.walks[i].length() - 1; k >= 0; k = k - 1 {
      back.push(p.walks[i][k])
    }
    self.put(end, n, p.weights[i], Run(back))
  }
}

///|
/// `_removePhantom(n)`.
fn Network::remove_phantom(self : Network, n : Int32) -> Unit {
  for end in self.compacted_neighbors(n) {
    self.unlink(end, n)
  }
  self.drop_vertex(n)
}

///|
/// tinyqueue 2.0.3's `_up` over state indices compared by cost.
fn sift_up(heap : Array[Int32], cost : Array[Double], pos : Int32) -> Unit {
  let item = heap[pos]
  let mut pos = pos
  while pos > 0 {
    let parent = (pos - 1) >> 1
    let current = heap[parent]
    if cost[item] - cost[current] >= 0.0 {
      break
    }
    heap[pos] = current
    pos = parent
  }
  heap[pos] = item
}

///|
/// tinyqueue 2.0.3's `_down`.
fn sift_down(heap : Array[Int32], cost : Array[Double], pos : Int32) -> Unit {
  let length = heap.length()
  let half = length >> 1
  let item = heap[pos]
  let mut pos = pos
  while pos < half {
    let mut left = (pos << 1) + 1
    let mut best = heap[left]
    let right = left + 1
    if right < length && cost[heap[right]] - cost[best] < 0.0 {
      left = right
      best = heap[right]
    }
    if cost[best] - cost[item] >= 0.0 {
      break
    }
    heap[pos] = best
    pos = left
  }
  heap[pos] = item
}

///|
/// tinyqueue 2.0.3's `pop`, or -1.
fn pop(heap : Array[Int32], cost : Array[Double]) -> Int32 {
  guard heap.pop() is Some(bottom) else { return -1 }
  if heap.is_empty() {
    return bottom
  }
  let top = heap[0]
  heap[0] = bottom
  sift_down(heap, cost, 0)
  top
}

///|
/// geojson-path-finder's `findPath` (Dijkstra) over the compacted graph: the
/// vertices along the path and its weight. A state popped after a cheaper one
/// of its vertex is skipped: the JavaScript expands it but can push nothing.
fn Network::dijkstra(
  self : Network,
  start : Int32,
  finish : Int32,
) -> (Array[Int32], Double)? {
  let cost = [0.0]
  let node = [start]
  let parent = [-1]
  let heap = [0]
  let touched = [start]
  self.costs[start] = 0.0
  let mut found = -1
  while true {
    let state = pop(heap, cost)
    if state < 0 {
      break
    }
    let v = node[state]
    if v == finish {
      found = state
      break
    }
    let c = cost[state]
    if c > self.costs[v] {
      continue
    }
    let mut s = self.head[v]
    while s >= 0 {
      let n = self.slot_nbr[s]
      let new_cost = c + self.slot_weight[s]
      if new_cost < self.costs[n] {
        if self.costs[n] == @double.infinity {
          touched.push(n)
        }
        self.costs[n] = new_cost
        cost.push(new_cost)
        node.push(n)
        parent.push(state)
        heap.push(cost.length() - 1)
        sift_up(heap, cost, heap.length() - 1)
      }
      s = self.slot_next[s]
    }
  }
  for v in touched {
    self.costs[v] = @double.infinity
  }
  guard found >= 0 else { return None }
  let path = []
  let mut s = found
  while s >= 0 {
    path.push(node[s])
    s = parent[s]
  }
  path.rev_in_place()
  Some((path, cost[found]))
}

///|
/// `findPath(point(from), point(to))`: the path's coordinates and weight in km,
/// or None where it gives undefined (an end off the network, or no path). The
/// network is left as it was, as the JavaScript leaves it.
pub fn Network::find_path(
  self : Network,
  from_x : Double,
  from_y : Double,
  to_x : Double,
  to_y : Double,
) -> (Array[(Double, Double)], Double)? {
  let start = self.vertex_at(from_x, from_y)
  let finish = self.vertex_at(to_x, to_y)
  guard start >= 0 &&
    finish >= 0 &&
    self.starts[start + 1] > self.starts[start] &&
    self.starts[finish + 1] > self.starts[finish] else {
    return None
  }
  let with_start = !self.in_compacted[start]
  if with_start {
    guard self.phantom(start) is Some(p) else { return None }
    self.add_phantom(start, p)
  }
  let with_finish = !self.in_compacted[finish]
  let ok = if with_finish {
    match self.phantom(finish) {
      Some(p) => {
        self.add_phantom(finish, p)
        true
      }
      None => false
    }
  } else {
    true
  }
  let result = if ok { self.collect(start, finish) } else { None }
  if with_start {
    self.remove_phantom(start)
  }
  if with_finish && ok {
    self.remove_phantom(finish)
  }
  self.slot_nbr.truncate(self.base_slots)
  self.slot_weight.truncate(self.base_slots)
  self.slot_seq.truncate(self.base_slots)
  self.slot_next.truncate(self.base_slots)
  self.slot_prev.truncate(self.base_slots)
  result
}

///|
/// The path found between the phantoms, with `compactedCoordinates` joined.
fn Network::collect(
  self : Network,
  start : Int32,
  finish : Int32,
) -> (Array[(Double, Double)], Double)? {
  guard self.dijkstra(start, finish) is Some((path, weight)) else {
    return None
  }
  let ids = []
  for i in 1..<path.length() {
    let s = self.slot(path[i - 1], path[i])
    guard s >= 0 else { return None }
    self.slot_seq[s].flatten(ids)
  }
  ids.push(finish)
  Some((ids.map(v => (self.xs[v], self.ys[v])), weight))
}
