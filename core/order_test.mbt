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
