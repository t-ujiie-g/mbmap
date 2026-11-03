///|
test "color_ramp maps each row's pixels onto its slice of the line" {
  let gray = (p : Double) => (p, p, p, 1.0)
  let one = @render_webgl2.color_ramp([], 256, gray)
  assert_eq(one.length(), 256 * 4)
  assert_eq(
    (one[0], one[3], one[255 * 4], one[128 * 4]),
    (b'\x00', b'\xff', b'\xff', b'\x80'),
  )
  // The second half of a line: pixel 0 at progress 0.5.
  let half = @render_webgl2.color_ramp([0.0, 0.5, 0.5, 1.0], 256, gray)
  assert_eq(half.length(), 2 * 256 * 4)
  assert_eq(
    (half[255 * 4], half[256 * 4], half[511 * 4]),
    (b'\x80', b'\x80', b'\xff'),
  )
  // Transparent pixels are 0 throughout.
  let clear = @render_webgl2.color_ramp([], 256, _ => (1.0, 0.0, 0.0, 0.0))
  assert_true(clear.iter().all(b => b == b'\x00'))
}

///|
test "ramp_width widens step ramps for long lines, as a power of two" {
  assert_eq(
    @render_webgl2.ramp_width(
      step=false,
      length=10.0,
      overzoom=1.0,
      max_size=4096,
    ),
    256,
  )
  assert_eq(
    @render_webgl2.ramp_width(
      step=true,
      length=0.1,
      overzoom=1.0,
      max_size=4096,
    ),
    256,
  )
  assert_eq(
    @render_webgl2.ramp_width(
      step=true,
      length=1.5,
      overzoom=1.0,
      max_size=4096,
    ),
    2048,
  )
  assert_eq(
    @render_webgl2.ramp_width(
      step=true,
      length=1.5,
      overzoom=16.0,
      max_size=4096,
    ),
    4096,
  )
}
