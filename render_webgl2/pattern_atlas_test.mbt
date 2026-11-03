///|
/// A `w` x `h` image whose pixel (x, y) is (x, y, 7, 255).
fn ramp_image(
  w : Int32,
  h : Int32,
  ratio~ : Double = 1.0,
) -> @render_webgl2.StyleImage {
  let data = FixedArray::make(w * h * 4, b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let at = (y * w + x) * 4
      data[at] = x.to_byte()
      data[at + 1] = y.to_byte()
      data[at + 2] = b'\x07'
      data[at + 3] = b'\xff'
    }
  }
  { width: w, height: h, data, pixel_ratio: ratio, sdf: false, }
}

///|
fn atlas_pixel(
  a : @render_webgl2.PatternAtlas,
  x : Int32,
  y : Int32,
) -> (Int32, Int32) {
  let at = (y * @render_webgl2.PATTERN_ATLAS_WIDTH + x) * 4
  (a.data[at].to_int(), a.data[at + 1].to_int())
}

///|
test "patterns are packed with their edges wrapped into the padding" {
  let a = @render_webgl2.PatternAtlas::new()
  let p = a.add("ramp", ramp_image(4, 3)).unwrap()
  assert_eq((p.tl, p.br), ((1, 1), (5, 4)))
  assert_eq(p.display_size(), (4.0, 3.0))
  assert_true(a.take_dirty())
  assert_false(a.take_dirty())
  // Inside, then the padding above (the last row), below (the first), left
  // (the last column) and right (the first).
  assert_eq(atlas_pixel(a, 2, 1), (1, 0))
  assert_eq(atlas_pixel(a, 2, 0), (1, 2))
  assert_eq(atlas_pixel(a, 2, 4), (1, 0))
  assert_eq(atlas_pixel(a, 0, 2), (3, 1))
  assert_eq(atlas_pixel(a, 5, 2), (0, 1))
  // The next one goes on the same shelf; a 2x image shows at half its size.
  let q = a.add("double", ramp_image(2, 2, ratio=2.0)).unwrap()
  assert_eq((q.tl, q.display_size()), ((7, 1), (1.0, 1.0)))
  assert_eq(a.get("ramp").map(p => p.tl), Some((1, 1)))
}

///|
test "the atlas grows downward and refuses what cannot fit" {
  let a = @render_webgl2.PatternAtlas::new()
  let tall = a.add("tall", ramp_image(8, 100)).unwrap()
  assert_eq(tall.tl, (1, 1))
  assert_true(a.height >= 102)
  // Kept across growth.
  assert_eq(atlas_pixel(a, 1, 1), (0, 0))
  assert_true(
    a.add("wide", ramp_image(@render_webgl2.PATTERN_ATLAS_WIDTH, 1)) is None,
  )
  assert_true(
    a.add("bad", { ..ramp_image(2, 2), data: FixedArray::make(4, b'\x00'), })
    is None,
  )
  a.clear()
  assert_true(a.get("tall") is None)
}
