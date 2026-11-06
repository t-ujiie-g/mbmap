///|
/// A straight (not premultiplied) RGBA color with components in [0, 1].
#derive(Debug, Eq)
pub(all) struct Color {
  r : Double
  g : Double
  b : Double
  a : Double
}

///|
fn hex_digit(c : UInt16) -> Int32 {
  match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'a'..<='f' => c.to_int() - 'a'.to_int() + 10
    'A'..<='F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// A CSS color as MapLibre's `parseCssColor` reads it: names, hex, `rgb()` and
/// `hsl()` (with or without `a`), with commas or spaces and `/ alpha`; values
/// out of range are clamped, and channels are not rounded to 0..255 integers.
pub fn parse_color(s : String) -> Color? {
  let s = css_lower(s)
  if s.has_prefix("#") {
    parse_hex(s)
  } else if s.has_prefix("rgb") {
    parse_css_function(s, false)
  } else if s.has_prefix("hsl") {
    parse_css_function(s, true)
  } else if s == "transparent" {
    Some({ r: 0.0, g: 0.0, b: 0.0, a: 0.0, })
  } else {
    named_color(s)
  }
}

///|
/// `toLowerCase().trim()` as JavaScript does for the text a color can match:
/// ASCII and white space; the Kelvin sign lowers to `k`, and any other
/// character, which can match nothing, becomes U+FFFD.
fn css_lower(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && js_space(s[a].to_int()) {
    a += 1
  }
  while b > a && js_space(s[b - 1].to_int()) {
    b -= 1
  }
  let out = StringBuilder()
  for i in a..<b {
    let c = s[i].to_int()
    let c = match c {
      'A'..<='Z' => c + 32
      0x212a => 'k'
      0..<0x80 => c
      _ => if js_space(c) { c } else { 0xfffd }
    }
    out.write_char(c.unsafe_to_char())
  }
  out.to_string()
}

///|
/// A name, a space and six hex digits per line: CSS Color 4's named colors.
let named_colors : String =
  #|aliceblue f0f8ff
  #|antiquewhite faebd7
  #|aqua 00ffff
  #|aquamarine 7fffd4
  #|azure f0ffff
  #|beige f5f5dc
  #|bisque ffe4c4
  #|black 000000
  #|blanchedalmond ffebcd
  #|blue 0000ff
  #|blueviolet 8a2be2
  #|brown a52a2a
  #|burlywood deb887
  #|cadetblue 5f9ea0
  #|chartreuse 7fff00
  #|chocolate d2691e
  #|coral ff7f50
  #|cornflowerblue 6495ed
  #|cornsilk fff8dc
  #|crimson dc143c
  #|cyan 00ffff
  #|darkblue 00008b
  #|darkcyan 008b8b
  #|darkgoldenrod b8860b
  #|darkgray a9a9a9
  #|darkgreen 006400
  #|darkgrey a9a9a9
  #|darkkhaki bdb76b
  #|darkmagenta 8b008b
  #|darkolivegreen 556b2f
  #|darkorange ff8c00
  #|darkorchid 9932cc
  #|darkred 8b0000
  #|darksalmon e9967a
  #|darkseagreen 8fbc8f
  #|darkslateblue 483d8b
  #|darkslategray 2f4f4f
  #|darkslategrey 2f4f4f
  #|darkturquoise 00ced1
  #|darkviolet 9400d3
  #|deeppink ff1493
  #|deepskyblue 00bfff
  #|dimgray 696969
  #|dimgrey 696969
  #|dodgerblue 1e90ff
  #|firebrick b22222
  #|floralwhite fffaf0
  #|forestgreen 228b22
  #|fuchsia ff00ff
  #|gainsboro dcdcdc
  #|ghostwhite f8f8ff
  #|gold ffd700
  #|goldenrod daa520
  #|gray 808080
  #|green 008000
  #|greenyellow adff2f
  #|grey 808080
  #|honeydew f0fff0
  #|hotpink ff69b4
  #|indianred cd5c5c
  #|indigo 4b0082
  #|ivory fffff0
  #|khaki f0e68c
  #|lavender e6e6fa
  #|lavenderblush fff0f5
  #|lawngreen 7cfc00
  #|lemonchiffon fffacd
  #|lightblue add8e6
  #|lightcoral f08080
  #|lightcyan e0ffff
  #|lightgoldenrodyellow fafad2
  #|lightgray d3d3d3
  #|lightgreen 90ee90
  #|lightgrey d3d3d3
  #|lightpink ffb6c1
  #|lightsalmon ffa07a
  #|lightseagreen 20b2aa
  #|lightskyblue 87cefa
  #|lightslategray 778899
  #|lightslategrey 778899
  #|lightsteelblue b0c4de
  #|lightyellow ffffe0
  #|lime 00ff00
  #|limegreen 32cd32
  #|linen faf0e6
  #|magenta ff00ff
  #|maroon 800000
  #|mediumaquamarine 66cdaa
  #|mediumblue 0000cd
  #|mediumorchid ba55d3
  #|mediumpurple 9370db
  #|mediumseagreen 3cb371
  #|mediumslateblue 7b68ee
  #|mediumspringgreen 00fa9a
  #|mediumturquoise 48d1cc
  #|mediumvioletred c71585
  #|midnightblue 191970
  #|mintcream f5fffa
  #|mistyrose ffe4e1
  #|moccasin ffe4b5
  #|navajowhite ffdead
  #|navy 000080
  #|oldlace fdf5e6
  #|olive 808000
  #|olivedrab 6b8e23
  #|orange ffa500
  #|orangered ff4500
  #|orchid da70d6
  #|palegoldenrod eee8aa
  #|palegreen 98fb98
  #|paleturquoise afeeee
  #|palevioletred db7093
  #|papayawhip ffefd5
  #|peachpuff ffdab9
  #|peru cd853f
  #|pink ffc0cb
  #|plum dda0dd
  #|powderblue b0e0e6
  #|purple 800080
  #|rebeccapurple 663399
  #|red ff0000
  #|rosybrown bc8f8f
  #|royalblue 4169e1
  #|saddlebrown 8b4513
  #|salmon fa8072
  #|sandybrown f4a460
  #|seagreen 2e8b57
  #|seashell fff5ee
  #|sienna a0522d
  #|silver c0c0c0
  #|skyblue 87ceeb
  #|slateblue 6a5acd
  #|slategray 708090
  #|slategrey 708090
  #|snow fffafa
  #|springgreen 00ff7f
  #|steelblue 4682b4
  #|tan d2b48c
  #|teal 008080
  #|thistle d8bfd8
  #|tomato ff6347
  #|turquoise 40e0d0
  #|violet ee82ee
  #|wheat f5deb3
  #|white ffffff
  #|whitesmoke f5f5f5
  #|yellow ffff00
  #|yellowgreen 9acd32

///|
fn named_color(s : String) -> Color? {
  let mut line = 0
  while line < named_colors.length() {
    let mut end = line
    while end < named_colors.length() && named_colors[end] != '\n' {
      end += 1
    }
    let name_end = end - 7
    if named_colors[line:name_end] == s {
      let channel = (i : Int32) => {
        let at = name_end + 1 + i * 2
        (hex_digit(named_colors[at]) * 16 + hex_digit(named_colors[at + 1])).to_double() /
        255.0
      }
      return Some({ r: channel(0), g: channel(1), b: channel(2), a: 1.0, })
    }
    line = end + 1
  }
  None
}

///|
fn parse_hex(s : String) -> Color? {
  let digits = []
  for i in 1..<s.length() {
    let d = hex_digit(s[i])
    if d < 0 {
      return None
    }
    digits.push(d)
  }
  let channel = (i : Int32, long : Bool) => {
    if long {
      (digits[i * 2] * 16 + digits[i * 2 + 1]).to_double() / 255.0
    } else {
      (digits[i] * 17).to_double() / 255.0
    }
  }
  match digits.length() {
    3 | 4 as n => {
      let a = if n == 4 { channel(3, false) } else { 1.0 }
      Some({
        r: channel(0, false),
        g: channel(1, false),
        b: channel(2, false),
        a,
      })
    }
    6 | 8 as n => {
      let a = if n == 8 { channel(3, true) } else { 1.0 }
      Some({ r: channel(0, true), g: channel(1, true), b: channel(2, true), a, })
    }
    _ => None
  }
}

///|
/// `rgb()`/`rgba()` or (`hsl`) `hsl()`/`hsla()` as MapLibre's regular expressions
/// match them: three values split by spaces (then `/ alpha`) or commas (then
/// `, alpha`); numbers are runs of `[0-9e.+-]`, and a NaN rejects the color.
fn parse_css_function(s : String, hsl : Bool) -> Color? {
  let at = (i : Int32) => if i < s.length() { s[i].to_int() } else { -1 }
  let mut i = 3
  if at(i) == 'a' {
    i += 1
  }
  if at(i) != '(' {
    return None
  }
  i += 1
  let spaces = () => {
    let from = i
    while at(i) >= 0 && js_space(at(i)) {
      i += 1
    }
    i - from
  }
  let number = () => {
    let from = i
    while at(i) is ('0'..<='9' | 'e' | '.' | '+' | '-') {
      i += 1
    }
    css_number(s, from, i)
  }
  let percent = () => {
    if at(i) == '%' {
      i += 1
      true
    } else {
      false
    }
  }
  let separator = () => {
    let n = spaces()
    if at(i) == ',' {
      i += 1
      spaces() |> ignore
      ','
    } else if n > 0 {
      ' '
    } else {
      '?'
    }
  }
  let values = FixedArray::make(3, 0.0)
  let percents = FixedArray::make(3, false)
  let mut commas = 0
  spaces() |> ignore
  for k in 0..<3 {
    if k > 0 {
      match separator() {
        ',' => commas += 1
        ' ' => ()
        _ => return None
      }
    }
    values[k] = number()
    if hsl && k == 0 {
      if s[i:].has_prefix("deg") {
        i += 3
      }
    } else {
      percents[k] = percent()
      if hsl && !percents[k] {
        return None
      }
    }
  }
  spaces() |> ignore
  let mut alpha = 1.0
  if at(i) == ',' || at(i) == '/' {
    let slash = at(i) == '/'
    i += 1
    spaces() |> ignore
    let a = number()
    let a = if percent() { a / 100.0 } else { a }
    alpha = css_clamp(a, 1.0)
    spaces() |> ignore
    if (commas == 2) == slash {
      return None
    }
  }
  if at(i) != ')' || i + 1 != s.length() || commas == 1 {
    return None
  }
  let color = if hsl {
    hsl_to_rgb(
      values[0],
      css_clamp(values[1], 100.0),
      css_clamp(values[2], 100.0),
      alpha,
    )
  } else {
    let max = match (percents[0], percents[1], percents[2]) {
      (true, true, true) => 100.0
      (false, false, false) => 255.0
      _ => return None
    }
    {
      r: css_clamp(values[0] / max, 1.0),
      g: css_clamp(values[1] / max, 1.0),
      b: css_clamp(values[2] / max, 1.0),
      a: alpha,
    }
  }
  if values.iter().any(x => x.is_nan()) || alpha.is_nan() {
    None
  } else {
    Some(color)
  }
}

///|
/// `Math.min(Math.max(0, x), max)`: NaN stays NaN and -0 becomes 0.
fn css_clamp(x : Double, max : Double) -> Double {
  if x.is_nan() {
    x
  } else if x <= 0.0 {
    0.0
  } else if x >= max {
    max
  } else {
    x
  }
}

///|
/// MapLibre's `hslToRgb` (style-spec `color_spaces.ts`), saturation and
/// lightness in percent.
fn hsl_to_rgb(h : Double, s : Double, l : Double, a : Double) -> Color {
  let mut h = h % 360.0
  if h < 0.0 {
    h += 360.0
  }
  let s = s / 100.0
  let l = l / 100.0
  let f = (n : Double) => {
    let k = (n + h / 30.0) % 12.0
    let a = s * js_min(l, 1.0 - l)
    l - a * js_max(-1.0, js_min(js_min(k - 3.0, 9.0 - k), 1.0))
  }
  { r: f(0.0), g: f(8.0), b: f(4.0), a, }
}

///|
/// `Math.min` of two numbers, NaN if either is.
fn js_min(a : Double, b : Double) -> Double {
  if a < b || a.is_nan() {
    a
  } else {
    b
  }
}

///|
/// `Math.max` of two numbers, NaN if either is.
fn js_max(a : Double, b : Double) -> Double {
  if a > b || a.is_nan() {
    a
  } else {
    b
  }
}

///|
/// JavaScript's `Number` of the run `s[from:to]` (NaN if empty or not decimal):
/// exact within Clinger's fast path (15 digits, powers of ten to ±22); past it
/// the last bits may differ, as `strconv` is too big for the bundles.
fn css_number(s : String, from : Int32, to : Int32) -> Double {
  let at = (i : Int32) => if i < to { s[i].to_int() } else { -1 }
  let mut i = from
  let negative = at(i) == '-'
  if at(i) is ('-' | '+') {
    i += 1
  }
  let mut mantissa = 0L
  let mut digits = 0
  let mut exponent = 0
  let mut any = false
  let mut point = false
  while at(i) is ('0'..<='9' | '.') {
    if at(i) == '.' {
      if point {
        break
      }
      point = true
    } else {
      any = true
      if digits < 18 {
        mantissa = mantissa * 10L + (at(i) - '0').to_int64()
        if mantissa > 0L {
          digits += 1
        }
        if point {
          exponent -= 1
        }
      } else {
        digits += 1
        if !point {
          exponent += 1
        }
      }
    }
    i += 1
  }
  if at(i) == 'e' {
    i += 1
    let sign = if at(i) == '-' { -1 } else { 1 }
    if at(i) is ('-' | '+') {
      i += 1
    }
    let mut e = 0
    let from = i
    while at(i) is ('0'..<='9') {
      e = @cmp.minimum(e * 10 + (at(i) - '0'), 100000)
      i += 1
    }
    if i == from {
      any = false
    }
    exponent += sign * e
  }
  if !any || i != to {
    return @double.not_a_number
  }
  let mut v = mantissa.to_double()
  while exponent > 22 && v != 0.0 && v < @double.infinity {
    v *= 1.0e22
    exponent -= 22
  }
  while exponent < -22 && v != 0.0 {
    v /= 1.0e22
    exponent += 22
  }
  if v != 0.0 && v < @double.infinity {
    v = if exponent < 0 { v / pow10(-exponent) } else { v * pow10(exponent) }
  }
  if negative {
    -v
  } else {
    v
  }
}

///|
/// 10^k, exact for 0 <= k <= 22.
fn pow10(k : Int32) -> Double {
  let mut p = 1.0
  for _ in 0..<k {
    p *= 10.0
  }
  p
}
