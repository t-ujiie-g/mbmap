// Port of earcut 3.2.4 (https://github.com/mapbox/earcut), ISC License,
// Copyright (c) 2026 Mapbox; see NOTICE. Operations follow src/earcut.js in
// order so triangles match exactly (no `refine`); nodes are parallel arrays.

///|
/// Edges per block of the hole-bridge index.
const BLOCK_EDGES : Int32 = 16

///|
fn Earcut::eliminate_holes(
  self : Earcut,
  data : ArrayView[Int32],
  hole_starts : ArrayView[Int32],
  outer : Int32,
) -> Int32 {
  let queue = self.queue
  queue.clear()
  let len = hole_starts.length()
  for i in 0..<len {
    let start = hole_starts[i] * 2
    let end = if i < len - 1 { hole_starts[i + 1] * 2 } else { data.length() }
    let list = self.linked_list(data, start, end, false)
    if list < 0 {
      continue
    }
    if list == self.next[list] {
      self.steiner[list] = true
      self.has_steiners = true
    }
    queue.push(self.get_leftmost(list))
  }
  // Stable insertion sort, like Array.prototype.sort on these short queues.
  for i in 1..<queue.length() {
    let h = queue[i]
    let mut j = i - 1
    while j >= 0 && self.compare_xy_slope(queue[j], h) > 0 {
      queue[j + 1] = queue[j]
      j -= 1
    }
    queue[j + 1] = h
  }
  self.block_bbox.clear()
  self.block_head.clear()
  self.block_stop.clear()
  self.index_segment(outer, outer)
  self.index_active = true
  let mut outer = outer
  for h in queue {
    outer = self.eliminate_hole(h, outer)
  }
  self.index_active = false
  self.filter_points(outer, outer)
}

///|
/// Orders holes by leftmost point, then counterclockwise where they touch.
/// Returns the sign of the JS comparator, with NaN treated as 0 as `sort` does.
fn Earcut::compare_xy_slope(self : Earcut, a : Int32, b : Int32) -> Int32 {
  let xs = self.xs
  let ys = self.ys
  let dx = xs[a] - xs[b]
  if dx != 0.0 {
    return if dx < 0.0 { -1 } else { 1 }
  }
  let dy = ys[a] - ys[b]
  if dy != 0.0 {
    return if dy < 0.0 { -1 } else { 1 }
  }
  let an = self.next[a]
  let bn = self.next[b]
  let d = (ys[an] - ys[a]) / (xs[an] - xs[a]) -
    (ys[bn] - ys[b]) / (xs[bn] - xs[b])
  if d < 0.0 {
    -1
  } else if d > 0.0 {
    1
  } else {
    0
  }
}

///|
fn Earcut::eliminate_hole(self : Earcut, hole : Int32, outer : Int32) -> Int32 {
  let bridge = self.find_hole_bridge(hole, outer)
  if bridge < 0 {
    return outer
  }
  let bridge_reverse = self.split_polygon(bridge, hole)
  let bridge2 = self.next[bridge_reverse]
  self.index_segment(bridge, self.next[bridge2])
  ignore(self.filter_points(bridge_reverse, self.next[bridge_reverse]))
  self.filter_points(bridge, self.next[bridge])
}

///|
/// Appends blocks of up to `BLOCK_EDGES` edges covering `head..stop`
/// (`head == stop` means the whole ring) to the hole-bridge index.
fn Earcut::index_segment(self : Earcut, head : Int32, stop : Int32) -> Unit {
  let xs = self.xs
  let ys = self.ys
  let mut p = head
  while true {
    let b = self.block_head.length()
    self.block_head.push(p)
    let mut min_x = xs[p]
    let mut min_y = ys[p]
    let mut max_x = min_x
    let mut max_y = min_y
    let mut k = 0
    while true {
      let c = self.next[p]
      // z doubles as the owning block while holes are merged (see grow_block).
      self.z[p] = b
      let cx = xs[c]
      let cy = ys[c]
      if cx < min_x {
        min_x = cx
      }
      if cx > max_x {
        max_x = cx
      }
      if cy < min_y {
        min_y = cy
      }
      if cy > max_y {
        max_y = cy
      }
      p = c
      k += 1
      if k >= BLOCK_EDGES || p == stop {
        break
      }
    }
    self.block_stop.push(p)
    self.block_bbox.push(min_x)
    self.block_bbox.push(min_y)
    self.block_bbox.push(max_x)
    self.block_bbox.push(max_y)
    if p == stop {
      break
    }
  }
}

///|
/// Grows `head`'s block to cover `tail` when a removal heals the edge between them.
fn Earcut::grow_block(self : Earcut, head : Int32, tail : Int32) -> Unit {
  let g = self.z[head] * 4
  let bb = self.block_bbox
  let tx = self.xs[tail]
  let ty = self.ys[tail]
  if tx < bb[g] {
    bb[g] = tx
  }
  if ty < bb[g + 1] {
    bb[g + 1] = ty
  }
  if tx > bb[g + 2] {
    bb[g + 2] = tx
  }
  if ty > bb[g + 3] {
    bb[g + 3] = ty
  }
}

///|
fn Earcut::is_live(self : Earcut, p : Int32) -> Bool {
  self.next[self.prev[p]] == p
}

///|
fn Earcut::live_block_stop(self : Earcut, b : Int32) -> Int32 {
  let mut stop = self.block_stop[b]
  while !self.is_live(stop) {
    stop = self.next[stop]
  }
  self.block_stop[b] = stop
  stop
}

///|
fn Earcut::live_block_head(self : Earcut, b : Int32) -> Int32 {
  let mut head = self.block_head[b]
  while !self.is_live(head) {
    head = self.next[head]
  }
  self.block_head[b] = head
  head
}

///|
/// David Eberly's hole bridge search, pruned by the block index.
fn Earcut::find_hole_bridge(
  self : Earcut,
  hole : Int32,
  outer : Int32,
) -> Int32 {
  let xs = self.xs
  let ys = self.ys
  let bb = self.block_bbox
  let num_blocks = self.block_head.length()
  let hx = xs[hole]
  let hy = ys[hole]
  let mut qx = @double.neg_infinity
  let mut m = -1
  if self.equals(hole, outer) {
    return outer
  }
  for b in 0..<num_blocks {
    let g = b * 4
    if hy < bb[g + 1] || hy > bb[g + 3] || bb[g] > hx || bb[g + 2] <= qx {
      continue
    }
    let stop = self.live_block_stop(b)
    let mut p = self.live_block_head(b)
    while true {
      if self.is_live(p) {
        let pn = self.next[p]
        if self.equals(hole, pn) {
          return pn
        } else if hy <= ys[p] && hy >= ys[pn] && ys[pn] != ys[p] {
          let x = xs[p] + (hy - ys[p]) * (xs[pn] - xs[p]) / (ys[pn] - ys[p])
          if x <= hx && x > qx {
            qx = x
            m = if xs[p] < xs[pn] { p } else { pn }
            if x == hx {
              return m
            }
          }
        }
      }
      p = self.next[p]
      if p == stop {
        break
      }
    }
  }
  if m < 0 {
    return -1
  }
  let mx = xs[m]
  let my = ys[m]
  let tmin_y = @cmp.minimum(hy, my)
  let tmax_y = @cmp.maximum(hy, my)
  let mut tan_min = @double.infinity
  for b in 0..<num_blocks {
    let g = b * 4
    if bb[g + 2] < mx || bb[g] > hx || bb[g + 3] < tmin_y || bb[g + 1] > tmax_y {
      continue
    }
    let stop = self.live_block_stop(b)
    let mut p = self.live_block_head(b)
    while true {
      let px = xs[p]
      let py = ys[p]
      if self.is_live(p) &&
        hx >= px &&
        px >= mx &&
        hx != px &&
        point_in_triangle(
          if hy < my {
            hx
          } else {
            qx
          },
          hy,
          mx,
          my,
          if hy < my {
            qx
          } else {
            hx
          },
          hy,
          px,
          py,
        ) {
        let tan = (hy - py).abs() / (hx - px)
        let pn = self.next[p]
        // A hole point on p's horizontal edge bridges along that edge.
        if (
            self.locally_inside(p, hole) ||
            (py == hy && ys[pn] == hy && xs[pn] > hx)
          ) &&
          (
            tan < tan_min ||
            (
              tan == tan_min &&
              (px > xs[m] || (px == xs[m] && self.sector_contains_sector(m, p)))
            )
          ) {
          m = p
          tan_min = tan
        }
      }
      p = self.next[p]
      if p == stop {
        break
      }
    }
  }
  m
}

///|
fn Earcut::sector_contains_sector(self : Earcut, m : Int32, p : Int32) -> Bool {
  self.area(self.prev[m], m, self.prev[p]) < 0.0 &&
  self.area(self.next[p], m, self.next[m]) < 0.0
}

///|
fn Earcut::get_leftmost(self : Earcut, start : Int32) -> Int32 {
  let mut p = start
  let mut leftmost = start
  while true {
    let px = self.xs[p]
    let lx = self.xs[leftmost]
    if px < lx || (px == lx && self.ys[p] < self.ys[leftmost]) {
      leftmost = p
    }
    p = self.next[p]
    if p == start {
      break
    }
  }
  leftmost
}
