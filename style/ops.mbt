///|
fn[C : FeatureContext] call(
  op : Op,
  args : Array[Expr],
  zoom : Double,
  ctx : C,
) -> Value {
  let go = (i : Int32) => args[i].eval(zoom, ctx)
  let n = args.length()
  match op {
    Concat => {
      let out = StringBuilder()
      for i in 0..<n {
        let v = go(i)
        if v is Failed {
          return Failed
        }
        out.write_string(value_to_string(ctx, v))
      }
      Str(out.to_string())
    }
    Upcase | Downcase =>
      match go(0) {
        Str(s) => Str(change_case(s, op is Upcase))
        _ => Failed
      }
    TypeOf =>
      match go(0) {
        Failed => Failed
        v => Str(type_of(v))
      }
    Length =>
      match go(0) {
        Str(s) => Num(code_points(s, s.length()).to_double())
        List(xs) => Num(xs.length().to_double())
        _ => Failed
      }
    Slice => {
      let input = go(0)
      guard go(1) is Num(begin) else { return Failed }
      let end = if n > 2 {
        guard go(2) is Num(end) else { return Failed }
        end
      } else {
        @double.infinity
      }
      match input {
        Str(s) => {
          let cps = s.iter().collect()
          let (a, b) = slice_range(begin, end, cps.length())
          Str(String::from_array(cps[a:b]))
        }
        List(xs) => {
          let (a, b) = slice_range(begin, end, xs.length())
          List(xs[a:b].to_owned())
        }
        _ => Failed
      }
    }
    IndexOf => index_of(go(0), go(1), if n > 2 { go(2) } else { Null }, ctx)
    At =>
      match (go(0), go(1)) {
        (Num(i), List(xs)) if i >= 0.0 &&
          i < xs.length().to_double() &&
          i == i.floor() => xs[i.to_int()]
        _ => Failed
      }
    Rgba => {
      let c = FixedArray::make(4, 1.0)
      for i in 0..<n {
        guard go(i) is Num(x) &&
          x >= 0.0 &&
          x <= (if i == 3 { 1.0 } else { 255.0 }) else {
          return Failed
        }
        c[i] = if i == 3 { x } else { x / 255.0 }
      }
      Color({ r: c[0], g: c[1], b: c[2], a: c[3], })
    }
    ToRgba =>
      match go(0) {
        Color(c) =>
          List([Num(c.r * 255.0), Num(c.g * 255.0), Num(c.b * 255.0), Num(c.a)])
        _ => Failed
      }
    Split =>
      match (go(0), go(1)) {
        (Str(s), Str(d)) => List(js_split(s, d))
        _ => Failed
      }
    Join =>
      match (go(0), go(1)) {
        (List(xs), Str(d)) => {
          let out = StringBuilder()
          for i, x in xs {
            guard x is Str(s) else { return Failed }
            if i > 0 {
              out.write_string(d)
            }
            out.write_string(s)
          }
          Str(out.to_string())
        }
        _ => Failed
      }
    Format => {
      let sections = []
      for k = 0; k + 4 < n; k = k + 5 {
        let text = match go(k) {
          Failed => return Failed
          v => value_to_string(ctx, v)
        }
        let (scale, font, color, align) = match
          (go(k + 1), go(k + 2), go(k + 3), go(k + 4)) {
          (Failed, _, _, _)
          | (_, Failed, _, _)
          | (_, _, Failed, _)
          | (_, _, _, Failed) => return Failed
          (s, f, c, a) => (s, f, c, a)
        }
        sections.push({
          text,
          scale: if scale is Num(x) {
            Some(x)
          } else {
            None
          },
          font: match font {
            List(xs) =>
              Some(xs.map(x => if x is Str(s) { s } else { "" }).join(","))
            _ => None
          },
          color: if color is Color(c) {
            Some(c)
          } else {
            None
          },
          align: if align is Str(a) {
            Some(a)
          } else {
            None
          },
        })
      }
      Formatted(sections)
    }
    NumberFormat => {
      guard go(0) is Num(x) else { return Failed }
      let text = (v : Value) => if v is Str(s) { Some(s) } else { None }
      let number = (v : Value) => if v is Num(x) { Some(x) } else { None }
      let (locale, currency, unit) = (go(1), go(2), go(3))
      let (min, max) = (go(4), go(5))
      if [locale, currency, unit, min, max].iter().any(v => v is Failed) {
        return Failed
      }
      match
        ctx.number_format(
          x,
          text(locale),
          text(currency),
          text(unit),
          number(min),
          number(max),
        ) {
        Some(s) => Str(s)
        None => Failed
      }
    }
    Collator =>
      match (go(0), go(1), go(2)) {
        (Bool(case), Bool(diacritic), Str(l)) =>
          Collator(case, diacritic, Some(l))
        (Bool(case), Bool(diacritic), Null) => Collator(case, diacritic, None)
        _ => Failed
      }
    ResolvedLocale =>
      match go(0) {
        Collator(_, _, locale) =>
          match ctx.resolved_locale(locale) {
            Some(s) => Str(s)
            None => Failed
          }
        _ => Failed
      }
    _ => {
      let trig = ctx.trig()
      let mut a = match op {
        Mul => 1.0
        Min => @double.infinity
        Max => @double.neg_infinity
        _ => 0.0
      }
      for i in 0..<n {
        guard go(i) is Num(x) else { return Failed }
        a = match op {
          Add => a + x
          Mul => a * x
          Min =>
            if a != a || x != x {
              @double.not_a_number
            } else if x < a || (x == a && 1.0 / x < 0.0) {
              x
            } else {
              a
            }
          Max =>
            if a != a || x != x {
              @double.not_a_number
            } else if x > a || (x == a && 1.0 / x > 0.0) {
              x
            } else {
              a
            }
          _ if i == 0 => x
          Sub => a - x
          Div => a / x
          Rem => a % x
          _ => trig.pow(a, x)
        }
      }
      Num(
        match op {
          Sub if n == 1 => -a
          Sqrt => a.sqrt()
          Log10 => trig.ln(a) / 2.302585092994046
          Ln => trig.ln(a)
          Log2 => trig.ln(a) / 0.6931471805599453
          Sin => trig.sin(a)
          Cos => trig.cos(a)
          Tan => trig.tan(a)
          Asin => trig.asin(a)
          Acos => trig.acos(a)
          Atan => trig.atan(a)
          Round => if a < 0.0 { -js_round(-a) } else { js_round(a) }
          Abs => a.abs()
          Ceil => a.ceil()
          Floor => a.floor()
          _ => a
        },
      )
    }
  }
}

///|
fn[C : FeatureContext] coerce(
  t : Expected,
  es : Array[Expr],
  zoom : Double,
  ctx : C,
) -> Value {
  for e in es {
    let v = e.eval(zoom, ctx)
    match (t, v) {
      (_, Failed) => return Failed
      (StringType, _) => return Str(value_to_string(ctx, v))
      (BoolType, Null | Bool(false) | Str("")) => return Bool(false)
      (BoolType, Num(x)) => return Bool(x == x && x != 0.0)
      (BoolType, _) => return Bool(true)
      (NumberType, Null) => return Num(0.0)
      (NumberType, _) => {
        let x = match v {
          Num(x) => x
          Bool(b) => if b { 1.0 } else { 0.0 }
          _ => ctx.text_number(js_string(ctx, v))
        }
        if x == x {
          return Num(x)
        }
      }
      (_, Color(_)) => return v
      (_, Str(s)) => if parse_color(s) is Some(c) { return Color(c) }
      (_, List(xs)) => if rgba_list(xs) is Some(c) { return Color(c) }
      _ => ()
    }
  }
  Failed
}

///|
/// `to-color` of `[r, g, b]` or `[r, g, b, a]`. MapLibre takes the channels
/// as premultiplied by `a`, so they are divided by it here.
fn rgba_list(xs : Array[Value]) -> Color? {
  let c = FixedArray::make(4, 1.0)
  guard xs.length() is (3 | 4) else { return None }
  for i, x in xs {
    guard x is Num(x) && x >= 0.0 && x <= (if i == 3 { 1.0 } else { 255.0 }) else {
      return None
    }
    c[i] = x
  }
  let k = if c[3] == 0.0 { 0.0 } else { 1.0 / 255.0 / c[3] }
  Some({ r: c[0] * k, g: c[1] * k, b: c[2] * k, a: c[3], })
}

///|
fn[C : FeatureContext] index_of(
  needle : Value,
  hay : Value,
  from : Value,
  ctx : C,
) -> Value {
  let start = match from {
    Null => 0.0
    Num(x) => x
    _ => return Failed
  }
  match (needle, hay) {
    (Failed | Color(_) | List(_) | Formatted(_) | Collator(_, _, _), _) =>
      Failed
    (_, Str(s)) => {
      let t = js_string(ctx, needle)
      let a = if start != start { 0.0 } else { start.trunc() }
      let a = @cmp.maximum(0.0, @cmp.minimum(a, s.length().to_double())).to_int()
      for i in a..<=(s.length() - t.length()) {
        if s.has_prefix_at(t, i) {
          return Num(code_points(s, i).to_double())
        }
      }
      Num(-1.0)
    }
    (_, List(xs)) => {
      let (a, _) = slice_range(start, 0.0, xs.length())
      for i in a..<xs.length() {
        if same(needle, xs[i]) {
          return Num(i.to_double())
        }
      }
      Num(-1.0)
    }
    _ => Failed
  }
}

///|
/// Whether `t` occurs in `s` at code unit `i`.
fn String::has_prefix_at(s : String, t : String, i : Int32) -> Bool {
  for k in 0..<t.length() {
    if s[i + k] != t[k] {
      return false
    }
  }
  true
}

///|
/// The code points among the first `n` code units of `s` (lone surrogates
/// count one each, as JavaScript's string iterator yields them).
fn code_points(s : String, n : Int32) -> Int32 {
  let mut count = n
  for i in 1..<n {
    if s[i].to_int() is (0xdc00..<=0xdfff) &&
      s[i - 1].to_int() is (0xd800..<=0xdbff) {
      count -= 1
    }
  }
  count
}

///|
/// `Array.prototype.slice`'s bounds for `begin` and `end` over `len` items.
fn slice_range(begin : Double, end : Double, len : Int32) -> (Int32, Int32) {
  let at = (x : Double) => {
    let x = if x != x { 0.0 } else { x.trunc() }
    let l = len.to_double()
    (if x < 0.0 { @cmp.maximum(l + x, 0.0) } else { @cmp.minimum(x, l) }).to_int()
  }
  let a = at(begin)
  (a, @cmp.maximum(a, at(end)))
}

///|
/// JavaScript's `Math.round` for numbers that are not negative.
fn js_round(x : Double) -> Double {
  let f = x.floor()
  if x - f >= 0.5 {
    f + 1.0
  } else {
    f
  }
}

///|
/// JavaScript's `toUpperCase` / `toLowerCase` for Latin (ASCII, Latin-1,
/// Extended-A and fullwidth) and Cyrillic letters; others are kept.
fn change_case(s : String, up : Bool) -> String {
  let out = StringBuilder()
  for c in s {
    let k = c.to_int()
    // Latin Extended-A pairs a capital with the small letter after it.
    let paired = k is (0x100..<=0x17e) &&
      k != 0x130 &&
      k != 0x131 &&
      k != 0x138 &&
      k != 0x149 &&
      k != 0x178
    let capital = paired &&
      (k % 2 == 0) == (k < 0x138 || (k > 0x149 && k < 0x178))
    let shifted = if up {
      match k {
        0x61..<=0x7a | 0xe0..<=0xfe | 0x430..<=0x44f | 0xff41..<=0xff5a if k !=
          0xf7 => k - 0x20
        0x450..<=0x45f => k - 0x50
        0xb5 => 0x39c
        0xff => 0x178
        0x131 => 0x49
        0x17f => 0x53
        0xdf => {
          out.write_string("SS")
          continue
        }
        0x149 => {
          out.write_string("\u{2BC}N")
          continue
        }
        _ => if paired && !capital { k - 1 } else { k }
      }
    } else {
      match k {
        0x41..<=0x5a | 0xc0..<=0xde | 0x410..<=0x42f | 0xff21..<=0xff3a if k !=
          0xd7 => k + 0x20
        0x400..<=0x40f => k + 0x50
        0x178 => 0xff
        0x130 => {
          out.write_string("i\u{307}")
          continue
        }
        _ => if capital { k + 1 } else { k }
      }
    }
    out.write_char(shifted.unsafe_to_char())
  }
  out.to_string()
}

///|
/// MapLibre's `typeToString(typeOf(v))`.
fn type_of(v : Value) -> String {
  match v {
    Null => "null"
    Bool(_) => "boolean"
    Num(_) => "number"
    Str(_) => "string"
    Color(_) => "color"
    Formatted(_) => "formatted"
    Collator(_, _, _) => "collator"
    Failed => "error"
    List(xs) => {
      // Array types are compared by identity: two array items never match.
      let item = match xs {
        [] => "value"
        [x] => type_of(x)
        [List(_), ..] => "value"
        [x, .. rest] => {
          let t = type_of(x)
          if rest.iter().all(y => !(y is List(_)) && type_of(y) == t) {
            t
          } else {
            "value"
          }
        }
      }
      "array<\{item}, \{xs.length()}>"
    }
  }
}

///|
/// JavaScript's `String(v)`.
fn[C : FeatureContext] js_string(ctx : C, v : Value) -> String {
  match v {
    Null => "null"
    List(xs) =>
      xs.map(x => if x is Null { "" } else { js_string(ctx, x) }).join(",")
    _ => value_to_string(ctx, v)
  }
}

///|
/// MapLibre's `valueToString`: what `to-string` and `concat` make of `v`.
fn[C : FeatureContext] value_to_string(ctx : C, v : Value) -> String {
  match v {
    Null | Failed => ""
    Bool(b) => b.to_string()
    Num(x) => ctx.number_text(x)
    Str(s) => s
    Color(c) => {
      let ch = (x : Double) => js_round(x * 255.0).to_int().to_string()
      "rgba(\{ch(c.r)},\{ch(c.g)},\{ch(c.b)},\{ctx.number_text(c.a)})"
    }
    List(_) => json_text(ctx, v)
    Formatted(sections) => sections.map(s => s.text).join("")
    // MapLibre's parser keeps collators out of strings.
    Collator(_, _, _) => ""
  }
}

///|
/// JavaScript's `s.split(d)`: an empty `d` splits between UTF-16 code units.
fn js_split(s : String, d : String) -> Array[Value] {
  if d == "" {
    return Array::makei(s.length(), i => {
      Str(s.unsafe_substring(start=i, end=i + 1))
    })
  }
  let out = []
  let mut start = 0
  let mut i = 0
  while i + d.length() <= s.length() {
    if s.has_prefix_at(d, i) {
      out.push(Str(s.unsafe_substring(start~, end=i)))
      i += d.length()
      start = i
    } else {
      i += 1
    }
  }
  out.push(Str(s.unsafe_substring(start~, end=s.length())))
  out
}

///|
/// `JSON.stringify(v)`; a color is MapLibre's object of premultiplied
/// channels.
fn[C : FeatureContext] json_text(ctx : C, v : Value) -> String {
  match v {
    Num(x) =>
      if x == x && x.abs() != @double.infinity {
        ctx.number_text(x)
      } else {
        "null"
      }
    Str(s) => {
      let out = StringBuilder()
      out.write_char('"')
      for c in s {
        match c {
          '"' | '\\' => {
            out.write_char('\\')
            out.write_char(c)
          }
          '\n' => out.write_string("\\n")
          '\r' => out.write_string("\\r")
          '\t' => out.write_string("\\t")
          '\b' => out.write_string("\\b")
          '\u{0C}' => out.write_string("\\f")
          _ if c.to_int() < 0x20 => {
            out.write_string("\\u00")
            out.write_char(if c.to_int() < 0x10 { '0' } else { '1' })
            out.write_char(hex_char(c.to_int() & 15))
          }
          _ => out.write_char(c)
        }
      }
      out.write_char('"')
      out.to_string()
    }
    List(xs) => "[" + xs.map(x => json_text(ctx, x)).join(",") + "]"
    Color(c) => {
      let n = (x : Double) => json_text(ctx, Num(x))
      "{\"r\":\{n(c.r * c.a)},\"g\":\{n(c.g * c.a)},\"b\":\{n(c.b * c.a)},\"a\":\{n(c.a)}}"
    }
    Null | Failed | Formatted(_) | Collator(_, _, _) => "null"
    Bool(b) => b.to_string()
  }
}

///|
fn hex_char(d : Int32) -> Char {
  (if d < 10 { 48 + d } else { 87 + d }).unsafe_to_char()
}

///|
/// JavaScript's `Number(s)`: decimal, `Infinity`, `0x`/`0o`/`0b` integers and
/// blank text (0) between white space; NaN otherwise.
pub fn js_number(s : String) -> Double {
  let mut a = 0
  let mut b = s.length()
  while a < b && js_space(s[a].to_int()) {
    a += 1
  }
  while b > a && js_space(s[b - 1].to_int()) {
    b -= 1
  }
  if a == b {
    return 0.0
  }
  let at = (i : Int32) => if i < b { s[i].to_int() } else { -1 }
  if b - a > 2 && at(a) == '0' {
    let radix = match at(a + 1) | 0x20 {
      'x' => 16
      'o' => 8
      'b' => 2
      _ => 0
    }
    if radix > 0 {
      let mut v = 0.0
      for i in (a + 2)..<b {
        let d = hex_digit(s[i])
        if d < 0 || d >= radix {
          return @double.not_a_number
        }
        v = v * radix.to_double() + d.to_double()
      }
      return v
    }
  }
  let text = StringBuilder()
  let mut i = a
  if at(i) == '-' || at(i) == '+' {
    if at(i) == '-' {
      text.write_char('-')
    }
    i += 1
  }
  if s[i:b] == "Infinity" {
    return if at(a) == '-' { @double.neg_infinity } else { @double.infinity }
  }
  let digits = () => {
    let from = i
    while at(i) is ('0'..<='9') {
      text.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
    i - from
  }
  while at(i) == '0' && at(i + 1) is ('0'..<='9') {
    i += 1
  }
  let int_digits = digits()
  if int_digits == 0 {
    text.write_char('0')
  }
  let mut frac_digits = 0
  if at(i) == '.' {
    i += 1
    text.write_char('.')
    frac_digits = digits()
    if frac_digits == 0 {
      text.write_char('0')
    }
  }
  if int_digits + frac_digits == 0 {
    return @double.not_a_number
  }
  if at(i) == 'e' || at(i) == 'E' {
    text.write_char('e')
    i += 1
    if at(i) == '-' || at(i) == '+' {
      text.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
    if digits() == 0 {
      return @double.not_a_number
    }
  }
  if i != b {
    return @double.not_a_number
  }
  @core.strconv_number(@utf8.encode(text.to_string())[:])
}

///|
/// JavaScript's white space and line terminators, which `Number` trims.
fn js_space(c : Int32) -> Bool {
  c
  is (0x09..<=0x0d
  | 0x20
  | 0xa0
  | 0x1680
  | 0x2000..<=0x200a
  | 0x2028
  | 0x2029
  | 0x202f
  | 0x205f
  | 0x3000
  | 0xfeff)
}
