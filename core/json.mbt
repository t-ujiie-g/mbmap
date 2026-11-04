///|
/// Powers of ten that doubles hold exactly.
let exact_powers : FixedArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22,
]

///|
/// The JSON number at `start` of `b` and the position after it (NaN and `start`
/// if none). Clinger's exact fast path takes up to 15 digits and exponents within
/// ±22; the rest goes to `slow_number` (a wasm host's `Number()`, say).
pub fn read_json_number(
  b : BytesView,
  start : Int32,
  slow_number : (Int32, Int32) -> Double,
) -> (Double, Int32) {
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
    return (@double.not_a_number, start)
  }
  if digits <= 15 && exponent.abs() <= 22 {
    let m = mantissa.to_double()
    let v = if exponent < 0 {
      m / exact_powers[-exponent]
    } else {
      m * exact_powers[exponent]
    }
    return (if negative { -v } else { v }, i)
  }
  let v = slow_number(start, i)
  if v.is_nan() {
    (v, start)
  } else {
    (v, i)
  }
}

///|
/// A JSON number's text parsed with core `strconv` (NaN if it is not one):
/// the slow path where a host's `Number()` is not at hand.
pub fn strconv_number(text : BytesView) -> Double {
  @string.parse_double(utf8_lossy(text)) catch {
    _ => @double.not_a_number
  }
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
/// The content of a JSON string (between its quotes) as text, escapes
/// resolved and invalid UTF-8 replaced.
pub fn json_string_text(s : BytesView) -> String {
  if !s.iter().any(c => c == b'\\') {
    return utf8_lossy(s)
  }
  let sb = StringBuilder()
  let mut i = 0
  let mut run = 0
  let end = s.length()
  while i < end {
    if s[i] != b'\\' {
      i += 1
      continue
    }
    sb.write_string(utf8_lossy(s[run:i]))
    let c = if i + 1 < end { s[i + 1] } else { b' ' }
    // A lone `\` at the end steps past it only.
    i = @cmp.minimum(i + 2, end)
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
          let h = hex(s[i + k])
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
  sb.write_string(utf8_lossy(s[run:end]))
  sb.to_string()
}

///|
/// Why `parse_json` refused its input: at which byte, and what.
pub(all) suberror JsonError {
  JsonError(pos~ : Int32, String)
}

///|
pub fn JsonError::message(self : JsonError) -> String {
  let JsonError(pos~, why) = self
  "\{why} at \{pos}"
}

///|
priv struct JsonParser {
  b : BytesView
  slow_number : (Int32, Int32) -> Double
  max_depth : Int32
  mut pos : Int32
}

///|
fn JsonParser::fail(self : JsonParser, why : String) -> JsonError {
  JsonError(pos=self.pos, why)
}

///|
/// The next non-space byte, or -1 at the end.
fn JsonParser::peek(self : JsonParser) -> Int32 {
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1
      c => return c.to_int()
    }
  }
  -1
}

///|
fn JsonParser::expect(self : JsonParser, c : Char) -> Unit raise JsonError {
  if self.peek() != c.to_int() {
    raise self.fail("expected '\{c}'")
  }
  self.pos += 1
}

///|
fn JsonParser::string(self : JsonParser) -> String raise JsonError {
  self.expect('"')
  let start = self.pos
  while self.pos < self.b.length() {
    match self.b[self.pos] {
      b'"' => {
        self.pos += 1
        return json_string_text(self.b[start:self.pos - 1])
      }
      b'\\' => self.pos += 2
      c if c < b' ' => raise self.fail("control character in string")
      _ => self.pos += 1
    }
  }
  raise self.fail("unterminated string")
}

///|
fn JsonParser::literal(
  self : JsonParser,
  word : String,
  value : Json,
) -> Json raise JsonError {
  let n = word.length()
  if self.pos + n > self.b.length() {
    raise self.fail("invalid literal")
  }
  for i in 0..<n {
    if self.b[self.pos + i].to_int() != word.code_unit_at(i).to_int() {
      raise self.fail("invalid literal")
    }
  }
  self.pos += n
  value
}

///|
fn JsonParser::value(self : JsonParser, depth : Int32) -> Json raise JsonError {
  match self.peek() {
    '{' => {
      if depth >= self.max_depth {
        raise self.fail("nested deeper than \{self.max_depth}")
      }
      self.pos += 1
      let members : Map[String, Json] = Map([])
      if self.peek() == '}' {
        self.pos += 1
        return Json::object(members)
      }
      while true {
        let key = self.string()
        self.expect(':')
        members[key] = self.value(depth + 1)
        if self.peek() == ',' {
          self.pos += 1
        } else {
          break
        }
      }
      self.expect('}')
      Json::object(members)
    }
    '[' => {
      if depth >= self.max_depth {
        raise self.fail("nested deeper than \{self.max_depth}")
      }
      self.pos += 1
      let items : Array[Json] = []
      if self.peek() == ']' {
        self.pos += 1
        return Json::array(items)
      }
      while true {
        items.push(self.value(depth + 1))
        if self.peek() == ',' {
          self.pos += 1
        } else {
          break
        }
      }
      self.expect(']')
      Json::array(items)
    }
    '"' => Json::string(self.string())
    't' => self.literal("true", Json::boolean(true))
    'f' => self.literal("false", Json::boolean(false))
    'n' => self.literal("null", Json::null())
    _ => {
      let (v, end) = read_json_number(self.b, self.pos, self.slow_number)
      if end == self.pos {
        raise self.fail("invalid value")
      }
      self.pos = end
      Json::number(v)
    }
  }
}

///|
/// Parses the UTF-8 JSON text `b` (nesting up to `max_depth`). Numbers past
/// the fast path of `read_json_number` go to `slow_number` with their range
/// in `b`; `strconv_number` is the default.
pub fn parse_json(
  b : BytesView,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => strconv_number(b[s:e]),
  max_depth~ : Int32 = 64,
) -> Json raise JsonError {
  let p = { b, slow_number, max_depth, pos: 0, }
  let v = p.value(0)
  if p.peek() >= 0 {
    raise p.fail("unexpected text after the value")
  }
  v
}
