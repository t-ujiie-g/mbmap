///|
/// Most points `dbscan` and `kmeans` take (AGENTS.md §8.2).
pub const MAX_CLUSTER_POINTS : Int32 = 1_000_000

///|
/// The rows Turf clusters (Point rows with a coordinate, the first one if
/// several) and their coordinates; None past `MAX_CLUSTER_POINTS`.
priv struct Points {
  rows : FixedArray[Int32]
  xs : FixedArray[Double]
  ys : FixedArray[Double]
}

///|
fn first_point(t : @geom.Table, row : Int32) -> Int32? {
  if t.kinds[row] != Point {
    return None
  }
  let (p0, p1) = t.parts(row)
  guard p0 < p1 else { return None }
  let (r0, r1) = t.rings(p0)
  guard r0 < r1 else { return None }
  let (q0, q1) = t.points(r0)
  if q0 < q1 {
    Some(q0)
  } else {
    None
  }
}

///|
fn points_of(t : @geom.Table) -> Points? {
  let mut n = 0
  for row in 0..<t.length() {
    if first_point(t, row) is Some(_) {
      n += 1
    }
  }
  guard n <= MAX_CLUSTER_POINTS else { return None }
  let rows = FixedArray::make(n, 0)
  let xs = FixedArray::make(n, 0.0)
  let ys = FixedArray::make(n, 0.0)
  let mut i = 0
  for row in 0..<t.length() {
    if first_point(t, row) is Some(p) {
      rows[i] = row
      xs[i] = t.coords[2 * p]
      ys[i] = t.coords[2 * p + 1]
      i += 1
    }
  }
  Some({ rows, xs, ys, })
}
