///|
/// An index over the features' boxes (`bbox`); features without geometry get
/// an inverted box that no search finds.
pub fn Index::of_table(t : @geom.Table) -> Index {
  let index = Index::new(t.length())
  let c = t.coords
  for f in 0..<t.length() {
    let (a, b) = point_range(t, f)
    let mut x0 = @double.infinity
    let mut y0 = @double.infinity
    let mut x1 = @double.neg_infinity
    let mut y1 = @double.neg_infinity
    for i in a..<b {
      let x = c[i * 2]
      let y = c[i * 2 + 1]
      if x0 > x {
        x0 = x
      }
      if y0 > y {
        y0 = y
      }
      if x1 < x {
        x1 = x
      }
      if y1 < y {
        y1 = y
      }
    }
    index.add(x0, y0, x1, y1) |> ignore
  }
  index.finish() |> ignore
  index
}

///|
/// Calls `f` with each point of Point and MultiPoint feature `i`.
fn each_point(t : @geom.Table, i : Int32, f : (Double, Double) -> Bool) -> Unit {
  guard t.kinds[i] is (Point | MultiPoint) else { return }
  let (a, b) = point_range(t, i)
  for p in a..<b {
    if !f(t.coords[p * 2], t.coords[p * 2 + 1]) {
      return
    }
  }
}

///|
/// Whether (x, y) is in any polygon of `polygons` among `candidates`.
fn in_any(
  polygons : @geom.Table,
  candidates : Array[Int32],
  x : Double,
  y : Double,
) -> Bool {
  for f in candidates {
    if contains_point(polygons, f, x, y) {
      return true
    }
  }
  false
}

///|
/// Point and MultiPoint features of `points` with a point in some polygon of
/// `polygons` (or on its boundary), in feature order (Turf's
/// `pointsWithinPolygon`, keeping whole features). `index` is
/// `Index::of_table(polygons)`.
pub fn points_within(
  points : @geom.Table,
  polygons : @geom.Table,
  index : Index,
) -> Array[Int32] {
  let out = []
  let candidates = []
  for i in 0..<points.length() {
    let mut inside = false
    each_point(points, i, (x, y) => {
      candidates.clear()
      index.search(x, y, x, y, candidates)
      inside = in_any(polygons, candidates, x, y)
      !inside
    })
    if inside {
      out.push(i)
    }
  }
  out
}

///|
/// Per polygon feature of `polygons`, the Point features of `points` inside
/// it (Turf's `collect`): three numbers each, the count of points, the count
/// of those whose `column` is a number and the sum of those numbers, added in
/// feature order. `index` is `Index::of_table(points)`.
pub fn collect(
  polygons : @geom.Table,
  points : @geom.Table,
  index : Index,
  column : String,
) -> FixedArray[Double] {
  let n = polygons.length()
  let out = FixedArray::make(n * 3, 0.0)
  let values = points.column(column).map(c => c.values)
  let hits = []
  for f in 0..<n {
    guard is_polygon(polygons.kinds[f]) else { continue }
    let (x0, y0, x1, y1) = bbox(polygons, f)
    hits.clear()
    index.search(x0, y0, x1, y1, hits)
    hits.sort()
    let mut count = 0
    let mut numbers = 0
    let mut sum = 0.0
    for i in hits {
      guard points.kinds[i] is Point else { continue }
      let (a, _) = point_range(points, i)
      if !contains_point(
          polygons,
          f,
          points.coords[a * 2],
          points.coords[a * 2 + 1],
        ) {
        continue
      }
      count += 1
      if values is Some(v) && v[i] is Some(Num(x)) {
        numbers += 1
        sum += x
      }
    }
    out[f * 3] = count.to_double()
    out[f * 3 + 1] = numbers.to_double()
    out[f * 3 + 2] = sum
  }
  out
}

///|
/// Most cells `grid_count` fills.
pub const MAX_GRID_CELLS : Int32 = 1 << 24

///|
/// Point counts of a `cols` x `rows` grid over the box, row by row from
/// `min_y`; points on the max edges fall in the last cells, points outside
/// are left out. None for an empty box or more than `MAX_GRID_CELLS` cells.
pub fn grid_count(
  t : @geom.Table,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
  cols : Int32,
  rows : Int32,
) -> FixedArray[Int32]? {
  if !(max_x > min_x && max_y > min_y) ||
    cols <= 0 ||
    rows <= 0 ||
    cols > MAX_GRID_CELLS / rows {
    return None
  }
  let out = FixedArray::make(cols * rows, 0)
  let w = (max_x - min_x) / cols.to_double()
  let h = (max_y - min_y) / rows.to_double()
  for i in 0..<t.length() {
    each_point(t, i, (x, y) => {
      if x >= min_x && x <= max_x && y >= min_y && y <= max_y {
        let c = @cmp.minimum(((x - min_x) / w).to_int(), cols - 1)
        let r = @cmp.minimum(((y - min_y) / h).to_int(), rows - 1)
        out[r * cols + c] += 1
      }
      true
    })
  }
  Some(out)
}
