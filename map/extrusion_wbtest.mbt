///|
test "light_direction converts MapLibre's default light and turns with the bearing" {
  let close = (a : (Double, Double, Double), b : (Double, Double, Double)) => {
    (a.0 - b.0).abs() < 1.0e-12 &&
    (a.1 - b.1).abs() < 1.0e-12 &&
    (a.2 - b.2).abs() < 1.0e-12
  }
  // [1.15, 210, 30]: azimuth 300° from +x, 30° from straight up.
  let half = 1.15 * 0.5
  let x = half * 0.5
  let y = -half * 3.0.sqrt() / 2.0
  let z = 1.15 * 3.0.sqrt() / 2.0
  assert_true(
    close(light_direction((1.15, 210.0, 30.0), false, 40.0), (x, y, z)),
  )
  assert_true(close(light_direction((1.15, 210.0, 30.0), true, 0.0), (x, y, z)))
  // Anchored to the viewport, a 90° bearing turns it a quarter around z.
  assert_true(
    close(light_direction((1.15, 210.0, 30.0), true, 90.0), (-y, x, z)),
  )
}
