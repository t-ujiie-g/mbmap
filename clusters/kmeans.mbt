// @turf/clusters-kmeans 7.4.0 (MIT License, Copyright (c) 2017 TurfJS) with
// skmeans 0.9.7 (MIT License, David Gómez Matarrodona). See NOTICE.

///|
/// skmeans' iteration cap (`MAX`).
const MAX_ITERATIONS : Int32 = 10000

///|
/// Most point-to-centroid distances `kmeans` computes over all its iterations
/// (AGENTS.md §8.2); past them it gives None.
pub const MAX_KMEANS_DISTANCES : Int64 = 10_000_000_000

///|
/// skmeans' `v || 0`: NaN and zero are 0.
fn or_zero(v : Double) -> Double {
  if v.is_nan() || v == 0.0 {
    0.0
  } else {
    v
  }
}

///|
/// `@turf/clusters-kmeans` over `t`'s Point rows (`k` <= 0 is Turf's default):
/// per row its cluster (-1 for other rows) and each centroid as x, y. None past
/// `MAX_CLUSTER_POINTS` or `MAX_KMEANS_DISTANCES`.
pub fn kmeans(
  t : @geom.Table,
  k : Int32,
) -> (FixedArray[Int32], FixedArray[Double])? {
  kmeans_within(t, k, MAX_KMEANS_DISTANCES)
}

///|
fn kmeans_within(
  t : @geom.Table,
  k : Int32,
  max_distances : Int64,
) -> (FixedArray[Int32], FixedArray[Double])? {
  guard points_of(t) is Some(pts) else { return None }
  let out = FixedArray::make(t.length(), -1)
  let n = pts.rows.length()
  guard n > 0 else { return Some((out, [])) }
  let k = if k <= 0 {
    @core.js_round((n.to_double() / 2.0).sqrt()).to_int()
  } else {
    k
  }
  let k = if k > n { n } else { k }
  guard skmeans(pts.xs, pts.ys, k, max_distances) is Some((idxs, centroids)) else {
    return None
  }
  for i in 0..<n {
    out[pts.rows[i]] = idxs[i]
  }
  Some((out, centroids))
}

///|
/// skmeans with the first `k` points as initial centroids, on two
/// dimensions: each point's centroid index, and the centroids. None once its
/// distances would pass `max_distances`.
fn skmeans(
  xs : FixedArray[Double],
  ys : FixedArray[Double],
  k : Int32,
  max_distances : Int64,
) -> (FixedArray[Int32], FixedArray[Double])? {
  let n = xs.length()
  let cx = FixedArray::makei(k, j => xs[j])
  let cy = FixedArray::makei(k, j => ys[j])
  let old_x = FixedArray::make(k, 0.0)
  let old_y = FixedArray::make(k, 0.0)
  let sum_x = FixedArray::make(k, 0.0)
  let sum_y = FixedArray::make(k, 0.0)
  let count = FixedArray::make(k, 0)
  let idxs = FixedArray::make(n, 0)
  let mut it = MAX_ITERATIONS
  let per_iteration = n.to_int64() * k.to_int64()
  let mut distances = 0L
  while true {
    distances += per_iteration
    guard distances <= max_distances else { return None }
    count.fill(0)
    for i in 0..<n {
      let x = or_zero(xs[i])
      let y = or_zero(ys[i])
      let mut min = @double.infinity
      let mut idx = 0
      for j in 0..<k {
        let dx = x - or_zero(cx[j])
        let dy = y - or_zero(cy[j])
        let d = dx * dx + dy * dy
        if d <= min {
          min = d
          idx = j
        }
      }
      idxs[i] = idx
      count[idx] += 1
    }
    sum_x.fill(0.0)
    sum_y.fill(0.0)
    for i in 0..<n {
      sum_x[idxs[i]] += xs[i]
      sum_y[idxs[i]] += ys[i]
    }
    let mut conv = true
    for j in 0..<k {
      old_x[j] = cx[j]
      old_y[j] = cy[j]
      let c = count[j].to_double()
      cx[j] = or_zero(sum_x[j] / c)
      cy[j] = or_zero(sum_y[j] / c)
      if conv && (old_x[j] != cx[j] || old_y[j] != cy[j]) {
        conv = false
      }
    }
    it -= 1
    if conv || it <= 0 {
      break
    }
  }
  let centroids = FixedArray::make(2 * k, 0.0)
  for j in 0..<k {
    centroids[2 * j] = cx[j]
    centroids[2 * j + 1] = cy[j]
  }
  Some((idxs, centroids))
}
