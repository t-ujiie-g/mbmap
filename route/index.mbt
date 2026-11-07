///|
/// An open-addressing map from pairs of `Int64` to non-negative `Int`s
/// (linear probing, deletion by backward shift).
priv struct PairIndex {
  mut k1 : FixedArray[Int64]
  mut k2 : FixedArray[Int64]
  mut vals : FixedArray[Int32]
  mut mask : Int32
  mut count : Int32
}

///|
fn PairIndex::new(expected : Int32) -> PairIndex {
  let mut cap = 16
  while cap < expected * 2 {
    cap = cap * 2
  }
  {
    k1: FixedArray::make(cap, 0L),
    k2: FixedArray::make(cap, 0L),
    vals: FixedArray::make(cap, -1),
    mask: cap - 1,
    count: 0,
  }
}

///|
fn PairIndex::home(self : PairIndex, a : Int64, b : Int64) -> Int32 {
  let h = (a.reinterpret_as_uint64() * 0x9E3779B97F4A7C15UL) ^
    (b.reinterpret_as_uint64() * 0xC2B2AE3D27D4EB4FUL)
  let h = h ^ (h >> 31)
  (h >> 32).to_int() & self.mask
}

///|
fn PairIndex::slot(self : PairIndex, a : Int64, b : Int64) -> Int32 {
  let mut i = self.home(a, b)
  while self.vals[i] >= 0 {
    if self.k1[i] == a && self.k2[i] == b {
      return i
    }
    i = (i + 1) & self.mask
  }
  i
}

///|
/// The value of `(a, b)`, or -1.
fn PairIndex::get(self : PairIndex, a : Int64, b : Int64) -> Int32 {
  self.vals[self.slot(a, b)]
}

///|
fn PairIndex::set(self : PairIndex, a : Int64, b : Int64, v : Int32) -> Unit {
  let i = self.slot(a, b)
  if self.vals[i] >= 0 {
    self.vals[i] = v
    return
  }
  self.k1[i] = a
  self.k2[i] = b
  self.vals[i] = v
  self.count += 1
  if self.count * 2 > self.mask + 1 {
    self.grow()
  }
}

///|
fn PairIndex::grow(self : PairIndex) -> Unit {
  let k1 = self.k1
  let k2 = self.k2
  let vals = self.vals
  let cap = (self.mask + 1) * 2
  self.k1 = FixedArray::make(cap, 0L)
  self.k2 = FixedArray::make(cap, 0L)
  self.vals = FixedArray::make(cap, -1)
  self.mask = cap - 1
  for i in 0..<vals.length() {
    if vals[i] >= 0 {
      let j = self.slot(k1[i], k2[i])
      self.k1[j] = k1[i]
      self.k2[j] = k2[i]
      self.vals[j] = vals[i]
    }
  }
}

///|
fn PairIndex::remove(self : PairIndex, a : Int64, b : Int64) -> Unit {
  let mut i = self.slot(a, b)
  guard self.vals[i] >= 0 else { return }
  self.count -= 1
  let mut j = i
  while true {
    j = (j + 1) & self.mask
    if self.vals[j] < 0 {
      break
    }
    let k = self.home(self.k1[j], self.k2[j])
    let stays = if i <= j { i < k && k <= j } else { i < k || k <= j }
    if !stays {
      self.k1[i] = self.k1[j]
      self.k2[i] = self.k2[j]
      self.vals[i] = self.vals[j]
      i = j
    }
  }
  self.vals[i] = -1
}
