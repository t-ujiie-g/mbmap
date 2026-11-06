// Ported from @xmldom/xmldom 0.9.12: MIT License, Copyright 2019 - present Christopher J. Brody
// and other contributors, Copyright 2012 - 2017 @jindw and other contributors. See NOTICE.

///|
/// `s` with its references replaced as xmldom replaces them (`/&#?\w+;?/`): the five
/// XML entities and character references; anything else (a declared entity, a missing
/// `;`) is kept as written, so entities never expand into more entities.
fn entities(s : String) -> String {
  let n = s.length()
  let out = StringBuilder()
  let mut last = 0
  let mut i = 0
  while i < n {
    if s[i] != '&' {
      i += 1
      continue
    }
    let hash = i + 1 < n && s[i + 1] == '#'
    let first = if hash { i + 2 } else { i + 1 }
    let mut w = first
    while w < n && s[w] < 0x80 && is_word(s[w].to_byte()) {
      w += 1
    }
    if w == first {
      i += 1
      continue
    }
    let semi = w < n && s[w] == ';'
    let stop = if semi { w + 1 } else { w }
    let value = if semi { reference(s, hash, first, w) } else { None }
    if value is Some(v) {
      write_units(out, s, last, i)
      out.write_string(v)
      last = stop
    }
    i = stop
  }
  write_units(out, s, last, n)
  out.to_string()
}

///|
/// What `&name;` or `&#digits;` (`s[start:end]` the word after `&` or `&#`) stands
/// for, or None if xmldom keeps it.
fn reference(s : String, hash : Bool, start : Int32, end : Int32) -> String? {
  if !hash {
    let name = units(s, start, end)
    return match name {
      "amp" => Some("&")
      "apos" => Some("'")
      "gt" => Some(">")
      "lt" => Some("<")
      "quot" => Some("\"")
      _ => None
    }
  }
  let hex = s[start] == 'x'
  let from = if hex { start + 1 } else { start }
  guard from < end else { return None }
  let mut code = 0.0
  for i in from..<end {
    let c = s[i].to_int()
    let d = if c >= 0x30 && c <= 0x39 {
      c - 0x30
    } else if hex && c >= 0x61 && c <= 0x66 {
      c - 0x61 + 10
    } else if hex && c >= 0x41 && c <= 0x46 {
      c - 0x41 + 10
    } else {
      return None
    }
    code = code * (if hex { 16.0 } else { 10.0 }) + d.to_double()
  }
  Some(from_char_code(code))
}

///|
/// xmldom's `fixedFromCharCode`: a surrogate pair above U+FFFF, computed with
/// JavaScript's 32-bit shifts and `String.fromCharCode`'s 16-bit truncation.
fn from_char_code(code : Double) -> String {
  let out = StringBuilder()
  if code > 65535.0 {
    let c = to_int32(code - 65536.0)
    out.write_char(((0xD800 + (c >> 10)) & 0xFFFF).unsafe_to_char())
    out.write_char(((0xDC00 + (c & 0x3FF)) & 0xFFFF).unsafe_to_char())
  } else {
    out.write_char(code.to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
/// JavaScript's `ToInt32` of a non-negative `x`.
fn to_int32(x : Double) -> Int32 {
  guard x == x && x < 1.0e308 * 10.0 else { return 0 }
  let m = x - (x / 4294967296.0).floor() * 4294967296.0
  if m >= 2147483648.0 {
    (m - 4294967296.0).to_int()
  } else {
    m.to_int()
  }
}

///|
/// Code units `start` to `end` of `s` (which may split a surrogate pair).
pub fn units(s : String, start : Int32, end : Int32) -> String {
  let out = StringBuilder()
  write_units(out, s, start, end)
  out.to_string()
}

///|
fn write_units(
  out : StringBuilder,
  s : String,
  start : Int32,
  end : Int32,
) -> Unit {
  for i in start..<end {
    out.write_char(s[i].to_int().unsafe_to_char())
  }
}
