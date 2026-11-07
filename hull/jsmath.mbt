///|
fn neg_sign(a : Double) -> Bool {
  a.reinterpret_as_int64() < 0L
}

///|
/// JavaScript's `Math.min(a, b)`: NaN if either is, -0 below +0.
fn js_min(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a < b {
    a
  } else if b < a {
    b
  } else if neg_sign(a) {
    a
  } else {
    b
  }
}

///|
/// JavaScript's `Math.max(a, b)`: NaN if either is, +0 above -0.
fn js_max(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() {
    @double.not_a_number
  } else if a > b {
    a
  } else if b > a {
    b
  } else if neg_sign(a) {
    b
  } else {
    a
  }
}

///|
/// Stable merge sort by `cmp(a, b) < 0`, which orders as V8's TimSort does for
/// a consistent comparator.
fn[T] stable_sort(arr : Array[T], cmp : (T, T) -> Double) -> Unit {
  let n = arr.length()
  if n < 2 {
    return
  }
  if n <= 32 {
    for i in 1..<n {
      let x = arr[i]
      let mut j = i
      while j > 0 && cmp(x, arr[j - 1]) < 0.0 {
        arr[j] = arr[j - 1]
        j -= 1
      }
      arr[j] = x
    }
    return
  }
  let mut src = arr.copy()
  let mut dst = arr.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while k < hi {
        if j < hi && (i >= mid || cmp(src[j], src[i]) < 0.0) {
          dst[k] = src[j]
          j += 1
        } else {
          dst[k] = src[i]
          i += 1
        }
        k += 1
      }
      lo = hi
    }
    let tmp = src
    src = dst
    dst = tmp
    width *= 2
  }
  for i in 0..<n {
    arr[i] = src[i]
  }
}
