// Ported from flatbush 4.6.2: ISC License, Copyright (c) 2022, Vladimir
// Agafonkin. See NOTICE.

///|
/// A static packed Hilbert R-tree over boxes (flatbush): `add` every box, then
/// `finish`; searches return item indices in flatbush's order.
pub struct Index {
  priv num_items : Int32
  priv node_size : Int32
  priv level_bounds : Array[Int32]
  priv boxes : FixedArray[Double]
  priv indices : FixedArray[Int32]
  priv mut pos : Int32
  priv mut min_x : Double
  priv mut min_y : Double
  priv mut max_x : Double
  priv mut max_y : Double
  priv queue : Queue
}

///|
/// An index for `num_items` boxes with `node_size` children per node (2 to
/// 65535, default 16).
pub fn Index::new(num_items : Int32, node_size~ : Int32 = 16) -> Index {
  let node_size = @cmp.minimum(@cmp.maximum(node_size, 2), 65535)
  let n0 = @cmp.maximum(num_items, 0)
  let mut n = n0
  let mut num_nodes = n
  let level_bounds = [n * 4]
  if n0 > 0 {
    for ;; {
      n = (n + node_size - 1) / node_size
      num_nodes += n
      level_bounds.push(num_nodes * 4)
      if n == 1 {
        break
      }
    }
  }
  {
    num_items: n0,
    node_size,
    level_bounds,
    boxes: FixedArray::make(num_nodes * 4, 0.0),
    indices: FixedArray::make(num_nodes, 0),
    pos: 0,
    min_x: @double.infinity,
    min_y: @double.infinity,
    max_x: @double.neg_infinity,
    max_y: @double.neg_infinity,
    queue: Queue::new(),
  }
}

///|
/// Adds a box and returns its index, or -1 (ignoring it) past `num_items`.
pub fn Index::add(
  self : Index,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
) -> Int32 {
  let pos = self.pos
  let index = pos >> 2
  if index >= self.num_items {
    return -1
  }
  self.indices[index] = index
  self.boxes[pos] = min_x
  self.boxes[pos + 1] = min_y
  self.boxes[pos + 2] = max_x
  self.boxes[pos + 3] = max_y
  self.pos = pos + 4
  if min_x < self.min_x {
    self.min_x = min_x
  }
  if min_y < self.min_y {
    self.min_y = min_y
  }
  if max_x > self.max_x {
    self.max_x = max_x
  }
  if max_y > self.max_y {
    self.max_y = max_y
  }
  index
}

///|
/// Builds the tree; false (and the index stays unusable) unless exactly
/// `num_items` boxes were added.
pub fn Index::finish(self : Index) -> Bool {
  if self.pos >> 2 != self.num_items {
    return false
  }
  if self.num_items == 0 {
    return true
  }
  let boxes = self.boxes
  if self.num_items <= self.node_size {
    boxes[self.pos] = self.min_x
    boxes[self.pos + 1] = self.min_y
    boxes[self.pos + 2] = self.max_x
    boxes[self.pos + 3] = self.max_y
    self.pos += 4
    return true
  }
  let n = self.num_items
  let width = if self.max_x - self.min_x == 0.0 {
    1.0
  } else {
    self.max_x - self.min_x
  }
  let height = if self.max_y - self.min_y == 0.0 {
    1.0
  } else {
    self.max_y - self.min_y
  }
  let values = FixedArray::make(n, 0)
  let hilbert_max = ((1 << 16) - 1).to_double()
  let sx = hilbert_max / width
  let sy = hilbert_max / height
  for i in 0..<n {
    let p = i * 4
    let x = (sx * ((boxes[p] + boxes[p + 2]) / 2.0 - self.min_x)).to_int()
    let y = (sy * ((boxes[p + 1] + boxes[p + 3]) / 2.0 - self.min_y)).to_int()
    values[i] = hilbert(x, y)
  }
  sort(values, boxes, self.indices, 0, n - 1, self.node_size)
  let mut pos = n * 4
  let mut read = 0
  for i in 0..<(self.level_bounds.length() - 1) {
    let end = self.level_bounds[i]
    while read < end {
      let node = read
      let mut x0 = boxes[read]
      let mut y0 = boxes[read + 1]
      let mut x1 = boxes[read + 2]
      let mut y1 = boxes[read + 3]
      read += 4
      for j = 1; j < self.node_size && read < end; j = j + 1 {
        x0 = @cmp.minimum(x0, boxes[read])
        y0 = @cmp.minimum(y0, boxes[read + 1])
        x1 = @cmp.maximum(x1, boxes[read + 2])
        y1 = @cmp.maximum(y1, boxes[read + 3])
        read += 4
      }
      self.indices[pos >> 2] = node
      boxes[pos] = x0
      boxes[pos + 1] = y0
      boxes[pos + 2] = x1
      boxes[pos + 3] = y1
      pos += 4
    }
  }
  self.pos = pos
  true
}

///|
fn Index::ready(self : Index) -> Bool {
  self.num_items > 0 && self.pos == self.boxes.length()
}

///|
/// Items whose boxes intersect or touch the query box, appended to `out`.
pub fn Index::search(
  self : Index,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
  out : Array[Int32],
) -> Unit {
  guard self.ready() else { return }
  let boxes = self.boxes
  let indices = self.indices
  let items4 = self.num_items * 4
  let q : Array[Int32] = []
  let mut node = boxes.length() - 4
  let mut level = self.level_bounds.length() - 1
  let mut contained = false
  for ;; {
    let end = @cmp.minimum(node + self.node_size * 4, self.level_bounds[level])
    if contained {
      self.collect_contained(node, end, level, items4, out)
    } else {
      let is_node = node >= items4
      for pos = node; pos < end; pos = pos + 4 {
        let x0 = boxes[pos]
        let y0 = boxes[pos + 1]
        let x1 = boxes[pos + 2]
        let y1 = boxes[pos + 3]
        if max_x < x0 || max_y < y0 || min_x > x1 || min_y > y1 {
          continue
        }
        let index = indices[pos >> 2]
        if is_node {
          let c = if min_x <= x0 && min_y <= y0 && max_x >= x1 && max_y >= y1 {
            1
          } else {
            0
          }
          q.push(index | c)
          q.push(level - 1)
        } else {
          out.push(index)
        }
      }
    }
    guard q.pop() is Some(l) else { break }
    level = l
    let v = q.unsafe_pop()
    contained = (v & 1) == 1
    node = v & -2
  }
}

///|
/// The leaves under a node wholly inside the query are one contiguous run of
/// the leaf level (the tree is packed bottom-up).
fn Index::collect_contained(
  self : Index,
  node : Int32,
  end : Int32,
  level : Int32,
  items4 : Int32,
  out : Array[Int32],
) -> Unit {
  let mut pos = node
  for _ in 0..<level {
    pos = self.indices[pos >> 2]
  }
  let mut span = end - node
  for _ in 0..<level {
    span *= self.node_size
  }
  let leaf_end = @cmp.minimum(pos + span, items4)
  while pos < leaf_end {
    out.push(self.indices[pos >> 2])
    pos += 4
  }
}

///|
/// Up to `max_results` items in order of box distance from (x, y), within
/// `max_distance`, appended to `out`.
pub fn Index::neighbors(
  self : Index,
  x : Double,
  y : Double,
  out : Array[Int32],
  max_results~ : Int32 = @int.MAX_VALUE,
  max_distance~ : Double = @double.infinity,
) -> Unit {
  guard self.ready() && max_results > 0 else { return }
  let boxes = self.boxes
  let indices = self.indices
  let items4 = self.num_items * 4
  let q = self.queue
  let start = out.length()
  let track_nearest = max_results == 1
  let mut bound = max_distance * max_distance
  q.push((boxes.length() - 4) << 1, 0.0)
  while q.length > 0 {
    let top = q.ids[0]
    q.pop()
    if (top & 1) == 1 {
      out.push(top >> 1)
      if out.length() - start == max_results {
        break
      }
      continue
    }
    let node = top >> 1
    let leaf_level = node < items4
    let end = @cmp.minimum(
      node + self.node_size * 4,
      upper_bound(node, self.level_bounds),
    )
    for pos = node; pos < end; pos = pos + 4 {
      let dx = @cmp.maximum(
        @cmp.maximum(boxes[pos] - x, x - boxes[pos + 2]),
        0.0,
      )
      let dy = @cmp.maximum(
        @cmp.maximum(boxes[pos + 1] - y, y - boxes[pos + 3]),
        0.0,
      )
      let dist = dx * dx + dy * dy
      if dist > bound {
        continue
      }
      let child = indices[pos >> 2]
      if leaf_level {
        q.push((child << 1) | 1, dist)
        if track_nearest && dist < bound {
          bound = dist
        }
      } else {
        q.push(child << 1, dist)
      }
    }
  }
  q.length = 0
}

///|
/// The first level bound greater than `value`.
fn upper_bound(value : Int32, bounds : Array[Int32]) -> Int32 {
  let mut i = 0
  let mut j = bounds.length() - 1
  while i < j {
    let m = (i + j) >> 1
    if bounds[m] > value {
      j = m
    } else {
      i = m + 1
    }
  }
  bounds[i]
}

///|
/// Partially sorts boxes by Hilbert value, down to blocks of `node_size`.
fn sort(
  values : FixedArray[Int32],
  boxes : FixedArray[Double],
  indices : FixedArray[Int32],
  left : Int32,
  right : Int32,
  node_size : Int32,
) -> Unit {
  let stack = [left, right]
  while stack.pop() is Some(r) {
    let l = stack.unsafe_pop()
    if r - l <= node_size && l / node_size >= r / node_size {
      continue
    }
    let a = values[l]
    let b = values[(l + r) >> 1]
    let c = values[r]
    let pivot = if (a > b) != (a > c) {
      a
    } else if (b < a) != (b < c) {
      b
    } else {
      c
    }
    let mut i = l - 1
    let mut j = r + 1
    for ;; {
      i += 1
      while values[i] < pivot {
        i += 1
      }
      j -= 1
      while values[j] > pivot {
        j -= 1
      }
      if i >= j {
        break
      }
      swap(values, boxes, indices, i, j)
    }
    stack.push(l)
    stack.push(j)
    stack.push(j + 1)
    stack.push(r)
  }
}

///|
fn swap(
  values : FixedArray[Int32],
  boxes : FixedArray[Double],
  indices : FixedArray[Int32],
  i : Int32,
  j : Int32,
) -> Unit {
  let t = values[i]
  values[i] = values[j]
  values[j] = t
  let k = 4 * i
  let m = 4 * j
  for d in 0..<4 {
    let b = boxes[k + d]
    boxes[k + d] = boxes[m + d]
    boxes[m + d] = b
  }
  let e = indices[i]
  indices[i] = indices[j]
  indices[j] = e
}

///|
/// Hilbert index of (x, y) in [0, 65535]², shifted to signed range as
/// flatbush does (fast Hilbert curve by threadlocalmutex.com, public domain).
fn hilbert(x : Int32, y : Int32) -> Int32 {
  let mut a = x ^ y
  let mut b = 0xFFFF ^ a
  let mut c = 0xFFFF ^ (x | y)
  let mut d = x & (y ^ 0xFFFF)
  let mut aa = a | (b >> 1)
  let mut bb = (a >> 1) ^ a
  let mut cc = c ^ ((c >> 1) ^ (b & (d >> 1)))
  let mut dd = d ^ ((a & (c >> 1)) ^ (d >> 1))
  a = (aa & (aa >> 2)) ^ (bb & (bb >> 2))
  b = (aa & (bb >> 2)) ^ (bb & ((aa ^ bb) >> 2))
  c = cc ^ ((aa & (cc >> 2)) ^ (bb & (dd >> 2)))
  d = dd ^ ((bb & (cc >> 2)) ^ ((aa ^ bb) & (dd >> 2)))
  aa = (a & (a >> 4)) ^ (b & (b >> 4))
  bb = (a & (b >> 4)) ^ (b & ((a ^ b) >> 4))
  cc = c ^ ((a & (c >> 4)) ^ (b & (d >> 4)))
  dd = d ^ ((b & (c >> 4)) ^ ((a ^ b) & (d >> 4)))
  c = cc ^ ((aa & (cc >> 8)) ^ (bb & (dd >> 8)))
  d = dd ^ ((bb & (cc >> 8)) ^ ((aa ^ bb) & (dd >> 8)))
  c = c ^ (c >> 1)
  d = d ^ (d >> 1)
  a = x ^ y
  b = d | (0xFFFF ^ (a | c))
  a = (a | (a << 8)) & 0x00FF00FF
  a = (a | (a << 4)) & 0x0F0F0F0F
  a = (a | (a << 2)) & 0x33333333
  a = (a | (a << 1)) & 0x55555555
  b = (b | (b << 8)) & 0x00FF00FF
  b = (b | (b << 4)) & 0x0F0F0F0F
  b = (b | (b << 2)) & 0x33333333
  b = (b | (b << 1)) & 0x55555555
  ((b << 1) | a) ^ (1 << 31)
}
