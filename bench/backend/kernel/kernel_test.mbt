///|
test "decode_deltas accumulates zigzag varint pairs" {
  // (dx, dy) = (1, -1), (300, 2) -> zigzag 2, 1, 600, 4
  let src : FixedArray[Byte] = [0x02, 0x01, 0xd8, 0x04, 0x04]
  let out = FixedArray::make(4, (0.0 : Float))
  let n = @kernel.decode_deltas(src, src.length(), out)
  assert_eq(n, 4)
  assert_eq(out, ([1, -1, 301, 1] : FixedArray[Float]))
}

///|
test "alloc_churn checksum" {
  // f=0: p=(1,1) -> 0+2 ; f=1: p=(0,2) -> -2+2
  assert_eq(@kernel.alloc_churn(2, 2), 2)
}
