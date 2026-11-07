///|
/// JSTS's `java/util/TreeMap`: a red-black tree, ported node for node so that
/// keys whose order is not consistent (NaN coordinates) land as they do there.
/// Nodes are indices; -1 is null.
priv struct TreeMap[K, V] {
  keys : Array[K]
  vals : Array[V]
  left : Array[Int32]
  right : Array[Int32]
  parent : Array[Int32]
  red : Array[Bool]
  mut root : Int32
  cmp : (K, K) -> Int32
}

///|
fn[K, V] TreeMap::new(cmp : (K, K) -> Int32) -> TreeMap[K, V] {
  {
    keys: [],
    vals: [],
    left: [],
    right: [],
    parent: [],
    red: [],
    root: -1,
    cmp,
  }
}

///|
fn[K, V] TreeMap::size(self : TreeMap[K, V]) -> Int32 {
  self.keys.length()
}

///|
fn[K, V] TreeMap::get(self : TreeMap[K, V], key : K) -> V? {
  let mut p = self.root
  while p != -1 {
    let c = (self.cmp)(key, self.keys[p])
    if c < 0 {
      p = self.left[p]
    } else if c > 0 {
      p = self.right[p]
    } else {
      return Some(self.vals[p])
    }
  }
  None
}

///|
fn[K, V] TreeMap::add_node(
  self : TreeMap[K, V],
  key : K,
  value : V,
  parent : Int32,
) -> Int32 {
  self.keys.push(key)
  self.vals.push(value)
  self.left.push(-1)
  self.right.push(-1)
  self.parent.push(parent)
  self.red.push(false)
  self.keys.length() - 1
}

///|
fn[K, V] TreeMap::put(self : TreeMap[K, V], key : K, value : V) -> Unit {
  if self.root == -1 {
    self.root = self.add_node(key, value, -1)
    return
  }
  let mut t = self.root
  let mut parent = -1
  let mut c = 0
  while t != -1 {
    parent = t
    c = (self.cmp)(key, self.keys[t])
    if c < 0 {
      t = self.left[t]
    } else if c > 0 {
      t = self.right[t]
    } else {
      self.vals[t] = value
      return
    }
  }
  let e = self.add_node(key, value, parent)
  if c < 0 {
    self.left[parent] = e
  } else {
    self.right[parent] = e
  }
  self.fix_after_insertion(e)
}

///|
fn[K, V] TreeMap::parent_of(self : TreeMap[K, V], p : Int32) -> Int32 {
  if p == -1 {
    -1
  } else {
    self.parent[p]
  }
}

///|
fn[K, V] TreeMap::left_of(self : TreeMap[K, V], p : Int32) -> Int32 {
  if p == -1 {
    -1
  } else {
    self.left[p]
  }
}

///|
fn[K, V] TreeMap::right_of(self : TreeMap[K, V], p : Int32) -> Int32 {
  if p == -1 {
    -1
  } else {
    self.right[p]
  }
}

///|
fn[K, V] TreeMap::is_red(self : TreeMap[K, V], p : Int32) -> Bool {
  p != -1 && self.red[p]
}

///|
fn[K, V] TreeMap::set_red(self : TreeMap[K, V], p : Int32, red : Bool) -> Unit {
  if p != -1 {
    self.red[p] = red
  }
}

///|
fn[K, V] TreeMap::fix_after_insertion(self : TreeMap[K, V], e : Int32) -> Unit {
  let mut x = e
  self.red[x] = true
  while x != -1 && x != self.root && self.red[self.parent[x]] {
    let gp = self.parent_of(self.parent_of(x))
    if self.parent_of(x) == self.left_of(gp) {
      let y = self.right_of(gp)
      if self.is_red(y) {
        self.set_red(self.parent_of(x), false)
        self.set_red(y, false)
        self.set_red(gp, true)
        x = gp
      } else {
        if x == self.right_of(self.parent_of(x)) {
          x = self.parent_of(x)
          self.rotate_left(x)
        }
        self.set_red(self.parent_of(x), false)
        self.set_red(self.parent_of(self.parent_of(x)), true)
        self.rotate_right(self.parent_of(self.parent_of(x)))
      }
    } else {
      let y = self.left_of(gp)
      if self.is_red(y) {
        self.set_red(self.parent_of(x), false)
        self.set_red(y, false)
        self.set_red(gp, true)
        x = gp
      } else {
        if x == self.left_of(self.parent_of(x)) {
          x = self.parent_of(x)
          self.rotate_right(x)
        }
        self.set_red(self.parent_of(x), false)
        self.set_red(self.parent_of(self.parent_of(x)), true)
        self.rotate_left(self.parent_of(self.parent_of(x)))
      }
    }
  }
  self.red[self.root] = false
}

///|
fn[K, V] TreeMap::rotate_left(self : TreeMap[K, V], p : Int32) -> Unit {
  if p == -1 {
    return
  }
  let r = self.right[p]
  self.right[p] = self.left[r]
  if self.left[r] != -1 {
    self.parent[self.left[r]] = p
  }
  self.parent[r] = self.parent[p]
  let pp = self.parent[p]
  if pp == -1 {
    self.root = r
  } else if self.left[pp] == p {
    self.left[pp] = r
  } else {
    self.right[pp] = r
  }
  self.left[r] = p
  self.parent[p] = r
}

///|
fn[K, V] TreeMap::rotate_right(self : TreeMap[K, V], p : Int32) -> Unit {
  if p == -1 {
    return
  }
  let l = self.left[p]
  self.left[p] = self.right[l]
  if self.right[l] != -1 {
    self.parent[self.right[l]] = p
  }
  self.parent[l] = self.parent[p]
  let pp = self.parent[p]
  if pp == -1 {
    self.root = l
  } else if self.right[pp] == p {
    self.right[pp] = l
  } else {
    self.left[pp] = l
  }
  self.right[l] = p
  self.parent[p] = l
}

///|
/// The values in key order (`values()`).
fn[K, V] TreeMap::values(self : TreeMap[K, V]) -> Array[V] {
  let out = Array(capacity=self.size())
  let mut p = self.root
  if p == -1 {
    return out
  }
  while self.left[p] != -1 {
    p = self.left[p]
  }
  while p != -1 {
    out.push(self.vals[p])
    if self.right[p] != -1 {
      p = self.right[p]
      while self.left[p] != -1 {
        p = self.left[p]
      }
    } else {
      let mut ch = p
      p = self.parent[p]
      while p != -1 && ch == self.right[p] {
        ch = p
        p = self.parent[p]
      }
    }
  }
  out
}
