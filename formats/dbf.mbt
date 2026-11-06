// Ported from shpjs 6.2.0 and parsedbf 2.0.0: MIT License, Copyright (c) 2013 Calvin Metcalf
// and other shapefile-js contributors. See NOTICE.

///|
/// Most property cells (records times fields) a DBF may make (AGENTS.md §8.2).
pub const MAX_DBF_CELLS : Int32 = 32_000_000

///|
/// A DBF field read into a column: its name, type (`C`, `N`, `F`, `L` or `D`) and
/// bytes within a record.
priv struct DbfField {
  name : String
  kind : Byte
  start : Int32
  len : Int32
}

///|
/// A dBASE table (as a shapefile's .dbf): `count` records of `record_len` bytes
/// from `header_len`, each led by its deletion flag.
priv struct Dbf {
  b : BytesView
  fields : Array[DbfField]
  count : Int32
  header_len : Int32
  record_len : Int32
}

///|
fn le_u16(b : BytesView, i : Int32) -> Int32 {
  b[i].to_int() | (b[i + 1].to_int() << 8)
}

///|
fn le_i32(b : BytesView, i : Int32) -> Int32 {
  let mut v = 0
  for k in 0..<4 {
    v = v | (b[i + k].to_int() << (k * 8))
  }
  v
}

///|
/// The range of `b[start:end]` without white space and NULs at either end, as
/// JavaScript's `trim` and DBF padding have them.
fn trimmed(b : BytesView, start : Int32, end : Int32) -> (Int32, Int32) {
  let blank = (c : Byte) => {
    c == b' ' || c == b'\x00' || (c >= b'\t' && c <= b'\r')
  }
  let mut s = start
  let mut e = end
  while s < e && blank(b[s]) {
    s += 1
  }
  while e > s && blank(b[e - 1]) {
    e -= 1
  }
  (s, e)
}

///|
/// The text of `b[start:end]`, trimmed: ASCII read here, anything else by `text`
/// (which decodes in the table's encoding, NULs removed and trimmed).
fn dbf_text(
  b : BytesView,
  start : Int32,
  end : Int32,
  text : (Int32, Int32) -> String,
) -> String {
  let (s, e) = trimmed(b, start, end)
  for i in s..<e {
    if b[i] >= b'\x80' || b[i] == b'\x00' {
      return text(s, e)
    }
  }
  let sb = StringBuilder()
  for i in s..<e {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
fn dbf_error(m : String) -> ReadError {
  Invalid(format="DBF", pos=0, m)
}

///|
/// Reads a DBF's header and field descriptors, checked against its length: the
/// records it holds whole are read (`count`); fields of types other than C, N, F,
/// L and D (memos, binary numbers) are left out; at most `max_cells` cells.
fn Dbf::new(
  b : BytesView,
  text : (Int32, Int32) -> String,
  max_cells : Int32,
) -> Dbf raise ReadError {
  guard b.length() >= 32 else { raise dbf_error("the header is cut short") }
  let records = le_i32(b, 4)
  let header_len = le_u16(b, 8)
  let record_len = le_u16(b, 10)
  guard records >= 0 &&
    header_len >= 33 &&
    header_len <= b.length() &&
    record_len >= 1 else {
    raise dbf_error("invalid header")
  }
  let fields = []
  let names = []
  let mut start = 1
  let mut at = 32
  while at + 32 <= header_len && b[at] != b'\x0d' {
    let mut name_end = at
    while name_end < at + 11 && b[name_end] != b'\x00' {
      name_end += 1
    }
    let kind = b[at + 11]
    // Character fields longer than 255 bytes keep the high byte in the decimal count.
    let len = b[at + 16].to_int() +
      (if kind == b'C' { b[at + 17].to_int() * 256 } else { 0 })
    if kind == b'C' ||
      kind == b'N' ||
      kind == b'F' ||
      kind == b'L' ||
      kind == b'D' {
      names.push(dbf_text(b, at, name_end, text))
      fields.push((kind, start, len))
    }
    start += len
    at += 32
  }
  guard start <= record_len else {
    raise dbf_error("fields longer than a record")
  }
  let count = @cmp.minimum(records, (b.length() - header_len) / record_len)
  if count.to_double() * fields.length().to_double() > max_cells.to_double() {
    raise dbf_error("too many cells")
  }
  let unique = unique_names(names)
  {
    b,
    fields: fields.mapi((i, f) => {
      name: unique[i],
      kind: f.0,
      start: f.1,
      len: f.2,
    }),
    count,
    header_len,
    record_len,
  }
}

///|
/// Whether record `i` (one this table holds) is marked deleted.
fn Dbf::deleted(self : Dbf, i : Int32) -> Bool {
  self.b[self.header_len + i * self.record_len] == b'*'
}

///|
/// Record `i`'s values: C text trimmed; N and F numbers (null when blank or not
/// one); L true for `TtYy`, false for `FfNn`, null otherwise; D `YYYY-MM-DD` from
/// `YYYYMMDD` (null when blank, else the text as it is).
fn Dbf::props(
  self : Dbf,
  i : Int32,
  out : @geom.TableBuilder,
  text : (Int32, Int32) -> String,
  slow : (Int32, Int32) -> Double,
) -> Unit {
  let b = self.b
  let record = self.header_len + i * self.record_len
  for f in self.fields {
    let (s, e) = trimmed(b, record + f.start, record + f.start + f.len)
    let value : @geom.Prop = match f.kind {
      b'N' | b'F' => {
        let (v, after) = read_decimal(b, s, e, true, slow)
        if after == e && after > s {
          Num(v)
        } else {
          Null
        }
      }
      b'L' =>
        match (if e > s { b[s] } else { b' ' }) {
          b'T' | b't' | b'Y' | b'y' => Bool(true)
          b'F' | b'f' | b'N' | b'n' => Bool(false)
          _ => Null
        }
      b'D' => {
        let mut digits = e - s == 8
        for j in s..<e {
          digits = digits && b[j] >= b'0' && b[j] <= b'9'
        }
        if s == e {
          Null
        } else if digits {
          let sb = StringBuilder()
          for j in s..<e {
            if j == s + 4 || j == s + 6 {
              sb.write_char('-')
            }
            sb.write_char(b[j].to_int().unsafe_to_char())
          }
          Str(sb.to_string())
        } else {
          Str(dbf_text(b, s, e, text))
        }
      }
      _ => Str(dbf_text(b, s, e, text))
    }
    out.prop(f.name, value)
  }
}
