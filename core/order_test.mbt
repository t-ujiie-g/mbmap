///|
test "stable_order sorts indices by key, keeping ties in order" {
  assert_eq(@core.stable_order([3.0, 1.0, 2.0, 1.0, 0.0][:]), [4, 1, 3, 2, 0])
  assert_eq(@core.stable_order([][:]), [])
  assert_eq(@core.stable_order([5.0][:]), [0])
  let keys = Array::makei(37, i => (i * 7 % 5).to_double())
  let order = @core.stable_order(keys[:])
  for k in 1..<37 {
    let (a, b) = (order[k - 1], order[k])
    assert_true(keys[a] < keys[b] || (keys[a] == keys[b] && a < b))
  }
}

///|
test "stable_sort keeps ties in order, short and long arrays alike" {
  for n in [0, 1, 5, 32, 33, 100] {
    let a = Array::makei(n, i => (i * 7 % 5, i))
    @core.stable_sort(a, (x, y) => x.0 < y.0)
    for k in 1..<n {
      assert_true(
        a[k - 1].0 < a[k].0 || (a[k - 1].0 == a[k].0 && a[k - 1].1 < a[k].1),
      )
    }
    assert_eq(a.length(), n)
  }
}
