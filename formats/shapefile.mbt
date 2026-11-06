// Ported from shpjs 6.2.0 and parsedbf 2.0.0: MIT License, Copyright (c) 2013 Calvin Metcalf
// and other shapefile-js contributors. See NOTICE.

///|
/// Reads a shapefile's .shp and .dbf into a row per record not deleted (npm/README.md
/// `mbmap/data`). `text` decodes `dbf[start:end]` where it is not ASCII, in the .dbf's
/// encoding; `slow_number` parses its numbers past the fast path, as `read_csv`'s.
pub fn read_shapefile(
  shp : BytesView,
  dbf : BytesView?,
  text~ : (Int32, Int32) -> String,
  slow_number~ : (Int32, Int32) -> Double,
) -> @geom.Table raise ReadError {
  shapefile_table(shp, dbf, text, slow_number, MAX_POINTS, MAX_DBF_CELLS)
}

///|
fn be_i32(b : BytesView, i : Int32) -> Int32 {
  (b[i].to_int() << 24) |
  (b[i + 1].to_int() << 16) |
  (b[i + 2].to_int() << 8) |
  b[i + 3].to_int()
}

///|
fn le_f64(b : BytesView, i : Int32) -> Double {
  let mut bits = 0UL
  for k in 0..<8 {
    bits = bits | (b[i + k].to_uint64() << (k * 8))
  }
  bits.reinterpret_as_double()
}

///|
fn shp_error(pos : Int32, m : String) -> ReadError {
  Invalid(format="shapefile", pos~, m)
}

///|
/// `read_shapefile` taking at most `max_points` points and `max_cells` DBF cells.
fn shapefile_table(
  shp : BytesView,
  dbf : BytesView?,
  text : (Int32, Int32) -> String,
  slow : (Int32, Int32) -> Double,
  max_points : Int32,
  max_cells : Int32,
) -> @geom.Table raise ReadError {
  guard shp.length() >= 100 && be_i32(shp, 0) == 9994 else {
    raise shp_error(0, "not a shapefile")
  }
  base_type(le_i32(shp, 32), 32) |> ignore
  let table = match dbf {
    Some(d) => Some(Dbf::new(d, text, max_cells))
    None => None
  }
  let out = @geom.TableBuilder::new()
  let rings = Rings::new(MAX_RING_STEPS)
  let mut pos = 100
  let mut row = 0
  while pos + 8 <= shp.length() {
    let words = be_i32(shp, pos + 4)
    guard words >= 0 && words <= (shp.length() - pos - 8) / 2 else {
      raise shp_error(pos, "a record past the end of the file")
    }
    let start = pos + 8
    let end = start + words * 2
    pos = end
    let deleted = match table {
      Some(t) => row < t.count && t.deleted(row)
      None => false
    }
    if !deleted {
      let kind = if words == 0 {
        @geom.GeomKind::NoGeometry
      } else {
        shape(shp[start:end], start, out, rings, max_points)
      }
      if table is Some(t) && row < t.count {
        t.props(row, out, text, slow)
      }
      out.end_feature(kind)
    }
    row += 1
  }
  out.finish()
}

///|
/// The XY type of shape type `code` (read at `at`): 0 (null), 1 (point), 3 (line), 5
/// (polygon) or 8 (multipoint), of their Z and M types too.
fn base_type(code : Int32, at : Int32) -> Int32 raise ReadError {
  match code {
    0 | 1 | 3 | 5 | 8 => code
    11 | 13 | 15 | 18 | 21 | 23 | 25 | 28 => code % 10
    31 => raise shp_error(at, "MultiPatch shapes are not supported")
    _ => raise shp_error(at, "unsupported shape type \{code}")
  }
}

///|
/// Writes the shape of a record's content `c` (at `at` in the file) to `out` and
/// returns its kind.
fn shape(
  c : BytesView,
  at : Int32,
  out : @geom.TableBuilder,
  rings : Rings,
  max_points : Int32,
) -> @geom.GeomKind raise ReadError {
  guard c.length() >= 4 else { raise shp_error(at, "a record cut short") }
  let base = base_type(le_i32(c, 0), at)
  let need = match base {
    0 => return NoGeometry
    1 => 20
    8 => 40
    _ => 44
  }
  guard c.length() >= need else { raise shp_error(at, "a record cut short") }
  let used = out.table.coords.length() / 2
  let (parts, count, points_at) = match base {
    1 => (1, 1, 4)
    8 => (1, le_i32(c, 36), 40)
    _ => {
      let parts = le_i32(c, 36)
      (parts, le_i32(c, 40), 44 + 4 * @cmp.maximum(parts, 0))
    }
  }
  guard parts >= 0 &&
    count >= 0 &&
    parts <= c.length() / 4 &&
    count <= (c.length() - points_at) / 16 else {
    raise shp_error(at, "counts past the end of the record")
  }
  guard used + count <= max_points else {
    raise shp_error(at, "too many points")
  }
  if base == 1 {
    let (x, y) = (le_f64(c, 4), le_f64(c, 12))
    if x.is_nan() && y.is_nan() {
      return NoGeometry
    }
  }
  if count == 0 || parts == 0 {
    return NoGeometry
  }
  rings.clear()
  for i in 0..<count {
    let (x, y) = (
      le_f64(c, points_at + i * 16),
      le_f64(c, points_at + i * 16 + 8),
    )
    guard !(x.is_nan() || y.is_nan() || x.is_inf() || y.is_inf()) else {
      raise shp_error(at + points_at + i * 16, "coordinates must be finite")
    }
    rings.coords.push(x)
    rings.coords.push(y)
  }
  if base == 1 || base == 8 {
    for i in 0..<count {
      out.point(rings.coords[i * 2], rings.coords[i * 2 + 1])
    }
    out.end_ring()
    out.end_part()
    return if count == 1 { Point } else { MultiPoint }
  }
  let mut last = 0
  for k in 0..<parts {
    let first = le_i32(c, 44 + 4 * k)
    guard first >= last && first <= count else {
      raise shp_error(at + 44 + 4 * k, "invalid part start")
    }
    if k > 0 {
      rings.ring(last, first)
    }
    last = first
  }
  rings.ring(last, count)
  if base == 3 {
    for r in rings.rings {
      for i in r.start..<r.end {
        out.point(rings.coords[i * 2], rings.coords[i * 2 + 1])
      }
      out.end_ring()
      out.end_part()
    }
    return if rings.rings.length() == 1 { LineString } else { MultiLineString }
  }
  let kind = rings.write_polygons(out)
  guard !rings.spent() else {
    raise shp_error(at, "too many rings to tell apart")
  }
  kind
}

///|
/// Most ring and point comparisons telling holes from outer rings in one file: a
/// budget, as nothing else bounds holes times outer rings' points.
const MAX_RING_STEPS : Int64 = 0x400000000

///|
/// A polygon's rings while they are told apart: `start`, `end` (points into
/// `coords`), the bounding box, `cw` (clockwise, which shapefiles make outer rings),
/// `area` (absolute) and, once assigned, `outer` (the ring a hole lies in, or -1).
priv struct Ring {
  start : Int32
  end : Int32
  box : FixedArray[Double]
  cw : Bool
  area : Double
  mut outer : Int32
}

///|
priv struct Rings {
  coords : Array[Double]
  rings : Array[Ring]
  mut steps : Int64
  max_steps : Int64
}

///|
fn Rings::new(max_steps : Int64) -> Rings {
  { coords: [], rings: [], steps: 0, max_steps, }
}

///|
fn Rings::spent(self : Rings) -> Bool {
  self.steps > self.max_steps
}

///|
fn Rings::clear(self : Rings) -> Unit {
  self.coords.clear()
  self.rings.clear()
}

///|
/// Adds points `start..<end` as a ring, unless there are none.
fn Rings::ring(self : Rings, start : Int32, end : Int32) -> Unit {
  guard end > start else { return }
  let c = self.coords
  let box : FixedArray[Double] = [
    c[start * 2],
    c[start * 2 + 1],
    c[start * 2],
    c[start * 2 + 1],
  ]
  // Twice the signed area, positive for clockwise rings (shpjs's `isClockWise`).
  let mut sum = 0.0
  for i in (start + 1)..<end {
    let (x, y) = (c[i * 2], c[i * 2 + 1])
    sum += (x - c[i * 2 - 2]) * (y + c[i * 2 - 1])
    box[0] = @cmp.minimum(box[0], x)
    box[1] = @cmp.minimum(box[1], y)
    box[2] = @cmp.maximum(box[2], x)
    box[3] = @cmp.maximum(box[3], y)
  }
  self.rings.push({
    start,
    end,
    box,
    cw: sum > 0.0,
    area: sum.abs(),
    outer: -1,
  })
}

///|
/// Where point `(x, y)` lies against ring `r`: 1 inside, 0 outside, -1 on its edge.
fn Rings::locate(self : Rings, r : Ring, x : Double, y : Double) -> Int32 {
  let c = self.coords
  let mut inside = false
  let mut j = r.end - 1
  for i in r.start..<r.end {
    let (xi, yi, xj, yj) = (c[i * 2], c[i * 2 + 1], c[j * 2], c[j * 2 + 1])
    let cross = (xj - xi) * (y - yi) - (x - xi) * (yj - yi)
    if cross == 0.0 &&
      @cmp.minimum(xi, xj) <= x &&
      x <= @cmp.maximum(xi, xj) &&
      @cmp.minimum(yi, yj) <= y &&
      y <= @cmp.maximum(yi, yj) {
      return -1
    }
    if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
      inside = !inside
    }
    j = i
  }
  if inside {
    1
  } else {
    0
  }
}

///|
/// Gives each hole (a ring whose `cw` differs from `outer_cw`) the smallest outer
/// ring that contains it, judged by its first vertex off that ring's edge; returns
/// how many holes no outer ring contains. Stops where `spent`.
fn Rings::assign(self : Rings, outer_cw : Bool) -> Int32 {
  let outers = []
  for k, o in self.rings {
    if o.cw == outer_cw {
      outers.push(k)
    }
  }
  let mut orphans = 0
  for h in self.rings {
    h.outer = -1
    if h.cw == outer_cw {
      continue
    }
    let mut best = -1
    for k in outers {
      let o = self.rings[k]
      self.steps += 1
      if o.box[0] > h.box[0] ||
        o.box[1] > h.box[1] ||
        o.box[2] < h.box[2] ||
        o.box[3] < h.box[3] ||
        (best >= 0 && o.area >= self.rings[best].area) {
        continue
      }
      let mut at = -1
      for i in h.start..<h.end {
        self.steps += (o.end - o.start).to_int64()
        if self.spent() {
          return orphans
        }
        at = self.locate(o, self.coords[i * 2], self.coords[i * 2 + 1])
        if at >= 0 {
          break
        }
      }
      if at != 0 {
        best = k
      }
    }
    h.outer = best
    if best < 0 {
      orphans += 1
    }
  }
  orphans
}

///|
/// Writes the rings as polygons (outer rings counter-clockwise, holes clockwise) and gives
/// the kind. Clockwise rings are outer, unless holes then go astray and the other way
/// round none do (as shpjs reads them); holes still astray are outer rings.
fn Rings::write_polygons(
  self : Rings,
  out : @geom.TableBuilder,
) -> @geom.GeomKind {
  let mut outer_cw = true
  if self.assign(true) > 0 {
    if self.assign(false) == 0 {
      outer_cw = false
    } else {
      self.assign(true) |> ignore
    }
  }
  // Each outer ring's holes as a list in ring order: `first` by outer, `next` by hole.
  let first = Array::make(self.rings.length(), -1)
  let next = Array::make(self.rings.length(), -1)
  for k = self.rings.length() - 1; k >= 0; k = k - 1 {
    let h = self.rings[k]
    if h.outer >= 0 && h.cw != outer_cw {
      next[k] = first[h.outer]
      first[h.outer] = k
    }
  }
  let mut polygons = 0
  for k, o in self.rings {
    if o.cw != outer_cw && o.outer >= 0 {
      continue
    }
    self.write_ring(out, o, false)
    for h = first[k]; h >= 0; h = next[h] {
      self.write_ring(out, self.rings[h], true)
    }
    out.end_part()
    polygons += 1
  }
  if polygons == 1 {
    Polygon
  } else {
    MultiPolygon
  }
}

///|
/// Writes ring `r` clockwise if `cw`, else counter-clockwise (a ring of no area as it is).
fn Rings::write_ring(
  self : Rings,
  out : @geom.TableBuilder,
  r : Ring,
  cw : Bool,
) -> Unit {
  let reverse = r.area > 0.0 && r.cw != cw
  for n in 0..<(r.end - r.start) {
    let i = if reverse { r.end - 1 - n } else { r.start + n }
    out.point(self.coords[i * 2], self.coords[i * 2 + 1])
  }
  out.end_ring()
}
