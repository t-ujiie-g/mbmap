// Ported from Draco 1.5.7 (compression/attributes/prediction_schemes/: the delta, parallelogram and
// (constrained) multi-parallelogram decoders): Apache License 2.0, Copyright 2016 The Draco
// Authors. See NOTICE.

///|
/// Prediction methods as Draco numbers them; `PREDICTION_DELTA` also stands for the
/// difference scheme that every other predictor falls back on.
const PREDICTION_DELTA = 0

///|
const PREDICTION_PARALLELOGRAM = 1

///|
const PREDICTION_MULTI_PARALLELOGRAM = 2

///|
const PREDICTION_TEX_COORDS_DEPRECATED = 3

///|
const PREDICTION_CONSTRAINED_MULTI_PARALLELOGRAM = 4

///|
const PREDICTION_TEX_COORDS_PORTABLE = 5

///|
const PREDICTION_GEOMETRIC_NORMAL = 6

///|
/// A parent position for the schemes that read one: its portable values, three per entry, and
/// its point-to-value mapping (None for the identity).
priv struct Parent {
  values : FixedArray[Int32]
  map : FixedArray[Int32]?
}

///|
fn Parent::position(
  self : Parent,
  point : Int32,
  out : FixedArray[Int64],
) -> Bool {
  let v = match self.map {
    None => point
    Some(m) => {
      guard point >= 0 && point < m.length() else { return false }
      m[point]
    }
  }
  guard v >= 0 && v < self.values.length() / 3 else { return false }
  out[0] = self.values[3 * v].to_int64()
  out[1] = self.values[3 * v + 1].to_int64()
  out[2] = self.values[3 * v + 2].to_int64()
  true
}

///|
/// A prediction scheme decoder: the scheme's `predictor`, its transform, and for the mesh schemes
/// the corner table and encoding data (`MeshPredictionSchemeData`) with their decoded side data.
priv struct Scheme {
  predictor : Int32
  transform : Transform
  table : Table?
  enc : EncodingData
  mut parent : Parent?
  crease : FixedArray[FixedArray[Bool]]
  mut orientations : FixedArray[Bool]
  mut orientations_left : Int32
  mut orientations_first : Int32
  flip : BitDecoder
  mut normal_mode : Int32
}

///|
fn Scheme::new(
  predictor : Int32,
  transform : Transform,
  table : Table?,
  enc : EncodingData,
  data : FixedArray[Byte],
) -> Scheme {
  {
    predictor,
    transform,
    table,
    enc,
    parent: None,
    crease: FixedArray::make(4, []),
    orientations: [],
    orientations_left: 0,
    orientations_first: 0,
    flip: BitDecoder::new(data),
    normal_mode: 1,
  }
}

///|
fn Scheme::has_parent(self : Scheme) -> Bool {
  self.predictor == PREDICTION_TEX_COORDS_DEPRECATED ||
  self.predictor == PREDICTION_TEX_COORDS_PORTABLE ||
  self.predictor == PREDICTION_GEOMETRIC_NORMAL
}

///|
fn Scheme::num_corners(self : Scheme) -> Int32 {
  match self.table {
    Some(t) => 3 * t.face_count()
    None => 0
  }
}

///|
/// Pops the next orientation (`orientations_.back()`), or None when none is left.
fn Scheme::pop_orientation(self : Scheme) -> Bool? {
  guard self.orientations_left > 0 else { return None }
  self.orientations_left -= 1
  let i = self.orientations_left - self.orientations_first
  guard i >= 0 && i < self.orientations.length() else { return None }
  Some(self.orientations[i])
}

///|
/// The tex coords portable scheme's orientations: `n` bits, of which only the last `keep` can be
/// popped. Once the rANS state stops changing every later bit is the same, so the rest is
/// filled in without decoding them one by one.
fn Scheme::decode_orientations(
  self : Scheme,
  d : BitDecoder,
  n : Int32,
  keep : Int32,
) -> Unit {
  let first = if n > keep { n - keep } else { 0 }
  let out = FixedArray::make(n - first, false)
  let mut last = true
  let mut i = 0
  while i < n {
    let state = d.state
    let offset = d.offset
    let bit = d.bit()
    if !bit {
      last = !last
    }
    if i >= first {
      out[i - first] = last
    }
    i += 1
    if d.state == state && d.offset == offset {
      for j in (if i > first { i } else { first })..<n {
        out[j - first] = if bit { last } else { last != ((j - i + 1) % 2 == 1) }
      }
      break
    }
  }
  self.orientations = out
  self.orientations_first = first
  self.orientations_left = n
}

///|
fn Scheme::decode_data(self : Scheme, b : Buffer) -> Bool {
  match self.predictor {
    PREDICTION_CONSTRAINED_MULTI_PARALLELOGRAM => {
      if b.version < bitstream(2, 2) {
        let mode = b.u8()
        guard !b.failed && mode == 0 else { return false }
      }
      for i in 0..<4 {
        let n = b.varint()
        guard !b.failed else { return false }
        guard !ult(self.num_corners(), n) else { return false }
        if n > 0 {
          let flags = FixedArray::make(n, false)
          self.crease[i] = flags
          let d = BitDecoder::new(b.data)
          guard d.start(b) else { return false }
          for j in 0..<n {
            flags[j] = d.bit()
          }
        }
      }
    }
    PREDICTION_TEX_COORDS_PORTABLE => {
      let n = b.u32()
      guard !b.failed && n >= 0 else { return false }
      let d = BitDecoder::new(b.data)
      guard d.start(b) else { return false }
      self.decode_orientations(d, n, self.enc.corners.length())
    }
    PREDICTION_TEX_COORDS_DEPRECATED => {
      let n = if b.version < bitstream(2, 2) { b.u32() } else { b.varint() }
      guard !b.failed else { return false }
      guard n != 0 && !ult(self.num_corners(), n) else { return false }
      let d = BitDecoder::new(b.data)
      guard d.start(b) else { return false }
      self.decode_orientations(d, n, n)
    }
    PREDICTION_GEOMETRIC_NORMAL => {
      guard self.transform.decode_data(b) else { return false }
      if b.version < bitstream(2, 2) {
        let mode = b.u8()
        guard !b.failed && mode <= 1 else { return false }
        self.normal_mode = mode
      }
      return self.flip.start(b)
    }
    _ => ()
  }
  self.transform.decode_data(b)
}

///|
fn vmap_at(enc : EncodingData, v : Int32) -> Int32 {
  if v < 0 || v >= enc.vertex_values.length() {
    0x7fffffff
  } else {
    enc.vertex_values[v]
  }
}

///|
/// `ComputeParallelogramPrediction` into `out[o, o + nc)`.
fn parallelogram(
  id : Int32,
  ci : Int32,
  t : Table,
  enc : EncodingData,
  data : FixedArray[Int32],
  nc : Int32,
  out : FixedArray[Int32],
  o : Int32,
) -> Bool {
  let oci = t.opposite(ci)
  if oci < 0 {
    return false
  }
  let opp = vmap_at(enc, t.vertex(oci))
  let nxt = vmap_at(enc, t.vertex(next(oci)))
  let prv = vmap_at(enc, t.vertex(previous(oci)))
  if opp < id && nxt < id && prv < id {
    for c in 0..<nc {
      out[o + c] = data[nxt * nc + c] + data[prv * nc + c] - data[opp * nc + c]
    }
    return true
  }
  false
}

///|
fn Scheme::delta(
  self : Scheme,
  data : FixedArray[Int32],
  size : Int32,
  nc : Int32,
) -> Bool {
  let t = self.transform
  t.init(nc)
  t.compute(FixedArray::make(nc, 0), 0, data, 0, data, 0)
  let mut i = nc
  while i < size {
    t.compute(data, i - nc, data, i, data, i)
    i += nc
  }
  true
}

///|
fn Scheme::parallelograms(
  self : Scheme,
  table : Table,
  data : FixedArray[Int32],
  nc : Int32,
) -> Bool {
  let t = self.transform
  let enc = self.enc
  let n = enc.corners.length()
  let limit = table.face_count() * 3 + 1
  t.init(nc)
  let pred = FixedArray::make(4 * nc, 0)
  let multi = FixedArray::make(nc, 0)
  t.compute(pred, 0, data, 0, data, 0)
  let crease_pos = FixedArray::make(4, 0)
  for p in 1..<n {
    let start = enc.corners[p]
    let dst = p * nc
    let src = (p - 1) * nc
    match self.predictor {
      PREDICTION_PARALLELOGRAM =>
        if parallelogram(p, start, table, enc, data, nc, pred, 0) {
          t.compute(pred, 0, data, dst, data, dst)
        } else {
          t.compute(data, src, data, dst, data, dst)
        }
      PREDICTION_MULTI_PARALLELOGRAM => {
        let mut corner = start
        let mut count = 0
        for c in 0..<nc {
          multi[c] = 0
        }
        let mut steps = 0
        while corner >= 0 {
          if parallelogram(p, corner, table, enc, data, nc, pred, 0) {
            for c in 0..<nc {
              multi[c] = multi[c] + pred[c]
            }
            count += 1
          }
          corner = table.swing_right(corner)
          if corner == start {
            corner = -1
          }
          steps += 1
          guard steps <= limit else { return false }
        }
        if count == 0 {
          t.compute(data, src, data, dst, data, dst)
        } else {
          for c in 0..<nc {
            multi[c] = multi[c] / count
          }
          t.compute(multi, 0, data, dst, data, dst)
        }
      }
      _ => {
        let mut corner = start
        let mut count = 0
        let mut first_pass = true
        let mut steps = 0
        while corner >= 0 {
          if parallelogram(p, corner, table, enc, data, nc, pred, count * nc) {
            count += 1
            if count == 4 {
              break
            }
          }
          corner = if first_pass {
            table.swing_left(corner)
          } else {
            table.swing_right(corner)
          }
          if corner == start {
            break
          }
          if corner < 0 && first_pass {
            first_pass = false
            corner = table.swing_right(start)
          }
          steps += 1
          guard steps <= limit else { return false }
        }
        let mut used = 0
        if count > 0 {
          for c in 0..<nc {
            multi[c] = 0
          }
          for i in 0..<count {
            let context = count - 1
            let pos = crease_pos[context]
            crease_pos[context] = pos + 1
            guard pos < self.crease[context].length() else { return false }
            if !self.crease[context][pos] {
              used += 1
              for c in 0..<nc {
                multi[c] = multi[c] + pred[i * nc + c]
              }
            }
          }
        }
        if used == 0 {
          t.compute(data, src, data, dst, data, dst)
        } else {
          for c in 0..<nc {
            multi[c] = multi[c] / used
          }
          t.compute(multi, 0, data, dst, data, dst)
        }
      }
    }
  }
  true
}

///|
/// `ComputeOriginalValues` of `data[0, size)` in place.
fn Scheme::compute(
  self : Scheme,
  data : FixedArray[Int32],
  size : Int32,
  nc : Int32,
  points : Array[Int32],
) -> Bool {
  guard self.table is Some(table) else { return self.delta(data, size, nc) }
  let per_entry = if self.predictor == PREDICTION_GEOMETRIC_NORMAL ||
    self.predictor == PREDICTION_TEX_COORDS_PORTABLE ||
    self.predictor == PREDICTION_TEX_COORDS_DEPRECATED {
    2
  } else {
    nc
  }
  guard self.enc.corners.length() * per_entry <= size else { return false }
  match self.predictor {
    PREDICTION_GEOMETRIC_NORMAL => self.geometric_normal(table, data, points)
    PREDICTION_TEX_COORDS_PORTABLE | PREDICTION_TEX_COORDS_DEPRECATED =>
      self.tex_coords(table, data, nc, points)
    _ => self.parallelograms(table, data, nc)
  }
}
