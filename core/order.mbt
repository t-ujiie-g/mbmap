///|
/// The indices of `keys` from the smallest key up, ties in index order (a stable
/// merge sort, smaller than core's generic sorts in each wasm module).
pub fn stable_order(keys : ArrayView[Double]) -> FixedArray[Int32] {
  let n = keys.length()
  let mut a = FixedArray::makei(n, i => i)
  let mut b = FixedArray::make(n, 0)
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = @cmp.minimum(lo + width, n)
      let hi = @cmp.minimum(lo + 2 * width, n)
      let mut i = lo
      let mut j = mid
      for k in lo..<hi {
        if i < mid && (j >= hi || !(keys[a[j]] < keys[a[i]])) {
          b[k] = a[i]
          i += 1
        } else {
          b[k] = a[j]
          j += 1
        }
      }
      lo = hi
    }
    let t = a
    a = b
    b = t
    width *= 2
  }
  a
}

///|
/// `arr` sorted in place by `less`, stably: as JavaScript's `Array.prototype.sort`
/// orders for a consistent comparator.
pub fn[T] stable_sort(arr : Array[T], less : (T, T) -> Bool) -> Unit {
  let n = arr.length()
  if n < 2 {
    return
  }
  if n <= 32 {
    for i in 1..<n {
      let x = arr[i]
      let mut j = i
      while j > 0 && less(x, arr[j - 1]) {
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
        if j < hi && (i >= mid || less(src[j], src[i])) {
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
