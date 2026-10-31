///|
fn near4(
  a : (Double, Double, Double, Double),
  b : (Double, Double, Double, Double),
) -> Bool {
  (a.0 - b.0).abs() < 1.0e-9 &&
  (a.1 - b.1).abs() < 1.0e-9 &&
  (a.2 - b.2).abs() < 1.0e-9 &&
  (a.3 - b.3).abs() < 1.0e-9
}

///|
test "translate, scale and rotations apply on the right" {
  let m = @core.Mat4::identity().translate(10.0, 0.0, 0.0).scale(2.0, 3.0, 1.0)
  // Scaled first, then translated.
  assert_true(near4(m.apply(1.0, 1.0, 0.0, 1.0), (12.0, 3.0, 0.0, 1.0)))
  let quarter = @math.PI / 2.0
  assert_true(
    near4(
      @core.Mat4::identity().rotate_z(quarter).apply(1.0, 0.0, 0.0, 1.0),
      (0.0, 1.0, 0.0, 1.0),
    ),
  )
  assert_true(
    near4(
      @core.Mat4::identity().rotate_x(quarter).apply(0.0, 1.0, 0.0, 1.0),
      (0.0, 0.0, 1.0, 1.0),
    ),
  )
}

///|
test "perspective maps the near and far planes to clip z -1 and 1" {
  let p = @core.Mat4::perspective(@math.PI / 2.0, 2.0, 1.0, 10.0)
  let (x, _, z, w) = p.apply(1.0, 0.0, -1.0, 1.0)
  assert_true((z / w + 1.0).abs() < 1.0e-9 && (x / w - 0.5).abs() < 1.0e-9)
  let (_, _, z, w) = p.apply(0.0, 0.0, -10.0, 1.0)
  assert_true((z / w - 1.0).abs() < 1.0e-9)
}

///|
test "invert undoes the matrix; singular matrices have no inverse" {
  let m = @core.Mat4::perspective(0.8, 1.5, 2.0, 500.0)
    .translate(3.0, -4.0, -50.0)
    .rotate_x(0.7)
    .rotate_z(-1.2)
    .scale(2.0, 2.0, 1.0)
  let i = m.invert().unwrap()
  let (x, y, z, w) = m.apply(5.0, 6.0, 0.0, 1.0)
  let (a, b, c, d) = i.apply(x, y, z, w)
  assert_true(near4((a / d, b / d, c / d, 1.0), (5.0, 6.0, 0.0, 1.0)))
  assert_eq(@core.Mat4::identity().scale(1.0, 0.0, 1.0).invert(), None)
}
