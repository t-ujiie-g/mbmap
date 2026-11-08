// Ported from Draco 1.5.7 (compression/point_cloud/algorithms/dynamic_integer_points_kd_tree_decoder.h,
// compression/bit_coders/direct_bit_decoder.cc, folded_integer_bit_decoder.h, rans_bit_decoder.cc):
// Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

///|
/// The most dimensions (components of the attributes one kd-tree decoder holds) a kd-tree may
/// have; Draco allocates `32 × dimensions + 1` stack levels of that many words up front.
pub const MAX_KD_DIMENSIONS : Int32 = 1024

///|
/// The most work (tree nodes times dimensions) one kd-tree may take, which Draco leaves unbounded.
const MAX_KD_WORK : Int64 = 0x40000000L

///|
/// `DirectBitDecoder`: 32-bit words read from their most significant bit. `value` holds what
/// `bits` decoded.
priv struct DirectBits {
  words : FixedArray[UInt32]
  mut pos : Int32
  mut used : Int32
  mut value : UInt32
}

///|
/// `StartDecoding`.
fn DirectBits::start(b : Buffer) -> DirectBits? {
  let size = b.u32()
  guard !b.failed else { return None }
  guard size != 0 && (size & 3) == 0 else { return None }
  guard b.fits(size.reinterpret_as_uint().to_uint64()) else { return None }
  let words = FixedArray::makei(size / 4, fn(_) {
    b.u32().reinterpret_as_uint()
  })
  Some({ words, pos: 0, used: 0, value: 0, })
}

///|
/// `DecodeNextBit`: false past the end.
fn DirectBits::next_bit(self : DirectBits) -> Bool {
  guard self.pos < self.words.length() else { return false }
  let bit = (self.words[self.pos] >> (31 - self.used)) & 1
  self.used += 1
  if self.used == 32 {
    self.pos += 1
    self.used = 0
  }
  bit != 0
}

///|
/// `DecodeLeastSignificantBits32` of 1 to 32 bits into `value`; false (leaving `value`) past the
/// end.
fn DirectBits::bits(self : DirectBits, nbits : Int32) -> Bool {
  let remaining = 32 - self.used
  if nbits <= remaining {
    guard self.pos < self.words.length() else { return false }
    self.value = self.words[self.pos] << self.used >> (32 - nbits)
    self.used += nbits
    if self.used == 32 {
      self.pos += 1
      self.used = 0
    }
  } else {
    guard self.pos + 1 < self.words.length() else { return false }
    let left = self.words[self.pos] << self.used
    self.used = nbits - remaining
    self.pos += 1
    let right = self.words[self.pos] >> (32 - self.used)
    self.value = (left >> (32 - self.used - remaining)) | right
  }
  true
}

///|
/// The numbers decoder of a compression level: `DirectBitDecoder` (levels 0 and 1),
/// `RAnsBitDecoder` (2 and 3) or `FoldedBit32Decoder<RAnsBitDecoder>` (4 to 6, its 32 folded
/// decoders then its bit decoder).
priv enum KdNumbers {
  Direct(DirectBits)
  RAns(BitDecoder)
  Folded(FixedArray[BitDecoder])
}

///|
fn KdNumbers::start(level : Int32, b : Buffer) -> KdNumbers? {
  if level < 2 {
    return DirectBits::start(b).map(d => Direct(d))
  }
  let count = if level < 4 { 1 } else { 33 }
  let decoders = FixedArray::makei(count, fn(_) { BitDecoder::new(b.data) })
  for d in decoders {
    guard d.start(b) else { return None }
  }
  Some(if level < 4 { RAns(decoders[0]) } else { Folded(decoders) })
}

///|
/// `DecodeLeastSignificantBits32` of 1 to 32 bits; 0 when a direct decoder runs out, as the
/// kd-tree decoder's zeroed number stays.
fn KdNumbers::decode(self : KdNumbers, nbits : Int32) -> UInt32 {
  match self {
    Direct(d) => if d.bits(nbits) { d.value } else { 0 }
    RAns(d) => {
      let mut v : UInt32 = 0
      for _ in 0..<nbits {
        v = (v << 1) + (if d.bit() { 1 } else { 0 })
      }
      v
    }
    Folded(ds) => {
      let mut v : UInt32 = 0
      for i in 0..<nbits {
        v = (v << 1) + (if ds[i].bit() { 1 } else { 0 })
      }
      v
    }
  }
}

///|
/// Where a kd-tree's points go: each point's coordinates written into attributes (Draco's
/// `PointAttributeVectorOutputIterator`), or collected three by three into `collected` (the float
/// tree's points, failing past `limit`).
priv struct KdOut {
  targets : Array[KdTarget]
  collected : Array[UInt32]
  collect : Bool
  limit : Int64
  mut count : Int64
  mut over : Bool
}

///|
/// An attribute a kd-tree fills: `nc` coordinates from `offset` on, each stored as its `data_size`
/// low bytes into `bytes`, or whole into `ints` when `portable`, for the first `size` points.
priv struct KdTarget {
  bytes : FixedArray[Byte]
  ints : FixedArray[Int32]
  portable : Bool
  offset : Int32
  data_size : Int32
  nc : Int32
  size : Int32
}

///|
fn KdOut::to_attributes(targets : Array[KdTarget]) -> KdOut {
  { targets, collected: [], collect: false, limit: 0, count: 0, over: false, }
}

///|
fn KdOut::collecting(limit : Int64) -> KdOut {
  { targets: [], collected: [], collect: true, limit, count: 0, over: false, }
}

///|
/// `*oit = p; ++oit;` repeated `n` times; false (and `over`) when collecting past `limit`.
fn KdOut::put(self : KdOut, p : FixedArray[UInt32], n : Int64) -> Bool {
  if self.collect {
    guard self.count + n <= self.limit else {
      self.over = true
      return false
    }
    for _ in 0..<n.to_int() {
      self.collected.push(p[0])
      self.collected.push(p[1])
      self.collected.push(p[2])
    }
    self.count += n
    return true
  }
  for t in self.targets {
    let size = t.size.to_int64()
    let first = if self.count < size { self.count } else { size }
    let last = if self.count + n < size { self.count + n } else { size }
    for point in first.to_int()..<last.to_int() {
      for c in 0..<t.nc {
        let v = p[t.offset + c]
        let at = point * t.nc + c
        if t.portable {
          t.ints[at] = v.reinterpret_as_int()
        } else {
          for k in 0..<t.data_size {
            t.bytes[at * t.data_size + k] = (v >> (8 * k)).to_byte()
          }
        }
      }
    }
  }
  self.count += n
  true
}

///|
/// The `remaining`, `axis` and `half` decoders and the stacks of one kd-tree.
priv struct KdTree {
  dim : Int32
  select_axis : Bool
  bit_length : Int32
  numbers : KdNumbers
  remaining : DirectBits
  axis : DirectBits
  half : DirectBits
  bases : Array[FixedArray[UInt32]]
  levels : Array[FixedArray[Int32]]
}

///|
/// `GetAxis`.
fn KdTree::get_axis(
  self : KdTree,
  num_remaining : UInt32,
  levels : FixedArray[Int32],
  last_axis : Int32,
) -> Int32 {
  if !self.select_axis {
    return if last_axis == self.dim - 1 { 0 } else { last_axis + 1 }
  }
  let mut best = 0
  if num_remaining < 64 {
    for axis in 1..<self.dim {
      if levels[best] > levels[axis] {
        best = axis
      }
    }
  } else if self.axis.bits(4) {
    best = self.axis.value.reinterpret_as_int()
  }
  best
}

///|
/// Makes stack level `at` exist (Draco allocates all `32 × dim + 1` up front).
fn KdTree::level(self : KdTree, at : Int32) -> Unit {
  while self.bases.length() <= at {
    self.bases.push(FixedArray::make(self.dim, 0))
    self.levels.push(FixedArray::make(self.dim, 0))
  }
}

///|
/// `DynamicIntegerPointsKdTreeDecoder<level>(dim).DecodePoints(buffer, out, max_points)`: false
/// where Draco fails, and past `MAX_KD_DIMENSIONS` or `MAX_KD_WORK`. `out.count` is then the
/// number of points decoded.
fn decode_kd_points(
  b : Buffer,
  level : Int32,
  dim : Int32,
  max_points : UInt32,
  out : KdOut,
) -> Bool {
  let bit_length = b.u32()
  guard !b.failed && bit_length.reinterpret_as_uint() <= 32 else {
    return false
  }
  let num_points = b.u32().reinterpret_as_uint()
  guard !b.failed else { return false }
  guard num_points != 0 else { return true }
  guard num_points <= max_points else { return false }
  guard dim >= 1 && dim <= MAX_KD_DIMENSIONS else { return false }
  guard KdNumbers::start(level, b) is Some(numbers) else { return false }
  guard DirectBits::start(b) is Some(remaining) else { return false }
  guard DirectBits::start(b) is Some(axis) else { return false }
  guard DirectBits::start(b) is Some(half) else { return false }
  let tree : KdTree = {
    dim,
    select_axis: level == 6,
    bit_length,
    numbers,
    remaining,
    axis,
    half,
    bases: [],
    levels: [],
  }
  tree.level(0)
  tree.decode(num_points, out)
}

///|
/// `DecodeInternal`.
fn KdTree::decode(self : KdTree, num_points : UInt32, out : KdOut) -> Bool {
  let dim = self.dim
  let stack_points : Array[UInt32] = [num_points]
  let stack_axis : Array[Int32] = [0]
  let stack_pos : Array[Int32] = [0]
  let p : FixedArray[UInt32] = FixedArray::make(dim, 0)
  let axes = FixedArray::make(dim, 0)
  let mut work = 0L
  while stack_points.length() > 0 {
    let n = stack_points.unsafe_pop()
    let last_axis = stack_axis.unsafe_pop()
    let pos = stack_pos.unsafe_pop()
    work += dim.to_int64()
    guard work <= MAX_KD_WORK else { return false }
    guard n <= num_points else { return false }
    let old_base = self.bases[pos]
    let levels = self.levels[pos]
    let axis = self.get_axis(n, levels, last_axis)
    guard axis >= 0 && axis < dim else { return false }
    let level = levels[axis]
    if self.bit_length == level {
      guard out.put(old_base, n.to_uint64().reinterpret_as_int64()) else {
        return false
      }
      continue
    }
    if n <= 2 {
      axes[0] = axis
      for i in 1..<dim {
        axes[i] = if axes[i - 1] == dim - 1 { 0 } else { axes[i - 1] + 1 }
      }
      for _ in 0..<n.reinterpret_as_int() {
        for j in 0..<dim {
          let a = axes[j]
          let bits = self.bit_length - levels[a]
          p[a] = 0
          if bits != 0 {
            guard self.remaining.bits(bits) else { return false }
            p[a] = self.remaining.value
          }
          p[a] = old_base[a] | p[a]
        }
        guard out.put(p, 1) else { return false }
      }
      continue
    }
    guard out.count <= num_points.to_uint64().reinterpret_as_int64() else {
      return false
    }
    let modifier = 1U << (self.bit_length - level - 1)
    self.level(pos + 1)
    let new_base = self.bases[pos + 1]
    for i in 0..<dim {
      new_base[i] = old_base[i]
    }
    new_base[axis] = new_base[axis] + modifier
    let number = self.numbers.decode(31 - n.clz())
    let mut first = n / 2
    guard first >= number else { return false }
    first = first - number
    let mut second = n - first
    if first != second && !self.half.next_bit() {
      let t = first
      first = second
      second = t
    }
    levels[axis] += 1
    let next_levels = self.levels[pos + 1]
    for i in 0..<dim {
      next_levels[i] = levels[i]
    }
    if first != 0 {
      stack_points.push(first)
      stack_axis.push(axis)
      stack_pos.push(pos)
    }
    if second != 0 {
      stack_points.push(second)
      stack_axis.push(axis)
      stack_pos.push(pos + 1)
    }
  }
  true
}
