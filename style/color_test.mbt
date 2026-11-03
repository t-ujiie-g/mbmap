///|
fn rgba(s : String) -> (Double, Double, Double, Double)? {
  @style.parse_color(s).map(c => (c.r, c.g, c.b, c.a))
}

///|
fn none(inputs : Array[String]) -> Unit raise {
  for s in inputs {
    assert_eq(rgba(s), None, msg=s)
  }
}

///|
test "parse_color reads named colors and transparent" {
  assert_eq(rgba("aliceblue"), Some((240.0 / 255.0, 248.0 / 255.0, 1.0, 1.0)))
  assert_eq(
    rgba(" RebeccaPurple\n"),
    Some((102.0 / 255.0, 51.0 / 255.0, 153.0 / 255.0, 1.0)),
  )
  assert_eq(
    rgba("yellowgreen"),
    Some((154.0 / 255.0, 205.0 / 255.0, 50.0 / 255.0, 1.0)),
  )
  assert_eq(rgba("blac\u{212a}"), Some((0.0, 0.0, 0.0, 1.0)))
  assert_eq(rgba("transparent"), Some((0.0, 0.0, 0.0, 0.0)))
  none(["none", "redx", "ed", "red blue", "", "constructor", "re\u{fffd}d"])
}

///|
test "parse_color reads every hex form" {
  assert_eq(rgba("#fff"), Some((1.0, 1.0, 1.0, 1.0)))
  assert_eq(rgba("#f0c8"), Some((1.0, 0.0, 0.8, 136.0 / 255.0)))
  assert_eq(rgba("#FF000080"), Some((1.0, 0.0, 0.0, 128.0 / 255.0)))
  assert_eq(rgba("#336699"), Some((0.2, 0.4, 0.6, 1.0)))
  none([
    "#", "#12", "#12345", "#1234567", "#123456789", "#ggg", "##fff", "#ab c",
  ])
}

///|
test "parse_color reads rgb() with commas, spaces and slash alpha" {
  assert_eq(rgba(" rgba(0, 51, 255, 0.5) "), Some((0.0, 0.2, 1.0, 0.5)))
  assert_eq(rgba("rgb(255,255,255)"), Some((1.0, 1.0, 1.0, 1.0)))
  assert_eq(
    rgba("rgba(1,2,3)"),
    Some((1.0 / 255.0, 2.0 / 255.0, 3.0 / 255.0, 1.0)),
  )
  assert_eq(
    rgba("RGB(1 2 3 / 50%)"),
    Some((1.0 / 255.0, 2.0 / 255.0, 3.0 / 255.0, 0.5)),
  )
  assert_eq(rgba("rgb(50% 0% 100% /.6)"), Some((0.5, 0.0, 1.0, 0.6)))
  assert_eq(
    rgba("\u{3000}rgb(\t1\n2\u{a0}3)\u{feff}"),
    Some((1.0 / 255.0, 2.0 / 255.0, 3.0 / 255.0, 1.0)),
  )
}

///|
test "parse_color clamps out-of-range channels and alpha" {
  assert_eq(rgba("rgb(300, -5, 50)"), Some((1.0, 0.0, 50.0 / 255.0, 1.0)))
  assert_eq(rgba("rgb(150% -0% 0%)"), Some((1.0, 0.0, 0.0, 1.0)))
  assert_eq(rgba("rgba(1,2,3,2)").map(c => c.3), Some(1.0))
  assert_eq(rgba("rgb(1 2 3 / -5%)").map(c => c.3), Some(0.0))
  assert_eq(rgba("rgb(1e400, -1e400, 1e-400)"), Some((1.0, 0.0, 0.0, 1.0)))
}

///|
test "parse_color reads numbers as JavaScript's Number does" {
  assert_eq(
    rgba("rgb(1e2, +5, .5)"),
    Some((100.0 / 255.0, 5.0 / 255.0, 0.5 / 255.0, 1.0)),
  )
  assert_eq(
    rgba("rgb(5., 12.5, 0e999)"),
    Some((5.0 / 255.0, 12.5 / 255.0, 0.0, 1.0)),
  )
  assert_eq(rgba("rgba(0, 0, 0, 1e-2)").map(c => c.3), Some(0.01))
  assert_eq(
    rgba("rgba(0, 0, 0, 0.30000000000000004)").map(c => c.3),
    Some(0.30000000000000004),
  )
  assert_eq(rgba("rgb(99999999999999999999, 0, 0)").map(c => c.0), Some(1.0))
  none([
    "rgb(1.2.3,0,0)", "rgb(1e,0,0)", "rgb(e1,0,0)", "rgb(.,0,0)", "rgb(+-1,0,0)",
    "rgb(1-2,0,0)", "rgb(1e2e3,0,0)", "rgb(,0,0)",
  ])
}

///|
test "parse_color rejects mixed separators, mixed units and stray text" {
  none([
    "rgb(1, 2 3)", "rgb(1 2, 3)", "rgb(1, 2, 3 / 0.5)", "rgb(1 2 3, 0.5)", "rgb(1,2,3,)",
    "rgb(1 2 3 /)", "rgb(1,2)", "rgb(1,2,3,4,5)", "rgb (1,2,3)", "rgb(1,2,3", "rgb(1,2,3))",
    "rgb(1,2,3) x", "rgbx(1,2,3)", "rgbaa(1,2,3)", "rgb()", "rgb(300, -5, 50%)",
    "rgb(1%%,2,3)", "rgb(1deg, 2, 3)",
  ])
}

///|
test "parse_color reads hsl() as MapLibre's hslToRgb" {
  assert_eq(rgba("hsl(120deg 50% 50%)"), Some((0.25, 0.75, 0.25, 1.0)))
  assert_eq(rgba("hsla(30, 19%, 90%, 0.4)"), Some((0.919, 0.9, 0.881, 0.4)))
  assert_eq(
    rgba("hsl(210 13.5% 77.25% / 50%)"),
    Some((0.7417874999999999, 0.7725, 0.8032125, 0.5)),
  )
  assert_eq(rgba("hsl(-120, 100%, 50%)"), Some((0.0, 0.0, 1.0, 1.0)))
  assert_eq(rgba("hsl(480deg, 100%, 50%)"), Some((0.0, 1.0, 0.0, 1.0)))
  assert_eq(rgba("hsl(120, 150%, -50%)"), Some((0.0, 0.0, 0.0, 1.0)))
  assert_true(
    rgba("hsl(1e400, 50%, 50%)") is Some((r, _, _, 1.0)) && r.is_nan(),
  )
  none([
    "hsl(120, 50, 50)", "hsl(120%, 50%, 50%)", "hsl(120 deg, 50%, 50%)", "hsl(120rad, 50%, 50%)",
    "hsl(1, 2%, 3% / 0.5)", "hsl(1 2% 3%, 0.5)", "hsl(1,2%,3%,4%x)", "hsl()", "hsl(1 2% 3%",
    "hsla (1, 2%, 3%)", "hsl(x, 2%, 3%)",
  ])
}
