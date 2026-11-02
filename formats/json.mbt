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
/// The string `start..<end` as text, with escapes resolved and invalid UTF-8
/// replaced.
fn Parser::text(
  self : Parser,
  start : Int32,
  end : Int32,
  escaped : Bool,
) -> String {
  if escaped {
    @core.json_string_text(self.b[start:end])
  } else {
    @core.utf8_lossy(self.b[start:end])
  }
}

///|
/// A JSON number (`@core.read_json_number`; `slow_number` past its fast path).
fn Parser::number(self : Parser) -> Double {
  self.peek() |> ignore
  let (v, end) = @core.read_json_number(self.b, self.pos, self.slow_number)
  if end == self.pos {
    self.fail("invalid number")
    return 0.0
  }
  self.pos = end
  v
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
  @core.utf8_lossy(Bytes::from_array(out))
}
