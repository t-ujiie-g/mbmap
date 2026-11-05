///|
let hex_digits : String = "0123456789abcdef"

///|
/// `JSON.stringify(s)` as well-formed `JSON.stringify` writes it: lone
/// surrogates escaped.
fn json_string(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s[i].to_int()
    let pair = c >= 0xD800 &&
      c <= 0xDBFF &&
      i + 1 < n &&
      s[i + 1].to_int() >= 0xDC00 &&
      s[i + 1].to_int() <= 0xDFFF
    if pair {
      out.write_view(s.clamped_view(start=i, end=i + 2))
      i += 2
      continue
    }
    match c {
      0x22 => out.write_string("\\\"")
      0x5C => out.write_string("\\\\")
      0x08 => out.write_string("\\b")
      0x0C => out.write_string("\\f")
      0x0A => out.write_string("\\n")
      0x0D => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      _ =>
        if c < 0x20 || (c >= 0xD800 && c <= 0xDFFF) {
          out.write_string("\\u")
          for k in 0..<4 {
            out.write_char(
              hex_digits[(c >> (12 - 4 * k)) & 0xF].to_int().unsafe_to_char(),
            )
          }
        } else {
          out.write_char(c.unsafe_to_char())
        }
    }
    i += 1
  }
  out.write_char('"')
  out.to_string()
}

///|
/// `JSON.stringify(x)`: `number_text` (the host's `String`), `null` if not finite.
fn Reader::json_number(self : Reader, x : Double) -> String {
  if x.is_nan() || x.is_inf() {
    "null"
  } else {
    (self.number_text)(x)
  }
}

///|
/// A JSON array of `items[start:end]` (JSON texts).
fn json_array(items : Array[String], start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  out.write_char('[')
  for i in start..<end {
    if i > start {
      out.write_char(',')
    }
    out.write_string(items[i])
  }
  out.write_char(']')
  out.to_string()
}

///|
/// A JSON object of `keys` and their `values` (JSON texts) in order.
fn json_object(keys : Array[String], values : Array[String]) -> String {
  let out = StringBuilder()
  out.write_char('{')
  for i, k in keys {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(json_string(k))
    out.write_char(':')
    out.write_string(values[i])
  }
  out.write_char('}')
  out.to_string()
}
