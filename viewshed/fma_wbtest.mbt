///|
test "fma rounds a * b + c once as C's fma does" {
  let cases : Array[(Double, Double, Double, Double)] = [
    (0x1.999999999999ap-4, 0x1.4p+3, -0x1.0p+0, 0x1.0p-54),
    (0x1.0000000000001p+0, 0x1.0000000000001p+0, -0x1.0p+0, 0x1.0p-51),
    (0x1.0000002p+0, 0x1.ffffffcp-1, -0x1.0p+0, -0x1.0p-54),
    (0x1.00000004p+0, 0x1.00000004p+0, 0x1.0p-80, 0x1.00000008p+0),
    (0x1.8p+1, 0x1.5555555555555p-2, -0x1.0p+0, -0x1.0p-54),
    (0x1.0000000000001p+0, 0x1.fffffffffffffp-1, 0x1.0p-106, 0x1.0p+0),
    (
      0x1.b5e3d70a3d70ap+9, 0x1.8p+1, 0x1.1486e39b78283p+10, 0x1.d2ae53156a289p+11,
    ),
    (
      -0x1.38773c05fdee7p+12, -0x1.14403de88ee6ep-9, -0x1.512ef615be5ebp+3, -0x1.a930703d3c6dcp-36,
    ),
    (
      -0x1.55601871dac03p+7, 0x1.4e54e9fd7df17p-9, 0x1.bdd4a0d7306cdp-2, 0x1.590860283c5fbp-24,
    ),
    (
      0x1.3cc1e675b183dp+8, -0x1.41f7ae1483ef6p+0, 0x1.8e61cc28f1f8p+8, 0x1.9da6ae504b5e1p-11,
    ),
    (
      0x1.d6cef755ad9e1p+0, 0x1.b08a1a5f61144p-2, -0x1.8dbd9eb9255edp-1, 0x1.9c5b071452fap-39,
    ),
    (
      0x1.a72b115ac6562p+8, 0x1.1f822b212f046p+7, -0x1.db4074e72ac71p+15, -0x1.4880242ad3a13p-9,
    ),
  ]
  for c in cases {
    let (a, b, z, want) = c
    assert_eq(fma(a, b, z), want)
  }
}

///|
test "fma passes zeros, infinities and NaN through as a * b + c" {
  assert_eq(fma(0.0, 5.0, 3.0), 3.0)
  assert_eq(fma(2.0, 3.0, 0.0), 6.0)
  assert_eq(fma(@double.infinity, 2.0, 1.0), @double.infinity)
  assert_true(fma(1.0, 2.0, @double.not_a_number).is_nan())
}
