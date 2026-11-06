// Color interpolation in CIE Lab and HCL as MapLibre GL JS's style-spec 26.5.0
// computes it (src/expression/types/color_spaces.ts and color.ts), BSD-3-Clause,
// Copyright (c) 2020 MapLibre contributors. See NOTICE.

///|
const T0 : Double = 4.0 / 29.0

///|
const T1 : Double = 6.0 / 29.0

///|
fn t2() -> Double {
  3.0 * T1 * T1
}

///|
/// `[l, a, b, alpha]` of a color.
fn lab(trig : @core.Trig, c : Color) -> FixedArray[Double] {
  let xyz = (v : Double) => {
    if v <= 0.04045 {
      v / 12.92
    } else {
      trig.pow((v + 0.055) / 1.055, 2.4)
    }
  }
  let lab_f = (t : Double) => {
    if t > T1 * T1 * T1 {
      trig.pow(t, 1.0 / 3.0)
    } else {
      t / t2() + T0
    }
  }
  let (r, g, b) = (xyz(c.r), xyz(c.g), xyz(c.b))
  let y = lab_f(0.2225045 * r + 0.7168786 * g + 0.0606169 * b)
  let (x, z) = if r == g && g == b {
    (y, y)
  } else {
    (
      lab_f((0.4360747 * r + 0.3850649 * g + 0.1430804 * b) / 0.96422),
      lab_f((0.0139322 * r + 0.0971045 * g + 0.7141733 * b) / 0.82521),
    )
  }
  let l = 116.0 * y - 16.0
  [if l < 0.0 { 0.0 } else { l }, 500.0 * (x - y), 200.0 * (y - z), c.a]
}

///|
fn from_lab(
  trig : @core.Trig,
  l : Double,
  a : Double,
  b : Double,
  alpha : Double,
) -> Color {
  let xyz = (t : Double) => if t > T1 { t * t * t } else { t2() * (t - T0) }
  let rgb = (v : Double) => {
    let v = if v <= 0.00304 {
      12.92 * v
    } else {
      1.055 * trig.pow(v, 1.0 / 2.4) - 0.055
    }
    if v < 0.0 {
      0.0
    } else if v > 1.0 {
      1.0
    } else {
      v
    }
  }
  let y0 = (l + 16.0) / 116.0
  let x = 0.96422 * xyz(if a != a { y0 } else { y0 + a / 500.0 })
  let z = 0.82521 * xyz(if b != b { y0 } else { y0 - b / 200.0 })
  let y = xyz(y0)
  {
    r: rgb(3.1338561 * x - 1.6168667 * y - 0.4906146 * z),
    g: rgb(-0.9787684 * x + 1.9161415 * y + 0.033454 * z),
    b: rgb(0.0719453 * x - 0.2289914 * y + 1.4052427 * z),
    a: alpha,
  }
}

///|
/// `[h, c, l, alpha]` of a color; the hue is NaN for a gray.
fn hcl(trig : @core.Trig, c : Color) -> FixedArray[Double] {
  let v = lab(trig, c)
  let chroma = (v[1] * v[1] + v[2] * v[2]).sqrt()
  let h = if js_round(chroma * 10000.0) != 0.0 {
    let h = trig.atan2(v[2], v[1]) * (180.0 / pi) % 360.0
    if h < 0.0 {
      h + 360.0
    } else {
      h
    }
  } else {
    @double.not_a_number
  }
  [h, chroma, v[0], v[3]]
}

///|
/// MapLibre's `Color.interpolate` in Lab or HCL.
fn blend_space(
  trig : @core.Trig,
  space : ColorSpace,
  from : Color,
  to : Color,
  t : Double,
) -> Color {
  let mix = (a : Double, b : Double) => a + t * (b - a)
  if space is Lab {
    let a = lab(trig, from)
    let b = lab(trig, to)
    return from_lab(
      trig,
      mix(a[0], b[0]),
      mix(a[1], b[1]),
      mix(a[2], b[2]),
      mix(a[3], b[3]),
    )
  }
  let a = hcl(trig, from)
  let b = hcl(trig, to)
  let mut chroma = mix(a[1], b[1])
  let hue = if a[0] == a[0] && b[0] == b[0] {
    let mut dh = b[0] - a[0]
    if b[0] > a[0] && dh > 180.0 {
      dh -= 360.0
    } else if b[0] < a[0] && a[0] - b[0] > 180.0 {
      dh += 360.0
    }
    a[0] + t * dh
  } else if a[0] == a[0] {
    if b[2] == 1.0 || b[2] == 0.0 {
      chroma = a[1]
    }
    a[0]
  } else if b[0] == b[0] {
    if a[2] == 1.0 || a[2] == 0.0 {
      chroma = b[1]
    }
    b[0]
  } else {
    0.0
  }
  let h = hue * (pi / 180.0)
  from_lab(
    trig,
    mix(a[2], b[2]),
    trig.cos(h) * chroma,
    trig.sin(h) * chroma,
    mix(a[3], b[3]),
  )
}
