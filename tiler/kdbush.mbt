// Ported from kdbush 4.1.0: ISC License, Copyright (c) 2026, Vladimir
// Agafonkin. See NOTICE.

///|
/// kdbush's `KDBush` over integer points: `ids` and `coords` kd-sorted, so
/// that queries return the indices the points were added at.
priv struct KDBush {
  node_size : Int32
  ids : FixedArray[Int32]
  coords : FixedArray[Int32]
}

///|
/// Indexes the first `n` points of `coords` (x, y pairs); `trig` gives the
/// `ln` and `exp` of the selection step.
fn KDBush::new(
  coords : FixedArray[Int32],
  n : Int32,
  node_size : Int32,
  trig : Trig,
) -> KDBush {
  let node_size = @cmp.minimum(@cmp.maximum(node_size, 2), 65535)
  let ids = FixedArray::makei(n, i => i)
  let sorted = FixedArray::make(n * 2, 0)
  FixedArray::unsafe_blit(sorted, 0, coords, 0, n * 2)
  kd_sort(ids, sorted, node_size, 0, n - 1, 0, trig)
  { node_size, ids, coords: sorted, }
}

///|
/// The indices of the points inside the box, edges included (kdbush's
/// `range`), in kdbush's order.
fn KDBush::range(
  self : KDBush,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
) -> Array[Int32] {
  let result = []
  if self.ids.length() == 0 {
    return result
  }
  let coords = self.coords
  let inside = (i : Int32) => {
    let x = coords[2 * i].to_double()
    let y = coords[2 * i + 1].to_double()
    x >= min_x && x <= max_x && y >= min_y && y <= max_y
  }
  let stack = [0, self.ids.length() - 1, 0]
  while stack.pop() is Some(axis) {
    let right = stack.pop().unwrap()
    let left = stack.pop().unwrap()
    if right - left <= self.node_size {
      for i in left..<=right {
        if inside(i) {
          result.push(self.ids[i])
        }
      }
      continue
    }
    let m = (left + right) >> 1
    let x = coords[2 * m].to_double()
    let y = coords[2 * m + 1].to_double()
    if inside(m) {
      result.push(self.ids[m])
    }
    if (if axis == 0 { min_x <= x } else { min_y <= y }) {
      stack.push(left)
      stack.push(m - 1)
      stack.push(1 - axis)
    }
    if (if axis == 0 { max_x >= x } else { max_y >= y }) {
      stack.push(m + 1)
      stack.push(right)
      stack.push(1 - axis)
    }
  }
  result
}

///|
/// Writes the indices of the points within `r` of (qx, qy) to `out` and
/// returns their number (kdbush's `withinInto`).
fn KDBush::within_into(
  self : KDBush,
  qx : Double,
  qy : Double,
  r : Double,
  out : FixedArray[Int32],
) -> Int32 {
  if self.ids.length() == 0 {
    return 0
  }
  let coords = self.coords
  let r2 = r * r
  let mut count = 0
  let near = (x : Double, y : Double) => {
    let dx = x - qx
    let dy = y - qy
    dx * dx + dy * dy <= r2
  }
  let stack = [0, self.ids.length() - 1, 0]
  while stack.pop() is Some(axis) {
    let right = stack.pop().unwrap()
    let left = stack.pop().unwrap()
    if right - left <= self.node_size {
      for i in left..<=right {
        if near(coords[2 * i].to_double(), coords[2 * i + 1].to_double()) {
          out[count] = self.ids[i]
          count += 1
        }
      }
      continue
    }
    let m = (left + right) >> 1
    let x = coords[2 * m].to_double()
    let y = coords[2 * m + 1].to_double()
    if near(x, y) {
      out[count] = self.ids[m]
      count += 1
    }
    if (if axis == 0 { qx - r <= x } else { qy - r <= y }) {
      stack.push(left)
      stack.push(m - 1)
      stack.push(1 - axis)
    }
    if (if axis == 0 { qx + r >= x } else { qy + r >= y }) {
      stack.push(m + 1)
      stack.push(right)
      stack.push(1 - axis)
    }
  }
  count
}

///|
/// kdbush's `sort`: halves split at the middle, on x and y in turn.
fn kd_sort(
  ids : FixedArray[Int32],
  coords : FixedArray[Int32],
  node_size : Int32,
  left : Int32,
  right : Int32,
  axis : Int32,
  trig : Trig,
) -> Unit {
  if right - left <= node_size {
    return
  }
  let m = (left + right) >> 1
  kd_select(ids, coords, m, left, right, axis, trig)
  kd_sort(ids, coords, node_size, left, m - 1, 1 - axis, trig)
  kd_sort(ids, coords, node_size, m + 1, right, 1 - axis, trig)
}

///|
/// kdbush's Floyd-Rivest `select`: the points of [left, right] reordered so
/// that those before `k` are not greater than it along `axis`.
fn kd_select(
  ids : FixedArray[Int32],
  coords : FixedArray[Int32],
  k : Int32,
  left : Int32,
  right : Int32,
  axis : Int32,
  trig : Trig,
) -> Unit {
  let mut left = left
  let mut right = right
  while right > left {
    if right - left > 600 {
      let n = (right - left + 1).to_double()
      let m = (k - left + 1).to_double()
      let z = trig.ln(n)
      let s = 0.5 * trig.exp(2.0 * z / 3.0)
      let sign = if m - n / 2.0 < 0.0 { -1.0 } else { 1.0 }
      let sd = 0.5 * (z * s * (n - s) / n).sqrt() * sign
      let kd = k.to_double()
      let new_left = @cmp.maximum(left, (kd - m * s / n + sd).floor().to_int())
      let new_right = @cmp.minimum(
        right,
        (kd + (n - m) * s / n + sd).floor().to_int(),
      )
      kd_select(ids, coords, k, new_left, new_right, axis, trig)
    }
    let t = coords[2 * k + axis]
    let mut i = left
    let mut j = right
    swap_item(ids, coords, left, k)
    if coords[2 * right + axis] > t {
      swap_item(ids, coords, left, right)
    }
    while i < j {
      swap_item(ids, coords, i, j)
      i += 1
      j -= 1
      while coords[2 * i + axis] < t {
        i += 1
      }
      while coords[2 * j + axis] > t {
        j -= 1
      }
    }
    if coords[2 * left + axis] == t {
      swap_item(ids, coords, left, j)
    } else {
      j += 1
      swap_item(ids, coords, j, right)
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
fn swap_item(
  ids : FixedArray[Int32],
  coords : FixedArray[Int32],
  i : Int32,
  j : Int32,
) -> Unit {
  let id = ids[i]
  ids[i] = ids[j]
  ids[j] = id
  let x = coords[2 * i]
  let y = coords[2 * i + 1]
  coords[2 * i] = coords[2 * j]
  coords[2 * i + 1] = coords[2 * j + 1]
  coords[2 * j] = x
  coords[2 * j + 1] = y
}
