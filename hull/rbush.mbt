// Ported from rbush 4.0.1 (MIT, (c) 2024 Volodymyr Agafonkin) and quickselect
// 3.0.0 (ISC, (c) 2024 Vladimir Agafonkin); see NOTICE.

///|
/// An rbush node: `nodes` when internal, `items` when a leaf.
priv struct Node {
  mut nodes : Array[Node]
  mut items : Array[Int32]
  mut height : Int32
  mut leaf : Bool
  mut min_x : Double
  mut min_y : Double
  mut max_x : Double
  mut max_y : Double
}

///|
fn Node::leaf_of(items : Array[Int32]) -> Node {
  {
    nodes: [],
    items,
    height: 1,
    leaf: true,
    min_x: @double.infinity,
    min_y: @double.infinity,
    max_x: @double.neg_infinity,
    max_y: @double.neg_infinity,
  }
}

///|
fn Node::count(self : Node) -> Int32 {
  if self.leaf {
    self.items.length()
  } else {
    self.nodes.length()
  }
}

///|
/// A box as rbush's `{minX, minY, maxX, maxY}`.
priv struct Box {
  mut min_x : Double
  mut min_y : Double
  mut max_x : Double
  mut max_y : Double
}

///|
fn empty_box() -> Box {
  {
    min_x: @double.infinity,
    min_y: @double.infinity,
    max_x: @double.neg_infinity,
    max_y: @double.neg_infinity,
  }
}

///|
/// An R-tree of item numbers whose boxes are `boxes[4 * item ..]`, which the
/// owner may change for an item outside the tree (rbush's `toBBox`).
priv struct RBush {
  mut data : Node
  max_entries : Int32
  min_entries : Int32
  boxes : Array[Double]
  trig : @core.Trig
}

///|
fn RBush::new(
  max_entries : Int32,
  boxes : Array[Double],
  trig : @core.Trig,
) -> RBush {
  let max = if max_entries > 4 { max_entries } else { 4 }
  let min = (max.to_double() * 0.4).ceil().to_int()
  {
    data: Node::leaf_of([]),
    max_entries: max,
    min_entries: if min > 2 {
      min
    } else {
      2
    },
    boxes,
    trig,
  }
}

///|
fn RBush::min_x(self : RBush, item : Int32) -> Double {
  self.boxes[4 * item]
}

///|
fn RBush::min_y(self : RBush, item : Int32) -> Double {
  self.boxes[4 * item + 1]
}

///|
fn RBush::max_x(self : RBush, item : Int32) -> Double {
  self.boxes[4 * item + 2]
}

///|
fn RBush::max_y(self : RBush, item : Int32) -> Double {
  self.boxes[4 * item + 3]
}

///|
fn extend_by(
  n : Box,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
) -> Unit {
  n.min_x = js_min(n.min_x, min_x)
  n.min_y = js_min(n.min_y, min_y)
  n.max_x = js_max(n.max_x, max_x)
  n.max_y = js_max(n.max_y, max_y)
}

///|
fn extend_node(
  n : Node,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
) -> Unit {
  n.min_x = js_min(n.min_x, min_x)
  n.min_y = js_min(n.min_y, min_y)
  n.max_x = js_max(n.max_x, max_x)
  n.max_y = js_max(n.max_y, max_y)
}

///|
/// rbush's `distBBox`: the box of children `k` to `p - 1` of `node`.
fn RBush::dist_box(self : RBush, node : Node, k : Int32, p : Int32) -> Box {
  let b = empty_box()
  for i in k..<p {
    if node.leaf {
      let it = node.items[i]
      extend_by(
        b,
        self.min_x(it),
        self.min_y(it),
        self.max_x(it),
        self.max_y(it),
      )
    } else {
      let c = node.nodes[i]
      extend_by(b, c.min_x, c.min_y, c.max_x, c.max_y)
    }
  }
  b
}

///|
fn RBush::calc_box(self : RBush, node : Node) -> Unit {
  let b = self.dist_box(node, 0, node.count())
  node.min_x = b.min_x
  node.min_y = b.min_y
  node.max_x = b.max_x
  node.max_y = b.max_y
}

///|
fn box_area(b : Box) -> Double {
  (b.max_x - b.min_x) * (b.max_y - b.min_y)
}

///|
fn box_margin(b : Box) -> Double {
  b.max_x - b.min_x + (b.max_y - b.min_y)
}

///|
fn node_box(n : Node) -> Box {
  { min_x: n.min_x, min_y: n.min_y, max_x: n.max_x, max_y: n.max_y, }
}

///|
fn enlarged_area(a : Box, b : Box) -> Double {
  (js_max(b.max_x, a.max_x) - js_min(b.min_x, a.min_x)) *
  (js_max(b.max_y, a.max_y) - js_min(b.min_y, a.min_y))
}

///|
fn intersection_area(a : Box, b : Box) -> Double {
  let min_x = js_max(a.min_x, b.min_x)
  let min_y = js_max(a.min_y, b.min_y)
  let max_x = js_min(a.max_x, b.max_x)
  let max_y = js_min(a.max_y, b.max_y)
  js_max(0.0, max_x - min_x) * js_max(0.0, max_y - min_y)
}

///|
/// rbush's `contains(a, b)`: `a` holds `b`.
fn contains(a : Box, b : Box) -> Bool {
  a.min_x <= b.min_x &&
  a.min_y <= b.min_y &&
  b.max_x <= a.max_x &&
  b.max_y <= a.max_y
}

///|
fn intersects(a : Box, b : Box) -> Bool {
  b.min_x <= a.max_x &&
  b.min_y <= a.max_y &&
  b.max_x >= a.min_x &&
  b.max_y >= a.min_y
}

///|
fn RBush::item_box(self : RBush, item : Int32) -> Box {
  {
    min_x: self.min_x(item),
    min_y: self.min_y(item),
    max_x: self.max_x(item),
    max_y: self.max_y(item),
  }
}

///|
/// rbush's `load` into an empty tree.
fn RBush::load(self : RBush, data : Array[Int32]) -> Unit {
  if data.length() == 0 {
    return
  }
  if data.length() < self.min_entries {
    for item in data {
      self.insert(item)
    }
    return
  }
  self.data = self.build(data.copy(), 0, data.length() - 1, 0)
}

///|
fn RBush::build(
  self : RBush,
  items : Array[Int32],
  left : Int32,
  right : Int32,
  height : Int32,
) -> Node {
  let n = right - left + 1
  let mut m = self.max_entries
  if n <= m {
    let node = Node::leaf_of(items[left:right + 1].to_owned())
    self.calc_box(node)
    return node
  }
  let mut height = height
  if height == 0 {
    height = ((self.trig.ln)(n.to_double()) / (self.trig.ln)(m.to_double()))
      .ceil()
      .to_int()
    let mut pow = 1.0
    for _ in 0..<(height - 1) {
      pow *= m.to_double()
    }
    m = (n.to_double() / pow).ceil().to_int()
  }
  let node = Node::leaf_of([])
  node.leaf = false
  node.height = height
  let n2 = (n.to_double() / m.to_double()).ceil().to_int()
  let n1 = n2 * m.to_double().sqrt().ceil().to_int()
  self.multi_select(items, left, right, n1, true)
  let mut i = left
  while i <= right {
    let right2 = if i + n1 - 1 < right { i + n1 - 1 } else { right }
    self.multi_select(items, i, right2, n2, false)
    let mut j = i
    while j <= right2 {
      let right3 = if j + n2 - 1 < right2 { j + n2 - 1 } else { right2 }
      node.nodes.push(self.build(items, j, right3, height - 1))
      j += n2
    }
    i += n1
  }
  self.calc_box(node)
  node
}

///|
/// `compareMinX` (or `compareMinY`) of two items.
fn RBush::compare_items(
  self : RBush,
  by_x : Bool,
  a : Int32,
  b : Int32,
) -> Double {
  if by_x {
    self.min_x(a) - self.min_x(b)
  } else {
    self.min_y(a) - self.min_y(b)
  }
}

///|
fn RBush::multi_select(
  self : RBush,
  arr : Array[Int32],
  left : Int32,
  right : Int32,
  n : Int32,
  by_x : Bool,
) -> Unit {
  let stack = [left, right]
  while stack.length() > 0 {
    let right = stack.unsafe_pop()
    let left = stack.unsafe_pop()
    if right - left <= n {
      continue
    }
    let mid = left +
      ((right - left).to_double() / n.to_double() / 2.0).ceil().to_int() * n
    self.quickselect(arr, mid, left, right, by_x)
    stack.push(left)
    stack.push(mid)
    stack.push(mid)
    stack.push(right)
  }
}

///|
fn swap(arr : Array[Int32], i : Int32, j : Int32) -> Unit {
  let tmp = arr[i]
  arr[i] = arr[j]
  arr[j] = tmp
}

///|
/// quickselect 3.0.0 (Floyd-Rivest) over `arr[left..=right]`.
fn RBush::quickselect(
  self : RBush,
  arr : Array[Int32],
  k : Int32,
  left : Int32,
  right : Int32,
  by_x : Bool,
) -> Unit {
  let mut left = left
  let mut right = right
  while right > left {
    if right - left > 600 {
      let n = (right - left + 1).to_double()
      let m = (k - left + 1).to_double()
      let z = (self.trig.ln)(n)
      let s = 0.5 * (self.trig.exp)(2.0 * z / 3.0)
      let sd = 0.5 *
        (z * s * (n - s) / n).sqrt() *
        (if m - n / 2.0 < 0.0 { -1.0 } else { 1.0 })
      let kd = k.to_double()
      let lo = (kd - m * s / n + sd).floor().to_int()
      let hi = (kd + (n - m) * s / n + sd).floor().to_int()
      let new_left = if left > lo { left } else { lo }
      let new_right = if right < hi { right } else { hi }
      self.quickselect(arr, k, new_left, new_right, by_x)
    }
    let t = arr[k]
    let mut i = left
    let mut j = right
    swap(arr, left, k)
    if self.compare_items(by_x, arr[right], t) > 0.0 {
      swap(arr, left, right)
    }
    while i < j {
      swap(arr, i, j)
      i += 1
      j -= 1
      while self.compare_items(by_x, arr[i], t) < 0.0 {
        i += 1
      }
      while self.compare_items(by_x, arr[j], t) > 0.0 {
        j -= 1
      }
    }
    if self.compare_items(by_x, arr[left], t) == 0.0 {
      swap(arr, left, j)
    } else {
      j += 1
      swap(arr, j, right)
    }
    if j <= k {
      left = j + 1
    }
    if k <= j {
      right = j - 1
    }
  }
}

///|
fn RBush::insert(self : RBush, item : Int32) -> Unit {
  let bbox = self.item_box(item)
  let path : Array[Node] = []
  let mut level = self.data.height - 1
  let node = self.choose_subtree(bbox, level, path)
  node.items.push(item)
  extend_node(node, bbox.min_x, bbox.min_y, bbox.max_x, bbox.max_y)
  while level >= 0 {
    if path[level].count() > self.max_entries {
      self.split(path, level)
      level -= 1
    } else {
      break
    }
  }
  for i = level; i >= 0; i = i - 1 {
    extend_node(path[i], bbox.min_x, bbox.min_y, bbox.max_x, bbox.max_y)
  }
}

///|
fn RBush::choose_subtree(
  self : RBush,
  bbox : Box,
  level : Int32,
  path : Array[Node],
) -> Node {
  let mut node = self.data
  while true {
    path.push(node)
    if node.leaf || path.length() - 1 == level {
      break
    }
    let mut min_area = @double.infinity
    let mut min_enlargement = @double.infinity
    let mut target : Node? = None
    for child in node.nodes {
      let cb = node_box(child)
      let area = box_area(cb)
      let enlargement = enlarged_area(bbox, cb) - area
      if enlargement < min_enlargement {
        min_enlargement = enlargement
        min_area = if area < min_area { area } else { min_area }
        target = Some(child)
      } else if enlargement == min_enlargement {
        if area < min_area {
          min_area = area
          target = Some(child)
        }
      }
    }
    node = match target {
      Some(t) => t
      None => node.nodes[0]
    }
  }
  node
}

///|
fn RBush::split(self : RBush, path : Array[Node], level : Int32) -> Unit {
  let node = path[level]
  let mm = node.count()
  let m = self.min_entries
  self.choose_split_axis(node, m, mm)
  let at = self.choose_split_index(node, m, mm)
  let new_node = Node::leaf_of([])
  if node.leaf {
    new_node.items = node.items[at:].to_owned()
    node.items.truncate(at)
  } else {
    new_node.nodes = node.nodes[at:].to_owned()
    node.nodes.truncate(at)
  }
  new_node.height = node.height
  new_node.leaf = node.leaf
  self.calc_box(node)
  self.calc_box(new_node)
  if level > 0 {
    path[level - 1].nodes.push(new_node)
  } else {
    self.split_root(node, new_node)
  }
}

///|
fn RBush::split_root(self : RBush, node : Node, new_node : Node) -> Unit {
  let root = Node::leaf_of([])
  root.nodes = [node, new_node]
  root.height = node.height + 1
  root.leaf = false
  self.calc_box(root)
  self.data = root
}

///|
fn RBush::choose_split_index(
  self : RBush,
  node : Node,
  m : Int32,
  mm : Int32,
) -> Int32 {
  let mut index : Int32? = None
  let mut min_overlap = @double.infinity
  let mut min_area = @double.infinity
  for i in m..<=(mm - m) {
    let b1 = self.dist_box(node, 0, i)
    let b2 = self.dist_box(node, i, mm)
    let overlap = intersection_area(b1, b2)
    let area = box_area(b1) + box_area(b2)
    if overlap < min_overlap {
      min_overlap = overlap
      index = Some(i)
      min_area = if area < min_area { area } else { min_area }
    } else if overlap == min_overlap {
      if area < min_area {
        min_area = area
        index = Some(i)
      }
    }
  }
  match index {
    Some(i) => i
    None => mm - m
  }
}

///|
fn RBush::sort_children(self : RBush, node : Node, by_x : Bool) -> Unit {
  if node.leaf {
    stable_sort(node.items, (a, b) => self.compare_items(by_x, a, b))
  } else if by_x {
    stable_sort(node.nodes, (a, b) => a.min_x - b.min_x)
  } else {
    stable_sort(node.nodes, (a, b) => a.min_y - b.min_y)
  }
}

///|
fn RBush::choose_split_axis(
  self : RBush,
  node : Node,
  m : Int32,
  mm : Int32,
) -> Unit {
  let x_margin = self.all_dist_margin(node, m, mm, true)
  let y_margin = self.all_dist_margin(node, m, mm, false)
  if x_margin < y_margin {
    self.sort_children(node, true)
  }
}

///|
fn RBush::all_dist_margin(
  self : RBush,
  node : Node,
  m : Int32,
  mm : Int32,
  by_x : Bool,
) -> Double {
  self.sort_children(node, by_x)
  let left = self.dist_box(node, 0, m)
  let right = self.dist_box(node, mm - m, mm)
  let mut margin = box_margin(left) + box_margin(right)
  for i in m..<(mm - m) {
    self.extend_with_child(left, node, i)
    margin += box_margin(left)
  }
  for i = mm - m - 1; i >= m; i = i - 1 {
    self.extend_with_child(right, node, i)
    margin += box_margin(right)
  }
  margin
}

///|
fn RBush::extend_with_child(
  self : RBush,
  b : Box,
  node : Node,
  i : Int32,
) -> Unit {
  if node.leaf {
    let it = node.items[i]
    extend_by(b, self.min_x(it), self.min_y(it), self.max_x(it), self.max_y(it))
  } else {
    let c = node.nodes[i]
    extend_by(b, c.min_x, c.min_y, c.max_x, c.max_y)
  }
}

///|
/// rbush's `remove`: the leaf holding `item` is looked for under the nodes
/// whose boxes hold the item's box, depth first.
fn RBush::remove(self : RBush, item : Int32) -> Bool {
  let bbox = self.item_box(item)
  let path : Array[Node] = []
  if self.find_path(self.data, item, bbox, path) {
    self.condense(path)
    true
  } else {
    false
  }
}

///|
fn RBush::find_path(
  self : RBush,
  node : Node,
  item : Int32,
  bbox : Box,
  path : Array[Node],
) -> Bool {
  if node.leaf {
    match node.items.search(item) {
      Some(i) => {
        node.items.remove(i) |> ignore
        path.push(node)
        return true
      }
      None => return false
    }
  }
  if !contains(node_box(node), bbox) {
    return false
  }
  path.push(node)
  for child in node.nodes {
    if self.find_path(child, item, bbox, path) {
      return true
    }
  }
  path.unsafe_pop() |> ignore
  false
}

///|
fn RBush::condense(self : RBush, path : Array[Node]) -> Unit {
  for i = path.length() - 1; i >= 0; i = i - 1 {
    if path[i].count() == 0 {
      if i > 0 {
        let siblings = path[i - 1].nodes
        match siblings.search_by(n => physical_equal(n, path[i])) {
          Some(k) => siblings.remove(k) |> ignore
          None => ()
        }
      } else {
        self.data = Node::leaf_of([])
      }
    } else {
      self.calc_box(path[i])
    }
  }
}

///|
/// Whether an item whose box meets `bbox` satisfies `pred` (rbush's `search`
/// then a scan of its results, stopping at the first).
fn RBush::search_any(self : RBush, bbox : Box, pred : (Int32) -> Bool) -> Bool {
  let root = self.data
  if !intersects(bbox, node_box(root)) {
    return false
  }
  let stack = [root]
  while stack.pop() is Some(node) {
    if node.leaf {
      for it in node.items {
        if intersects(bbox, self.item_box(it)) && pred(it) {
          return true
        }
      }
    } else {
      for child in node.nodes {
        if intersects(bbox, node_box(child)) {
          stack.push(child)
        }
      }
    }
  }
  false
}
