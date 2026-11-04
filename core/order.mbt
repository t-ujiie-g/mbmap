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
