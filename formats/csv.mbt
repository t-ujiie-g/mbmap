// Ported from papaparse 5.7.0: MIT License, Copyright (c) 2015 Matthew Holt. See NOTICE.

///|
/// Most fields in a CSV row (AGENTS.md §8.2).
pub const MAX_CSV_COLUMNS : Int32 = 4096

///|
/// Longest CSV field in bytes.
const MAX_CSV_FIELD_BYTES : Int32 = 16 * 1024 * 1024

///|
/// How `read_csv` reads its input. `delimiter`: a byte, or -1 to guess it as
/// papaparse does; `header`: the first row names the columns (else they are named
/// "0", "1", ...); `dynamic_typing`: fields become numbers, booleans and nulls as
/// papaparse's `dynamicTyping` makes them (else they stay strings); `latitude` and
/// `longitude`, or `geometry` (WKT, EWKT or hexadecimal WKB), name the columns
/// the geometry comes from, found by name when None.
pub(all) struct CsvOptions {
  delimiter : Int32
  header : Bool
  dynamic_typing : Bool
  latitude : String?
  longitude : String?
  geometry : String?
}

///|
pub fn CsvOptions::new(
  delimiter~ : Int32 = -1,
  header~ : Bool = true,
  dynamic_typing~ : Bool = true,
  latitude? : String,
  longitude? : String,
  geometry? : String,
) -> CsvOptions {
  { delimiter, header, dynamic_typing, latitude, longitude, geometry, }
}

///|
/// Column names that hold latitudes, longitudes and geometries, in order of
/// preference, compared without ASCII case.
let latitude_names : FixedArray[String] = ["lat", "latitude", "y", "緯度"]

///|
let longitude_names : FixedArray[String] = [
  "lon", "lng", "long", "longitude", "x", "経度",
]

///|
let geometry_names : FixedArray[String] = [
  "wkt", "geometry", "the_geom", "geom",
]

///|
/// Delimiters tried when guessing, papaparse's.
let guessed_delimiters : FixedArray[Byte] = [
  b',', b'\t', b'|', b';', b'\x1e', b'\x1f',
]

///|
/// Reads CSV (RFC 4180, CRLF, LF or CR row ends) into a row per CSV row and member of its
/// geometry (npm/README.md `mbmap/data`); `slow_number` parses numbers past the fast path
/// from offsets into `bytes`; `srids` gets each row's SRID as `read_wkt`'s.
pub fn read_csv(
  bytes : BytesView,
  options : CsvOptions,
  slow_number~ : (Int32, Int32) -> Double = (s, e) => {
    @core.strconv_number(bytes[s:e])
  },
  srids? : Array[Int32],
) -> @geom.Table raise ReadError {
  csv_table(
    bytes,
    options,
    slow_number,
    @geom.MAX_TABLE_POINTS,
    @geom.MAX_TABLE_CELLS,
    srids,
  )
}

///|
/// A CSV reader over `b`; the fields of the row last read are `starts`, `ends`
/// (content ranges, quotes excluded) and `escaped` (holds `""`). Errors are sticky.
priv struct Csv {
  b : BytesView
  mut pos : Int32
  mut delimiter : Byte
  mut error : (Int32, String)?
  starts : Array[Int32]
  ends : Array[Int32]
  escaped : Array[Bool]
}

///|
fn Csv::fail(self : Csv, at : Int32, message : String) -> Unit {
  if self.error is None {
    self.error = Some((at, message))
  }
  self.pos = self.b.length()
}

///|
/// Takes a row end (CRLF, LF or CR) at the position; false if there is none.
fn Csv::row_end(self : Csv) -> Bool {
  let b = self.b
  if self.pos < b.length() && b[self.pos] == b'\r' {
    self.pos += if self.pos + 1 < b.length() && b[self.pos + 1] == b'\n' {
      2
    } else {
      1
    }
    true
  } else if self.pos < b.length() && b[self.pos] == b'\n' {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Csv::field(self : Csv, start : Int32, end : Int32, escaped : Bool) -> Unit {
  if end - start > MAX_CSV_FIELD_BYTES {
    self.fail(start, "a field longer than \{MAX_CSV_FIELD_BYTES} bytes")
  } else if self.starts.length() >= MAX_CSV_COLUMNS {
    self.fail(start, "more than \{MAX_CSV_COLUMNS} fields in a row")
  }
  self.starts.push(start)
  self.ends.push(end)
  self.escaped.push(escaped)
}

///|
/// Reads the next row's fields; false at the end of the input or on an error.
fn Csv::row(self : Csv) -> Bool {
  self.starts.clear()
  self.ends.clear()
  self.escaped.clear()
  let b = self.b
  let n = b.length()
  if self.pos >= n || self.error is Some(_) {
    return false
  }
  while self.error is None {
    if self.pos < n && b[self.pos] == b'"' {
      let open = self.pos
      let start = self.pos + 1
      let mut i = start
      let mut escaped = false
      let mut closed = -1
      while i < n {
        if b[i] == b'"' {
          if i + 1 < n && b[i + 1] == b'"' {
            escaped = true
            i += 2
            continue
          }
          closed = i
          break
        }
        i += 1
      }
      if closed < 0 {
        self.fail(open, "unterminated quoted field")
        return false
      }
      self.field(start, closed, escaped)
      // Spaces may stand between the closing quote and a delimiter or row end, as
      // papaparse allows.
      self.pos = closed + 1
      while self.pos < n && b[self.pos] == b' ' {
        self.pos += 1
      }
      if self.pos == closed + 1 && self.pos == n {
        return true
      }
      if self.pos < n && b[self.pos] == self.delimiter {
        self.pos += 1
        continue
      }
      if self.row_end() {
        return true
      }
      self.fail(closed, "unexpected text after a quoted field")
      return false
    }
    let start = self.pos
    while self.pos < n {
      let c = b[self.pos]
      if c == self.delimiter || c == b'\n' || c == b'\r' {
        break
      }
      self.pos += 1
    }
    self.field(start, self.pos, false)
    if self.pos < n && b[self.pos] == self.delimiter {
      self.pos += 1
      continue
    }
    self.row_end() |> ignore
    return true
  }
  false
}

///|
/// Whether the row last read is empty (one empty field), which is skipped.
fn Csv::empty_row(self : Csv) -> Bool {
  self.starts.length() == 1 && self.starts[0] == self.ends[0]
}

///|
/// The delimiter papaparse's `guessDelimiter` picks from the first ten rows at
/// `start`: the one whose rows' field counts vary least, more fields breaking
/// ties, if its rows average two or more; ',' if none does.
fn Csv::guess_delimiter(self : Csv, start : Int32) -> Byte {
  let mut best = b','
  let mut best_delta = -1
  let mut best_fields = 0.0
  for d in guessed_delimiters {
    self.delimiter = d
    self.pos = start
    self.error = None
    let mut rows = 0
    let mut empty = 0
    let mut fields = 0
    let mut delta = 0
    let mut previous = -1
    while rows < 10 && self.row() {
      rows += 1
      if self.empty_row() {
        empty += 1
        continue
      }
      let count = self.starts.length()
      fields += count
      if previous >= 0 {
        delta += (count - previous).abs()
      }
      previous = count
    }
    let average = if rows > empty {
      fields.to_double() / (rows - empty).to_double()
    } else {
      0.0
    }
    if average > 1.99 &&
      (
        best_delta < 0 ||
        delta < best_delta ||
        (delta == best_delta && average > best_fields)
      ) {
      best = d
      best_delta = delta
      best_fields = average
    }
  }
  self.error = None
  best
}

///|
/// Field `i` of the row last read as text, `""` unescaped and invalid UTF-8
/// replaced.
fn Csv::text(self : Csv, i : Int32) -> String {
  let (s, e) = (self.starts[i], self.ends[i])
  if !self.escaped[i] {
    return @core.utf8_lossy(self.b[s:e])
  }
  let out : Array[Byte] = Array(capacity=e - s)
  let mut j = s
  while j < e {
    out.push(self.b[j])
    j += if self.b[j] == b'"' { 2 } else { 1 }
  }
  @core.utf8_lossy(Bytes::from_array(out))
}

///|
/// Whether field `i` of the row last read is the ASCII `word`.
fn Csv::field_is(self : Csv, i : Int32, word : String) -> Bool {
  let (s, e) = (self.starts[i], self.ends[i])
  if e - s != word.length() || self.escaped[i] {
    return false
  }
  for k in 0..<word.length() {
    if self.b[s + k].to_int() != word.code_unit_at(k).to_int() {
      return false
    }
  }
  true
}
