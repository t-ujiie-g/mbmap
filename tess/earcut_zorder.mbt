// Port of earcut 3.2.4 (https://github.com/mapbox/earcut), ISC License,
// Copyright (c) 2026 Mapbox; see NOTICE. Operations follow src/earcut.js in
// order so triangles match exactly (no `refine`); nodes are parallel arrays.

///|
/// Coordinates are mapped into [0, Z_RANGE] for the z-order hash.
const Z_RANGE : Double = 32767.0

///|
/// Links the ring's nodes in z-order (stable by z).
fn Earcut::index_curve(
  self : Earcut,
  start : Int32,
  min_x : Double,
  min_y : Double,
  inv_size : Double,
) -> Unit {
  let arr = self.sort_arr
  arr.clear()
  let mut p = start
  while true {
    self.z[p] = z_order(self.xs[p], self.ys[p], min_x, min_y, inv_size)
    arr.push(p)
    p = self.next[p]
    if p == start {
      break
    }
  }
  self.sort_nodes()
  let mut prev = -1
  for node in arr {
    self.prev_z[node] = prev
    if prev >= 0 {
      self.next_z[prev] = node
    }
    prev = node
  }
  self.next_z[prev] = -1
}

///|
/// Sorts `sort_arr` by z: insertion sort when short, else an 8-bit LSD radix
/// sort over z's 30 bits.
fn Earcut::sort_nodes(self : Earcut) -> Unit {
  let arr = self.sort_arr
  let z = self.z
  let n = arr.length()
  if n <= 32 {
    for i in 1..<n {
      let node = arr[i]
      let zn = z[node]
      let mut j = i - 1
      while j >= 0 && z[arr[j]] > zn {
        arr[j + 1] = arr[j]
        j -= 1
      }
      arr[j + 1] = node
    }
    return
  }
  let buf = self.sort_buf
  let za = self.z_arr
  let zb = self.z_buf
  buf.resize(n, 0)
  za.resize(n, 0)
  zb.resize(n, 0)
  for i in 0..<n {
    za[i] = z[arr[i]]
  }
  self.radix_pass(n, arr, za, buf, zb, 0)
  self.radix_pass(n, buf, zb, arr, za, 8)
  self.radix_pass(n, arr, za, buf, zb, 16)
  self.radix_pass(n, buf, zb, arr, za, 24)
}

///|
fn Earcut::radix_pass(
  self : Earcut,
  n : Int32,
  src : Array[Int32],
  src_z : Array[Int32],
  dst : Array[Int32],
  dst_z : Array[Int32],
  shift : Int32,
) -> Unit {
  let counts = self.counts
  counts.fill(0)
  for i in 0..<n {
    let d = (src_z[i] >> shift) & 0xff
    counts[d] = counts[d] + 1
  }
  let mut sum = 0
  for b in 0..<256 {
    let c = counts[b]
    counts[b] = sum
    sum += c
  }
  for i in 0..<n {
    let zi = src_z[i]
    let d = (zi >> shift) & 0xff
    let pos = counts[d]
    counts[d] = pos + 1
    dst[pos] = src[i]
    dst_z[pos] = zi
  }
}

///|
/// Morton code of a point mapped into the 15-bit range of the data bbox.
fn z_order(
  x : Double,
  y : Double,
  min_x : Double,
  min_y : Double,
  inv_size : Double,
) -> Int32 {
  let mut x = ((x - min_x) * inv_size).to_int()
  let mut y = ((y - min_y) * inv_size).to_int()
  x = (x | (x << 8)) & 0x00FF00FF
  x = (x | (x << 4)) & 0x0F0F0F0F
  x = (x | (x << 2)) & 0x33333333
  x = (x | (x << 1)) & 0x55555555
  y = (y | (y << 8)) & 0x00FF00FF
  y = (y | (y << 4)) & 0x0F0F0F0F
  y = (y | (y << 2)) & 0x33333333
  y = (y | (y << 1)) & 0x55555555
  x | (y << 1)
}
