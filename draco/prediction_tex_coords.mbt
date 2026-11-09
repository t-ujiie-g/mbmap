// Ported from Draco 1.5.7 (compression/attributes/prediction_schemes/: the tex coords decoders,
// portable and deprecated): Apache License 2.0, Copyright 2016 The Draco Authors. See NOTICE.

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
