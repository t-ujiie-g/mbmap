///|
fn Parser::fail(self : Parser, message : String) -> Unit {
  if self.error is None {
    self.error = Some((self.pos, message))
  }
  self.pos = self.b.length()
}

///|
/// The next non-space byte, or -1 at the end.
fn Parser::peek(self : Parser) -> Int32 {
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1
      c => return c.to_int()
    }
  }
  -1
}

///|
fn Parser::expect(self : Parser, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    self.fail("expected '\{c}'")
    false
  }
}

///|
/// Enters an array or object; false (and an error) past `MAX_GEOJSON_DEPTH`.
fn Parser::enter(self : Parser) -> Bool {
  self.depth += 1
  if self.depth > MAX_GEOJSON_DEPTH {
    self.fail("nested deeper than \{MAX_GEOJSON_DEPTH}")
    return false
  }
  true
}

///|
/// Calls `on_member` for each key of the object at the position, with the
/// parser at the member's value; `on_member` must consume the value.
fn Parser::object(
  self : Parser,
  on_member : (Int32, Int32, Bool) -> Unit,
) -> Unit {
  if !self.expect('{') || !self.enter() {
    return
  }
  if self.peek() == '}'.to_int() {
    self.pos += 1
    self.depth -= 1
    return
  }
  while self.error is None {
    let (start, end, escaped) = self.string_raw()
    if !self.expect(':') {
      return
    }
    on_member(start, end, escaped)
    match self.peek() {
      ',' => self.pos += 1
      '}' => {
        self.pos += 1
        self.depth -= 1
        return
      }
      _ => self.fail("expected ',' or '}'")
    }
  }
}

///|
/// Calls `element` for each element of the array at the position; `element`
/// must consume it.
fn Parser::array(self : Parser, element : () -> Unit) -> Unit {
  if !self.expect('[') || !self.enter() {
    return
  }
  if self.peek() == ']'.to_int() {
    self.pos += 1
    self.depth -= 1
    return
  }
  while self.error is None {
    element()
    match self.peek() {
      ',' => self.pos += 1
      ']' => {
        self.pos += 1
        self.depth -= 1
        return
      }
      _ => self.fail("expected ',' or ']'")
    }
  }
}

///|
/// A string's content range (without quotes) and whether it has escapes.
fn Parser::string_raw(self : Parser) -> (Int32, Int32, Bool) {
  if !self.expect('"') {
    return (0, 0, false)
  }
  let start = self.pos
  let mut escaped = false
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b'"' => {
        self.pos += 1
        return (start, self.pos - 1, escaped)
      }
      b'\\' => {
        escaped = true
        self.pos += 2
      }
      c if c < b' ' => {
        self.fail("control character in string")
        return (0, 0, false)
      }
      _ => self.pos += 1
    }
  }
  self.fail("unterminated string")
  (0, 0, false)
}

///|
/// Whether the unescaped key `start..<end` is the ASCII `name`.
fn Parser::matches(
  self : Parser,
  start : Int32,
  end : Int32,
  name : String,
) -> Bool {
  if end - start != name.length() {
    return false
  }
  for i in 0..<name.length() {
    if self.b[start + i].to_int() != name.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn hex(c : Byte) -> Int32 {
  match c {
    b'0'..<=b'9' => c.to_int() - '0'.to_int()
    b'a'..<=b'f' => c.to_int() - 'a'.to_int() + 10
    b'A'..<=b'F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// The string `start..<end` as text, with escapes resolved and invalid UTF-8
/// replaced.
fn Parser::text(
  self : Parser,
  start : Int32,
  end : Int32,
  escaped : Bool,
) -> String {
  if !escaped {
    return @utf8.decode_lossy(self.b[start:end])
  }
  let sb = StringBuilder()
  let mut i = start
  let mut run = start
  while i < end {
    if self.b[i] != b'\\' {
      i += 1
      continue
    }
    sb.write_string(@utf8.decode_lossy(self.b[run:i]))
    let c = if i + 1 < end { self.b[i + 1] } else { b' ' }
    i += 2
    match c {
      b'"' => sb.write_char('"')
      b'\\' => sb.write_char('\\')
      b'/' => sb.write_char('/')
      b'b' => sb.write_char('\b')
      b'f' => sb.write_char('\u{0C}')
      b'n' => sb.write_char('\n')
      b'r' => sb.write_char('\r')
      b't' => sb.write_char('\t')
      b'u' if i + 4 <= end => {
        let mut v = 0
        for k in 0..<4 {
          let h = hex(self.b[i + k])
          v = if h < 0 || v < 0 { -1 } else { v * 16 + h }
        }
        i += 4
        // Surrogates go out as UTF-16 code units, which String holds.
        sb.write_char(Int32::unsafe_to_char(if v < 0 { 0xFFFD } else { v }))
      }
      _ => sb.write_char('\u{FFFD}')
    }
    run = i
  }
  sb.write_string(@utf8.decode_lossy(self.b[run:end]))
  sb.to_string()
}

///|
/// Powers of ten that doubles hold exactly.
let exact_powers : FixedArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22,
]

///|
/// A JSON number. Up to 15 digits with an exponent within ±22 take Clinger's
/// exact fast path; anything else goes to `slow_number`.
fn Parser::number(self : Parser) -> Double {
  self.peek() |> ignore
  let b = self.b
  let start = self.pos
  let mut i = start
  let negative = i < b.length() && b[i] == b'-'
  if negative {
    i += 1
  }
  let mut mantissa = 0L
  let mut digits = 0
  let mut exponent = 0
  let mut any = false
  while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
    if digits < 18 {
      mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
      if mantissa > 0L {
        digits += 1
      }
    } else {
      exponent += 1
      digits += 1
    }
    any = true
    i += 1
  }
  // JSON wants digits on both sides of the point.
  let int_part = any
  if i < b.length() && b[i] == b'.' {
    i += 1
    any = false
    while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
      if digits < 18 {
        mantissa = mantissa * 10L + (b[i].to_int() - '0'.to_int()).to_int64()
        if mantissa > 0L {
          digits += 1
        }
        exponent -= 1
      } else {
        digits += 1
      }
      any = true
      i += 1
    }
  }
  if i < b.length() && (b[i] == b'e' || b[i] == b'E') {
    i += 1
    let mut sign = 1
    if i < b.length() && (b[i] == b'+' || b[i] == b'-') {
      sign = if b[i] == b'-' { -1 } else { 1 }
      i += 1
    }
    let mut e = 0
    let mut any_e = false
    while i < b.length() && b[i] >= b'0' && b[i] <= b'9' {
      e = @cmp.minimum(e * 10 + (b[i].to_int() - '0'.to_int()), 100000)
      any_e = true
      i += 1
    }
    if !any_e {
      any = false
    }
    exponent += sign * e
  }
  if !any || !int_part {
    self.fail("invalid number")
    return 0.0
  }
  self.pos = i
  if digits <= 15 && exponent.abs() <= 22 {
    let m = mantissa.to_double()
    let v = if exponent < 0 {
      m / exact_powers[-exponent]
    } else {
      m * exact_powers[exponent]
    }
    return if negative { -v } else { v }
  }
  let v = (self.slow_number)(start, i)
  if v.is_nan() {
    self.pos = start
    self.fail("invalid number")
    return 0.0
  }
  v
}

///|
/// A JSON number's text parsed with core `strconv` (NaN if it is not one):
/// the default slow path of `read_geojson`.
pub fn strconv_number(text : BytesView) -> Double {
  @string.parse_double(@utf8.decode_lossy(text)) catch {
    _ => @double.not_a_number
  }
}

///|
/// Skips a literal (`true`, `false` or `null`); false if it is not `word`.
fn Parser::literal(self : Parser, word : String) -> Bool {
  if self.pos + word.length() > self.b.length() ||
    !self.matches(self.pos, self.pos + word.length(), word) {
    self.fail("invalid literal")
    return false
  }
  self.pos += word.length()
  true
}

///|
/// Skips any JSON value.
fn Parser::skip(self : Parser) -> Unit {
  match self.peek() {
    '{' | '[' => self.skip_nested()
    '"' => self.string_raw() |> ignore
    't' => self.literal("true") |> ignore
    'f' => self.literal("false") |> ignore
    'n' => self.literal("null") |> ignore
    _ => self.number() |> ignore
  }
}

///|
/// Skips an object or array by matching brackets, honoring strings and the
/// depth limit. It does not check the commas and colons inside: values the
/// reader ignores need not be valid JSON, only bounded.
fn Parser::skip_nested(self : Parser) -> Unit {
  let b = self.b
  let mut nested = 0
  while self.pos < b.length() {
    match b[self.pos] {
      b'{' | b'[' => {
        nested += 1
        if self.depth + nested > MAX_GEOJSON_DEPTH {
          self.fail("nested deeper than \{MAX_GEOJSON_DEPTH}")
          return
        }
      }
      b'}' | b']' => {
        nested -= 1
        if nested == 0 {
          self.pos += 1
          return
        }
      }
      b'"' => {
        self.string_raw() |> ignore
        continue
      }
      _ => ()
    }
    self.pos += 1
  }
  self.fail("unterminated array or object")
}

///|
/// The JSON text `start..<end` without whitespace outside strings.
fn Parser::compact(self : Parser, start : Int32, end : Int32) -> String {
  let out : Array[Byte] = []
  let mut in_string = false
  let mut i = start
  while i < end {
    let c = self.b[i]
    if in_string {
      out.push(c)
      if c == b'\\' && i + 1 < end {
        out.push(self.b[i + 1])
        i += 1
      } else if c == b'"' {
        in_string = false
      }
    } else if !(c == b' ' || c == b'\t' || c == b'\n' || c == b'\r') {
      out.push(c)
      in_string = c == b'"'
    }
    i += 1
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}
