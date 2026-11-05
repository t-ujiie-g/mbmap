///|
/// Whether the code point at byte `j` is not XML's `Char`: a C0 control other
/// than tab, line feed and carriage return, or U+FFFE / U+FFFF. (Malformed UTF-8
/// reads as U+FFFD, which is one.)
fn not_char(b : Bytes, j : Int32, end : Int32) -> Bool {
  let c = b[j]
  (c < b' ' && c != b'\t' && c != b'\n' && c != b'\r') ||
  (
    c == b'\xEF' &&
    j + 2 < end &&
    b[j + 1] == b'\xBF' &&
    (b[j + 2] == b'\xBE' || b[j + 2] == b'\xBF')
  )
}

///|
/// XML's `S`: space, tab, carriage return, line feed.
fn is_space(c : Byte) -> Bool {
  c == b' ' || c == b'\t' || c == b'\r' || c == b'\n'
}

///|
/// xmldom's `NameStartChar` (`:` included).
fn is_name_start(c : Int32) -> Bool {
  (c >= 0x61 && c <= 0x7A) ||
  (c >= 0x41 && c <= 0x5A) ||
  c == 0x5F ||
  c == 0x3A ||
  (c >= 0xC0 && c <= 0xD6) ||
  (c >= 0xD8 && c <= 0xF6) ||
  (c >= 0xF8 && c <= 0x2FF) ||
  (c >= 0x370 && c <= 0x1FFF) ||
  (c >= 0x200C && c <= 0x200D) ||
  (c >= 0x2070 && c <= 0x218F) ||
  (c >= 0x2C00 && c <= 0x2FEF) ||
  (c >= 0x3001 && c <= 0xD7FF) ||
  (c >= 0xF900 && c <= 0xFDCF) ||
  (c >= 0xFDF0 && c <= 0xFFFD) ||
  (c >= 0x10000 && c <= 0x10FFFF)
}

///|
/// xmldom's `NameChar`.
fn is_name_char(c : Int32) -> Bool {
  is_name_start(c) ||
  c == 0x2D ||
  c == 0x2E ||
  (c >= 0x30 && c <= 0x39) ||
  c == 0xB7 ||
  (c >= 0x300 && c <= 0x36F) ||
  (c >= 0x203F && c <= 0x2040)
}

///|
/// Whether byte `c` may start a name: an ASCII letter, `_`, `:` or any byte of a
/// non-ASCII character (which `is_qname` checks exactly where it matters).
fn is_name_byte(c : Byte, first : Bool) -> Bool {
  (c >= b'a' && c <= b'z') ||
  (c >= b'A' && c <= b'Z') ||
  c == b'_' ||
  c == b':' ||
  c >= b'\x80' ||
  (!first && ((c >= b'0' && c <= b'9') || c == b'-' || c == b'.'))
}

///|
/// Where the name at `i` ends (`i` if there is none); colons are left out
/// unless `colons`.
fn name_end(b : Bytes, i : Int32, end : Int32, colons~ : Bool = true) -> Int32 {
  let mut j = i
  while j < end && is_name_byte(b[j], j == i) && (colons || b[j] != b':') {
    j += 1
  }
  j
}

///|
/// Whether `q` is a `QName`: an `NCName`, or two joined by one colon.
fn is_qname(q : String) -> Bool {
  let mut at_start = true
  let mut colons = 0
  for c in q {
    let c = c.to_int()
    if c == 0x3A {
      if at_start || colons == 1 {
        return false
      }
      colons = 1
      at_start = true
    } else if at_start {
      if !is_name_start(c) {
        return false
      }
      at_start = false
    } else if !is_name_char(c) {
      return false
    }
  }
  !at_start
}

///|
/// Whether `c` is an ASCII letter, digit or `_` (a regular expression's `\w`).
fn is_word(c : Byte) -> Bool {
  (c >= b'a' && c <= b'z') ||
  (c >= b'A' && c <= b'Z') ||
  (c >= b'0' && c <= b'9') ||
  c == b'_'
}

///|
/// Whether code unit `c` is white space to JavaScript (`\s`, `trim`, `parseFloat`).
pub fn is_js_space(c : UInt16) -> Bool {
  let c = c.to_int()
  c == 0x20 ||
  (c >= 0x09 && c <= 0x0D) ||
  c == 0xA0 ||
  c == 0x1680 ||
  (c >= 0x2000 && c <= 0x200A) ||
  c == 0x2028 ||
  c == 0x2029 ||
  c == 0x202F ||
  c == 0x205F ||
  c == 0x3000 ||
  c == 0xFEFF
}
