// @turf/clusters-kmeans 7.4.0 (MIT License, Copyright (c) 2017 TurfJS) with
// skmeans 0.9.7 (MIT License, David Gómez Matarrodona). See NOTICE.

///|
/// skmeans' iteration cap (`MAX`).
const MAX_ITERATIONS : Int32 = 10000

///|
/// skmeans' `v || 0`: NaN and zero are 0.
fn or_zero(v : Double) -> Double {
  if is_nan(v) || v == 0.0 {
    0.0
  } else {
    v
  }
}

///|
/// JavaScript's `Math.round` of a non-negative number.
fn js_round(x : Double) -> Double {
  let f = x.floor()
  if x - f >= 0.5 {
    f + 1.0
  } else {
    f
  }
}

///|
/// `@turf/clusters-kmeans` over `t`'s Point rows: per row its
/// `properties.cluster` (-1 for other rows, which take no part), and each
/// cluster's centroid as x, y pairs (`properties.centroid`). `k` <= 0 is
/// Turf's default, `round(sqrt(points / 2))`; past the point count it is the
/// point count. skmeans starts from the first `k` points, so the result is
/// deterministic. None past `MAX_CLUSTER_POINTS`.
pub fn kmeans_checked(
  t : @geom.Table,
  k : Int32,
) -> (FixedArray[Int32], FixedArray[Double])? {
  guard points_of(t) is Some(pts) else { return None }
  let out = FixedArray::make(t.length(), -1)
  let n = pts.rows.length()
  guard n > 0 else { return Some((out, [])) }
  let k = if k <= 0 {
    js_round((n.to_double() / 2.0).sqrt()).to_int()
  } else {
    k
  }
  let k = if k > n { n } else { k }
  let (idxs, centroids) = skmeans(pts.xs, pts.ys, k)
  for i in 0..<n {
    out[pts.rows[i]] = idxs[i]
  }
  Some((out, centroids))
}

///|
/// `kmeans_checked`, with every row -1 and no centroids past
/// `MAX_CLUSTER_POINTS`.
pub fn kmeans(
  t : @geom.Table,
  k : Int32,
) -> (FixedArray[Int32], FixedArray[Double]) {
  match kmeans_checked(t, k) {
    Some(r) => r
    None => (FixedArray::make(t.length(), -1), [])
  }
}

///|
/// skmeans with the first `k` points as initial centroids, on two
/// dimensions: each point's centroid index, and the centroids.
fn skmeans(
  xs : FixedArray[Double],
  ys : FixedArray[Double],
  k : Int32,
) -> (FixedArray[Int32], FixedArray[Double]) {
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
  while true {
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
  (idxs, centroids)
}
