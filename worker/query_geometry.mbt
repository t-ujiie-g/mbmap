// Geometry tests of rendered-feature queries as MapLibre GL JS 6.16.0 makes them
// (feature_index.ts, the style layers' `queryIntersectsFeature`), BSD-3-Clause,
// Copyright (c) 2020 MapLibre contributors; see NOTICE.

///|
/// Lines moved sideways by `offset` tile units (MapLibre's `offsetLine`: each
/// point along its corner's bisector, scaled to keep the segments parallel).
fn offset_line(rings : Array[@core.Line], offset : Double) -> Array[@core.Line] {
  rings.map(raw => {
    let ring : @core.Line = []
    for p in raw {
      if ring.last() is Some(q) && q == p {
        continue
      }
      ring.push(p)
    }
    let unit = (a : (Double, Double), b : (Double, Double)) => {
      let dx = b.0 - a.0
      let dy = b.1 - a.1
      let len = (dx * dx + dy * dy).sqrt()
      (-dy / len, dx / len)
    }
    ring.mapi((i, p) => {
      let ab = if i == 0 { (0.0, 0.0) } else { unit(ring[i - 1], p) }
      let bc = if i == ring.length() - 1 {
        (0.0, 0.0)
      } else {
        unit(p, ring[i + 1])
      }
      let sx = ab.0 + bc.0
      let sy = ab.1 + bc.1
      let len = (sx * sx + sy * sy).sqrt()
      let (ux, uy) = if len > 0.0 { (sx / len, sy / len) } else { (sx, sy) }
      let cos_half = ux * bc.0 + uy * bc.1
      let k = if cos_half != 0.0 { offset / cos_half } else { offset }
      (p.0 + ux * k, p.1 + uy * k)
    })
  })
}

///|
/// MapLibre's `getLineWidth`: a gapped line is the gap and two widths wide.
fn line_width(width : Double, gap : Double) -> Double {
  if gap > 0.0 {
    gap + 2.0 * width
  } else {
    width
  }
}

///|
/// Clip space (x, y, z over w) and w of tile point (x, y) at height `z`.
fn project(
  m : FixedArray[Double],
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double, Double) {
  let w = m[3] * x + m[7] * y + m[11] * z + m[15]
  (
    (m[0] * x + m[4] * y + m[8] * z + m[12]) / w,
    (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
    (m[2] * x + m[6] * y + m[10] * z + m[14]) / w,
    w,
  )
}

///|
/// Feature geometry loaded by `TileProcessor::decode`, as rings in `TILE_EXTENT`
/// units (`f` per feature unit).
fn rings_of(g : @mvt.Geometry, f : Double) -> Array[@core.Line] {
  Array::makei(g.num_rings(), r => {
    Array::makei(g.ring_ends[r] - g.ring_start(r), k => {
      let p = g.ring_start(r) + k
      (g.coords[p * 2].to_double() * f, g.coords[p * 2 + 1].to_double() * f)
    })
  })
}

///|
/// The box around `points`: min x, min y, max x, max y.
fn box_of(points : @core.Line) -> (Double, Double, Double, Double) {
  points.fold(
    init=(
      @double.infinity, @double.infinity, @double.neg_infinity, @double.neg_infinity,
    ),
    (b, p) => {
      (
        @cmp.minimum(b.0, p.0),
        @cmp.minimum(b.1, p.1),
        @cmp.maximum(b.2, p.0),
        @cmp.maximum(b.3, p.1),
      )
    },
  )
}

///|
/// Whether a feature with these rings is in MapLibre's index of the tile and
/// found by the query: some ring's box overlaps the tile, and one grown by
/// `pad` overlaps the query's box (or, for an extrusion, the camera polygon).
fn near_query(
  rings : Array[@core.Line],
  query : Query,
  pad : Double,
  extruded : Bool,
) -> Bool {
  let extent = @core.TILE_EXTENT.to_double()
  let boxes = rings
    .map(box_of)
    .filter(b => b.0 < extent && b.1 < extent && b.2 >= 0.0 && b.3 >= 0.0)
  if extruded {
    return boxes
      .iter()
      .any(b => {
        @core.polygon_hits_box(
          query.camera,
          b.0 - pad,
          b.1 - pad,
          b.2 + pad,
          b.3 + pad,
        )
      })
  }
  let (qx0, qy0, qx1, qy1) = box_of(query.polygon)
  boxes
  .iter()
  .any(b => {
    b.0 <= qx1 + pad && b.2 >= qx0 - pad && b.1 <= qy1 + pad && b.3 >= qy0 - pad
  })
}

///|
/// How far from the camera an extrusion with these rings, between heights
/// `base` and `top` (world pixels), meets the query (clip z; smaller is
/// nearer), or None if it does not (MapLibre's `checkIntersection`).
fn extrusion_hit(
  query : Query,
  rings : Array[@core.Line],
  base : Double,
  top : Double,
) -> Double? {
  let m = query.matrix
  let q = query.polygon.map(p => {
    let (x, y, _, _) = project(m, p.0, p.1, 0.0)
    (x, y)
  })
  let lift = (z : Double) => {
    rings.map(ring => ring.map(p => project(m, p.0, p.1, z)))
  }
  let bases = lift(base)
  let tops = lift(top)
  let flat = (r : Array[(Double, Double, Double, Double)]) => {
    r.map(p => (p.0, p.1))
  }
  let mut closest = @double.infinity
  if @core.polygon_hits_polygons(q, tops.map(flat)) {
    closest = face_distance(q, tops[0])
  }
  for r, ring in tops {
    for k in 0..<(ring.length() - 1) {
      let face = [ring[k], ring[k + 1], bases[r][k + 1], bases[r][k], ring[k]]
      if @core.polygon_hits_polygon(q, flat(face)) {
        closest = @cmp.minimum(closest, face_distance(q, face))
      }
    }
  }
  if closest == @double.infinity {
    None
  } else {
    Some(closest)
  }
}

///|
/// MapLibre's `getIntersectionDistance`: for a point, the depth where it meets
/// the face's plane; for a box, the face's nearest corner.
fn face_distance(
  q : @core.Line,
  face : Array[(Double, Double, Double, Double)],
) -> Double {
  if q.length() != 1 {
    return face.iter().map(p => p.2).fold(init=@double.infinity, @cmp.minimum)
  }
  guard face.length() > 0 else { return @double.infinity }
  let a = face[0]
  let mut i = 1
  while i < face.length() && face[i].0 == a.0 && face[i].1 == a.1 {
    i += 1
  }
  guard i < face.length() else { return @double.infinity }
  let b = face[i]
  let p = q[0]
  for c in face[i + 1:] {
    let (abx, aby) = (b.0 - a.0, b.1 - a.1)
    let (acx, acy) = (c.0 - a.0, c.1 - a.1)
    let (apx, apy) = (p.0 - a.0, p.1 - a.1)
    let ab_ab = abx * abx + aby * aby
    let ab_ac = abx * acx + aby * acy
    let ac_ac = acx * acx + acy * acy
    let ap_ab = apx * abx + apy * aby
    let ap_ac = apx * acx + apy * acy
    let denom = ab_ab * ac_ac - ab_ac * ab_ac
    let v = (ac_ac * ap_ab - ab_ac * ap_ac) / denom
    let w = (ab_ab * ap_ac - ab_ac * ap_ab) / denom
    let distance = a.2 * (1.0 - v - w) + b.2 * v + c.2 * w
    if !distance.is_nan() && !distance.is_inf() {
      return distance
    }
  }
  @double.infinity
}
