// Ported from Draco 1.5.7 (compression/attributes/prediction_schemes/: the delta, parallelogram,
// multi-parallelogram, constrained multi-parallelogram, tex coords (portable and deprecated) and
// geometric normal decoders): Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

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
fn abs64(x : Int64) -> Int64 {
  if x < 0L {
    -x
  } else {
    x
  }
}

///|
fn max64(a : Int64, b : Int64) -> Int64 {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// `MeshPredictionSchemeTexCoordsPortablePredictor::ComputePredictedValue<false>` into `pred`.
fn Scheme::tex_portable_prediction(
  self : Scheme,
  t : Table,
  corner : Int32,
  data : FixedArray[Int32],
  id : Int32,
  points : Array[Int32],
  pred : FixedArray[Int32],
) -> Bool {
  let next_id = vmap_at(self.enc, t.vertex(next(corner)))
  let prev_id = vmap_at(self.enc, t.vertex(previous(corner)))
  if prev_id < id && next_id < id {
    let nu = data[next_id * 2].to_int64()
    let nv = data[next_id * 2 + 1].to_int64()
    let pu = data[prev_id * 2].to_int64()
    let pv = data[prev_id * 2 + 1].to_int64()
    if pu == nu && pv == nv {
      pred[0] = pu.to_int()
      pred[1] = pv.to_int()
      return true
    }
    guard self.parent is Some(parent) else { return false }
    let tip = FixedArray::make(3, 0L)
    let np = FixedArray::make(3, 0L)
    let pp = FixedArray::make(3, 0L)
    guard id < points.length() &&
      parent.position(points[id], tip) &&
      parent.position(points[next_id], np) &&
      parent.position(points[prev_id], pp) else {
      return false
    }
    let pn0 = pp[0] - np[0]
    let pn1 = pp[1] - np[1]
    let pn2 = pp[2] - np[2]
    let pn_norm2 = (pn0 * pn0 + pn1 * pn1 + pn2 * pn2).reinterpret_as_uint64()
    if pn_norm2 != 0UL {
      let cn0 = tip[0] - np[0]
      let cn1 = tip[1] - np[1]
      let cn2 = tip[2] - np[2]
      let cn_dot_pn = pn0 * cn0 + pn1 * cn1 + pn2 * cn2
      let pnu = pu - nu
      let pnv = pv - nv
      let n_absmax = max64(abs64(nu), abs64(nv))
      if n_absmax.reinterpret_as_uint64() > 0x7fffffffffffffffUL / pn_norm2 {
        return false
      }
      let pn_uv_absmax = max64(abs64(pnu), abs64(pnv))
      if abs64(cn_dot_pn) > 0x7fffffffffffffffL / pn_uv_absmax {
        return false
      }
      let norm = pn_norm2.reinterpret_as_int64()
      let xu = nu * norm + cn_dot_pn * pnu
      let xv = nv * norm + cn_dot_pn * pnv
      let pn_absmax = max64(max64(abs64(pn0), abs64(pn1)), abs64(pn2))
      if abs64(cn_dot_pn) > 0x7fffffffffffffffL / pn_absmax {
        return false
      }
      let xp0 = np[0] + cn_dot_pn * pn0 / norm
      let xp1 = np[1] + cn_dot_pn * pn1 / norm
      let xp2 = np[2] + cn_dot_pn * pn2 / norm
      let d0 = tip[0] - xp0
      let d1 = tip[1] - xp1
      let d2 = tip[2] - xp2
      let cx_norm2 = (d0 * d0 + d1 * d1 + d2 * d2).reinterpret_as_uint64()
      let s = int_sqrt(cx_norm2 * pn_norm2).reinterpret_as_int64()
      let cxu = pnv * s
      let cxv = -pnu * s
      guard self.pop_orientation() is Some(orientation) else { return false }
      let (u, v) = if orientation {
        (xu + cxu, xv + cxv)
      } else {
        (xu - cxu, xv - cxv)
      }
      pred[0] = (u / norm).to_int()
      pred[1] = (v / norm).to_int()
      return true
    }
  }
  fallback(data, id, prev_id, next_id, 2, pred)
}

///|
/// The predictions' fallback when not every neighbour is decoded: the last of them that is, or
/// the previous entry.
fn fallback(
  data : FixedArray[Int32],
  id : Int32,
  prev_id : Int32,
  next_id : Int32,
  nc : Int32,
  pred : FixedArray[Int32],
) -> Bool {
  let mut offset = 0
  if prev_id < id {
    offset = prev_id * nc
  }
  if next_id < id {
    offset = next_id * nc
  } else if id > 0 {
    offset = (id - 1) * nc
  } else {
    for i in 0..<nc {
      pred[i] = 0
    }
    return true
  }
  for i in 0..<nc {
    pred[i] = data[offset + i]
  }
  true
}

///|
/// `IntSqrt`.
fn int_sqrt(number : UInt64) -> UInt64 {
  if number == 0UL {
    return 0
  }
  let mut act = number
  let mut root = 1UL
  while act >= 2UL {
    root = root * 2
    act = act / 4
  }
  while true {
    root = (root + number / root) / 2
    if root * root <= number {
      break
    }
  }
  root
}

///|
/// The deprecated tex coords scheme's prediction (`MeshPredictionSchemeTexCoordsDecoder`).
fn Scheme::tex_deprecated_prediction(
  self : Scheme,
  t : Table,
  corner : Int32,
  data : FixedArray[Int32],
  id : Int32,
  points : Array[Int32],
  pred : FixedArray[Int32],
) -> Bool {
  let next_id = vmap_at(self.enc, t.vertex(next(corner)))
  let prev_id = vmap_at(self.enc, t.vertex(previous(corner)))
  if prev_id < id && next_id < id {
    let nu = Float::from_int(data[next_id * 2])
    let nv = Float::from_int(data[next_id * 2 + 1])
    let pu = Float::from_int(data[prev_id * 2])
    let pv = Float::from_int(data[prev_id * 2 + 1])
    if pu == nu && pv == nv {
      pred[0] = to_int_or_min(pu.to_double())
      pred[1] = to_int_or_min(pv.to_double())
      return true
    }
    guard self.parent is Some(parent) else { return false }
    let tip = FixedArray::make(3, 0L)
    let np = FixedArray::make(3, 0L)
    let pp = FixedArray::make(3, 0L)
    guard id < points.length() &&
      parent.position(points[id], tip) &&
      parent.position(points[next_id], np) &&
      parent.position(points[prev_id], pp) else {
      return false
    }
    let f = fn(x : Int64) { Float::from_int(x.to_int()) }
    let pn0 = f(pp[0]) - f(np[0])
    let pn1 = f(pp[1]) - f(np[1])
    let pn2 = f(pp[2]) - f(np[2])
    let cn0 = f(tip[0]) - f(np[0])
    let cn1 = f(tip[1]) - f(np[1])
    let cn2 = f(tip[2]) - f(np[2])
    let pn_norm2 = pn0 * pn0 + pn1 * pn1 + pn2 * pn2
    let mut s : Float = 0.0
    let mut tt : Float = 0.0
    if pn_norm2 > 0.0 {
      s = ((0.0 : Float) + pn0 * cn0 + pn1 * cn1 + pn2 * cn2) / pn_norm2
      let r0 = cn0 - pn0 * s
      let r1 = cn1 - pn1 * s
      let r2 = cn2 - pn2 * s
      tt = ((r0 * r0 + r1 * r1 + r2 * r2) / pn_norm2).sqrt()
    }
    let pnu = pu - nu
    let pnv = pv - nv
    let pnus = pnu * s + nu
    let pnut = pnu * tt
    let pnvs = pnv * s + nv
    let pnvt = pnv * tt
    guard self.pop_orientation() is Some(orientation) else { return false }
    let (u, v) = if orientation {
      (pnus - pnvt, pnvs + pnut)
    } else {
      (pnus + pnvt, pnvs - pnut)
    }
    pred[0] = to_int_or_min((u.to_double() + 0.5).floor())
    pred[1] = to_int_or_min((v.to_double() + 0.5).floor())
    return true
  }
  fallback(data, id, prev_id, next_id, 2, pred)
}

///|
/// `static_cast<int>` of a double, or `INT_MIN` for NaN and values out of range (as the
/// deprecated tex coords scheme guards it).
fn to_int_or_min(x : Double) -> Int32 {
  if x.is_nan() || x > 2147483647.0 || x < -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
fn Scheme::tex_coords(
  self : Scheme,
  t : Table,
  data : FixedArray[Int32],
  nc : Int32,
  points : Array[Int32],
) -> Bool {
  guard nc == 2 else { return false }
  self.transform.init(nc)
  let pred = FixedArray::make(2, 0)
  let corners = self.enc.corners
  for p in 0..<corners.length() {
    let ok = if self.predictor == PREDICTION_TEX_COORDS_PORTABLE {
      self.tex_portable_prediction(t, corners[p], data, p, points, pred)
    } else {
      self.tex_deprecated_prediction(t, corners[p], data, p, points, pred)
    }
    guard ok else { return false }
    self.transform.compute(pred, 0, data, p * 2, data, p * 2)
  }
  true
}

///|
fn Scheme::position_of_corner(
  self : Scheme,
  t : Table,
  parent : Parent,
  points : Array[Int32],
  c : Int32,
  out : FixedArray[Int64],
) -> Bool {
  let v = t.vertex(c)
  guard v >= 0 && v < self.enc.vertex_values.length() else { return false }
  let id = self.enc.vertex_values[v]
  guard id >= 0 && id < points.length() else { return false }
  parent.position(points[id], out)
}

///|
fn sat_abs_sum(a : Int64, b : Int64, c : Int64) -> Int64 {
  let mut result = 0L
  for x in [a, b, c] {
    let v = abs64(x)
    if result > 0x7fffffffffffffffL - v {
      return 0x7fffffffffffffffL
    }
    result = result + v
  }
  result
}

///|
/// `MeshPredictionSchemeGeometricNormalDecoder::ComputeOriginalValues`.
fn Scheme::geometric_normal(
  self : Scheme,
  t : Table,
  data : FixedArray[Int32],
  points : Array[Int32],
) -> Bool {
  let tb = Toolbox::new()
  let _ = tb.set_bits(self.transform.bits())
  guard self.parent is Some(parent) else { return false }
  let limit = t.face_count() * 3 + 1
  let cent = FixedArray::make(3, 0L)
  let pn = FixedArray::make(3, 0L)
  let pp = FixedArray::make(3, 0L)
  let normal3 = FixedArray::make(3, 0)
  let oct = FixedArray::make(2, 0)
  let corners = self.enc.corners
  for data_id in 0..<corners.length() {
    let corner = corners[data_id]
    guard self.position_of_corner(t, parent, points, corner, cent) else {
      return false
    }
    let mut n0 = 0L
    let mut n1 = 0L
    let mut n2 = 0L
    let mut c = corner
    let mut left = true
    let mut steps = 0
    while c >= 0 {
      let (c_next, c_prev) = if self.normal_mode == 0 {
        (next(corner), previous(corner))
      } else {
        (next(c), previous(c))
      }
      guard self.position_of_corner(t, parent, points, c_next, pn) &&
        self.position_of_corner(t, parent, points, c_prev, pp) else {
        return false
      }
      let dn0 = pn[0] - cent[0]
      let dn1 = pn[1] - cent[1]
      let dn2 = pn[2] - cent[2]
      let dp0 = pp[0] - cent[0]
      let dp1 = pp[1] - cent[1]
      let dp2 = pp[2] - cent[2]
      n0 = n0 + (dn1 * dp2 - dn2 * dp1)
      n1 = n1 + (dn2 * dp0 - dn0 * dp2)
      n2 = n2 + (dn0 * dp1 - dn1 * dp0)
      if left {
        c = t.swing_left(c)
        if c < 0 {
          c = t.swing_right(corner)
          left = false
        } else if c == corner {
          c = -1
        }
      } else {
        c = t.swing_right(c)
      }
      steps += 1
      guard steps <= limit else { return false }
    }
    let upper_bound = 0x20000000L
    let abs_sum = if self.normal_mode == 0 {
      sat_abs_sum(n0, n1, n2).to_int().to_int64()
    } else {
      sat_abs_sum(n0, n1, n2)
    }
    if abs_sum > upper_bound {
      let quotient = abs_sum / upper_bound
      n0 = n0 / quotient
      n1 = n1 / quotient
      n2 = n2 / quotient
    }
    normal3[0] = n0.to_int()
    normal3[1] = n1.to_int()
    normal3[2] = n2.to_int()
    tb.canonicalize_vector(normal3)
    if self.flip.bit() {
      normal3[0] = -normal3[0]
      normal3[1] = -normal3[1]
      normal3[2] = -normal3[2]
    }
    tb.vector_to_coords(normal3, oct)
    guard data_id * 2 + 2 <= data.length() else { return false }
    self.transform.compute(oct, 0, data, data_id * 2, data, data_id * 2)
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
