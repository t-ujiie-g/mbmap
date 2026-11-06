// Ported from @xmldom/xmldom 0.9.12: MIT License, Copyright 2019 - present Christopher J. Brody
// and other contributors, Copyright 2012 - 2017 @jindw and other contributors. See NOTICE.

///|
/// Deepest element nesting a document may have (AGENTS.md §8.2).
pub const MAX_XML_DEPTH : Int32 = 256

///|
/// Most attributes one element may have.
pub const MAX_XML_ATTRIBUTES : Int32 = 1024

///|
/// Most elements, text and CDATA nodes one document may have.
const MAX_XML_NODES : Int32 = 4_000_000

///|
/// `Malformed`: not XML as xmldom reads it; `Limit`: a document past one of the
/// readers' limits.
pub(all) suberror XmlError {
  Malformed(pos~ : Int32, String)
  Limit(String)
} derive(Debug)

///|
/// A one-line description, e.g. `malformed XML at 12: unclosed tag`.
pub fn XmlError::message(self : XmlError) -> String {
  match self {
    Malformed(pos~, m) => "malformed XML at \{pos}: \{m}"
    Limit(m) => "too large: " + m
  }
}

///|
/// Reads UTF-8 `input` as xmldom's `DOMParser().parseFromString(text, "text/xml")` does: raises
/// where it throws a `ParseError`, goes on where it only reports one (a `<` in text, a missing `;`,
/// an unquoted attribute); a BOM is dropped and line ends normalized as `normalizeLineEndings`.
pub fn Document::parse(input : Bytes) -> Document raise XmlError {
  let p = Parser::new(normalize(input), MAX_XML_NODES)
  p.run()
  if p.fatal is None && p.state == before_root {
    p.fail(p.n, "missing root element")
  }
  if p.fatal is Some((pos, m)) {
    raise Malformed(pos~, m)
  }
  p.doc.ends[0] = p.doc.names.length()
  p.doc
}

///|
/// `input` without a leading BOM, `\r\n`, `\r`, U+0085, U+2028 and U+2029 made `\n`.
fn normalize(input : Bytes) -> Bytes {
  let n = input.length()
  let out = Array(capacity=n)
  let mut i = if n >= 3 &&
    input[0] == b'\xEF' &&
    input[1] == b'\xBB' &&
    input[2] == b'\xBF' {
    3
  } else {
    0
  }
  while i < n {
    let c = input[i]
    if c == b'\r' {
      out.push(b'\n')
      i += if i + 1 < n && input[i + 1] == b'\n' {
        2
      } else if i + 2 < n && input[i + 1] == b'\xC2' && input[i + 2] == b'\x85' {
        3
      } else {
        1
      }
    } else if c == b'\xC2' && i + 1 < n && input[i + 1] == b'\x85' {
      out.push(b'\n')
      i += 2
    } else if c == b'\xE2' &&
      i + 2 < n &&
      input[i + 1] == b'\x80' &&
      (input[i + 2] == b'\xA8' || input[i + 2] == b'\xA9') {
      out.push(b'\n')
      i += 3
    } else {
      out.push(c)
      i += 1
    }
  }
  Bytes::from_array(out)
}

///|
let before_root : Int32 = 0

///|
let in_root : Int32 = 1

///|
/// The root has ended: xmldom's current node is the document.
let after_root : Int32 = 2

///|
/// An end tag past the root's has popped the document too (xmldom then has no
/// current node, and start tags fail and are read as text).
let past_document : Int32 = 3

///|
/// What a tag's parse asks of the loop: `recover` reads its `<` as text, as xmldom
/// does after an `Error`; `stop` ends the document there.
let recover : Int32 = -1

///|
let stop : Int32 = -2

///|
/// The sax reader's state over normalized source `b`; `fatal` holds the first error.
/// `bind_*`: namespace bindings, `heads` each prefix's innermost; `attr_*`: the tag
/// being read; `next_gt`: the first `>` from where `end_tag` last looked (`n` if none).
priv struct Parser {
  b : Bytes
  n : Int32
  doc : Document
  mut fatal : (Int32, String)?
  mut state : Int32
  mut root_name : String
  mut doctype : Bool
  open : Array[Int32]
  bound : Array[Int32]
  prefixes : Names
  heads : Array[Int32]
  bind_uris : Array[Int32]
  bind_prev : Array[Int32]
  bind_prefixes : Array[Int32]
  attr_names : Array[String]
  attr_values : Array[String]
  attr_starts : Array[Int32]
  mut attr_tag : Int32
  attr_seen : Map[String, Int32]
  mut next_gt : Int32
  max_nodes : Int32
}

///|
fn Parser::new(b : Bytes, max_nodes : Int32) -> Parser {
  let p = {
    b,
    n: b.length(),
    doc: Document::new(b),
    fatal: None,
    state: before_root,
    root_name: "",
    doctype: false,
    open: [],
    bound: [],
    prefixes: Names::new(),
    heads: [],
    bind_uris: [],
    bind_prev: [],
    bind_prefixes: [],
    attr_names: [],
    attr_values: [],
    attr_starts: [],
    attr_tag: 0,
    attr_seen: Map([]),
    next_gt: -1,
    max_nodes,
  }
  p.bind("", -1)
  p.bind("xml", p.doc.uri_id(xml_namespace))
  p
}

///|
fn Parser::fail(self : Parser, pos : Int32, message : String) -> Unit {
  if self.fatal is None {
    self.fatal = Some((pos, message))
  }
}

///|
fn Parser::index_of(self : Parser, c : Byte, from : Int32) -> Int32 {
  for i in from..<self.n {
    if self.b[i] == c {
      return i
    }
  }
  -1
}

///|
/// `index_of(b'>', from)` for `from`s that only grow, each byte read once: recovering
/// from an end tag past the document would otherwise scan to one far `>` per tag.
fn Parser::gt_from(self : Parser, from : Int32) -> Int32 {
  if self.next_gt < from && self.next_gt < self.n {
    let gt = self.index_of(b'>', from)
    self.next_gt = if gt < 0 { self.n } else { gt }
  }
  if self.next_gt < self.n {
    self.next_gt
  } else {
    -1
  }
}

///|
fn Parser::starts_with(self : Parser, at : Int32, s : Bytes) -> Bool {
  guard at >= 0 && at + s.length() <= self.n else { return false }
  for i in 0..<s.length() {
    if self.b[at + i] != s[i] {
      return false
    }
  }
  true
}

///|
fn Parser::text(self : Parser, start : Int32, end : Int32) -> String {
  @core.utf8_lossy(self.b[start:end])
}

///|
/// Adds a node of `name` under the innermost open element.
fn Parser::node(
  self : Parser,
  name : Int32,
  start : Int32,
  stop : Int32,
) -> Int32 {
  let d = self.doc
  let i = d.names.length()
  if i >= self.max_nodes {
    self.fail(start, "too many nodes")
  }
  d.names.push(name)
  d.ends.push(i + 1)
  d.parents.push(
    match self.open.last() {
      Some(p) => p
      None => 0
    },
  )
  d.starts.push(start)
  d.stops.push(stop)
  d.nss.push(-1)
  i
}

///|
/// Text from `start` to `end` (references replaced when read), kept only inside
/// the root: xmldom keeps nothing but white space outside it, which no query reads.
fn Parser::append_text(self : Parser, start : Int32, end : Int32) -> Unit {
  if end > start && self.state == in_root {
    self.node(text_name, start, end) |> ignore
  }
}

///|
fn Parser::run(self : Parser) -> Unit {
  let mut start = 0
  while self.fatal is None {
    let tag = self.index_of(b'<', start)
    if tag < 0 {
      if self.open.length() > 0 {
        self.fail(self.n, "unclosed xml tag(s)")
      }
      return
    }
    self.append_text(start, tag)
    start = tag
    let next = if tag + 1 < self.n { self.b[tag + 1] } else { b'\x00' }
    let end = match next {
      b'/' => self.end_tag(tag)
      b'?' => self.instruction(tag)
      b'!' => self.markup(tag)
      _ => self.start_tag(tag)
    }
    if self.fatal is Some(_) || end == stop {
      return
    }
    if end > start {
      start = end
    } else {
      self.append_text(start, tag + 1)
      start = tag + 1
    }
  }
}

///|
/// The longest `QName` at `i` (its end; `i` if none).
fn Parser::qname_end(self : Parser, i : Int32, end : Int32) -> Int32 {
  let first = name_end(self.b, i, end, colons=false)
  if first > i && first < end && self.b[first] == b':' {
    let second = name_end(self.b, first + 1, end, colons=false)
    if second > first + 1 {
      return second
    }
  }
  first
}

///|
fn Parser::end_tag(self : Parser, tag : Int32) -> Int32 {
  let gt = self.gt_from(tag + 2)
  let raw_end = if gt > 0 { gt } else { self.n }
  if raw_end == tag + 2 {
    self.fail(tag, "end tag name missing")
    return stop
  }
  let qend = if gt > 0 { self.qname_end(tag + 2, raw_end) } else { tag + 2 }
  // `^QName S*$`, or a line break among the spaces after the name (xmldom recovers).
  let mut j = qend
  let mut line_break = false
  while j < raw_end && is_space(self.b[j]) {
    line_break = line_break || self.b[j] == b'\n'
    j += 1
  }
  if qend == tag + 2 || (j < raw_end && !line_break) {
    self.fail(tag, "end tag name contains invalid characters")
    return stop
  }
  if self.state == before_root {
    return stop
  }
  if self.state == past_document {
    return recover
  }
  let name = self.text(tag + 2, qend)
  let current = match self.open.last() {
    Some(e) => self.doc.name(e)
    None => self.root_name
  }
  if current != name {
    self.fail(
      tag,
      "opening and ending tag mismatch: " + current + " != " + name,
    )
    return stop
  }
  if self.open.length() > 0 {
    self.close()
  } else {
    self.state = past_document
  }
  gt + 1
}

///|
/// Ends the innermost open element.
fn Parser::close(self : Parser) -> Unit {
  guard self.open.pop() is Some(e) else { return }
  self.doc.ends[e] = self.doc.names.length()
  if self.bound.pop() is Some(count) {
    self.unbind(count)
  }
  if self.open.length() == 0 {
    self.state = after_root
  }
}

///|
/// `<?target data?>`, as xmldom's `PI` production; an XML declaration only at the start.
fn Parser::instruction(self : Parser, start : Int32) -> Int32 {
  let end = self.pi_end(start)
  if end < 0 {
    self.fail(start, "invalid processing instruction")
    return stop
  }
  let target_end = name_end(self.b, start + 2, self.n)
  if target_end - start - 2 == 3 && self.lower_is(start + 2, b"xml") {
    // xmldom also checks the declaration's version, encoding and standalone parts.
    if start > 0 {
      self.fail(start, "an XML declaration is only allowed at the start")
      return stop
    }
  }
  end
}

///|
/// Where the processing instruction at `start` ends, or -1.
fn Parser::pi_end(self : Parser, start : Int32) -> Int32 {
  let target_end = name_end(self.b, start + 2, self.n)
  if target_end == start + 2 {
    return -1
  }
  let mut j = target_end
  if self.starts_with(j, b"?>") {
    return j + 2
  }
  if j >= self.n || !is_space(self.b[j]) {
    return -1
  }
  while j < self.n && is_space(self.b[j]) {
    j += 1
  }
  while j < self.n {
    if self.starts_with(j, b"?>") {
      return j + 2
    }
    if not_char(self.b, j, self.n) {
      return -1
    }
    j += 1
  }
  -1
}

///|
fn Parser::lower_is(self : Parser, at : Int32, s : Bytes) -> Bool {
  guard at + s.length() <= self.n else { return false }
  for i in 0..<s.length() {
    let c = self.b[at + i]
    let lower = if c >= b'A' && c <= b'Z' { c + b'\x20' } else { c }
    if lower != s[i] {
      return false
    }
  }
  true
}

///|
/// `<!--`, `<![CDATA[` or `<!DOCTYPE`.
fn Parser::markup(self : Parser, start : Int32) -> Int32 {
  let c = if start + 2 < self.n { self.b[start + 2] } else { b'\x00' }
  if c == b'-' {
    let end = self.comment_end(start)
    if end < 0 {
      self.fail(start, "comment is not well-formed")
      return stop
    }
    end
  } else if c == b'[' {
    let end = self.cdata_end(start)
    if end < 0 {
      self.fail(start, "invalid CDATA")
      return stop
    }
    if self.state == before_root || self.state == past_document {
      self.fail(start, "CDATA outside of element")
      return stop
    }
    if self.state == in_root {
      self.node(cdata_name, start + 9, end - 3) |> ignore
    }
    end
  } else if c == b'D' {
    self.doctype(start)
  } else {
    self.fail(start, "not well-formed XML starting with <!")
    stop
  }
}

///|
/// Where the comment at `start` ends, or -1: `<!--`, no `--` inside, `-->`.
fn Parser::comment_end(self : Parser, start : Int32) -> Int32 {
  guard self.starts_with(start, b"<!--") else { return -1 }
  let mut j = start + 4
  while j < self.n {
    if self.starts_with(j, b"-->") {
      return j + 3
    }
    if self.b[j] == b'-' {
      j += 1
      if j >= self.n || self.b[j] == b'-' {
        return -1
      }
    }
    if not_char(self.b, j, self.n) {
      return -1
    }
    j += 1
  }
  -1
}

///|
/// Where the CDATA section at `start` ends, or -1.
fn Parser::cdata_end(self : Parser, start : Int32) -> Int32 {
  guard self.starts_with(start, b"<![CDATA[") else { return -1 }
  let mut j = start + 9
  while j < self.n {
    if self.starts_with(j, b"]]>") {
      return j + 3
    }
    if not_char(self.b, j, self.n) {
      return -1
    }
    j += 1
  }
  -1
}

///|
/// How many blanks follow `i` (moved past them), -1 if they reach the end.
fn Parser::blanks(self : Parser, i : Ref[Int32]) -> Int32 {
  let from = i.val
  while i.val < self.n {
    if !is_space(self.b[i.val]) {
      return i.val - from
    }
    i.val += 1
  }
  -1
}

///|
/// `<!DOCTYPE Name ...>`: before the root and once. Its external id and internal
/// subset are skipped (quoted strings and comments in it included), not checked;
/// entities declared there stay unexpanded, as in xmldom.
fn Parser::doctype(self : Parser, start : Int32) -> Int32 {
  if self.state != before_root ||
    self.doctype ||
    !self.starts_with(start, b"<!DOCTYPE") {
    self.fail(start, "misplaced or malformed doctype")
    return stop
  }
  let i = Ref(start + 9)
  let name = if self.blanks(i) > 0 {
    name_end(self.b, i.val, self.n)
  } else {
    -1
  }
  if name <= i.val {
    self.fail(i.val, "doctype name missing")
    return stop
  }
  let mut j = name
  let mut subset = false
  while j < self.n {
    let c = self.b[j]
    if c == b'"' || c == b'\'' {
      j = self.index_of(c, j + 1)
      if j < 0 {
        break
      }
    } else if subset && self.starts_with(j, b"<!--") {
      j = self.comment_end(j) - 1
      if j < 0 {
        break
      }
    } else if c == b'[' {
      subset = true
    } else if c == b']' {
      subset = false
    } else if c == b'>' && !subset {
      self.doctype = true
      return j + 1
    }
    j += 1
  }
  self.fail(start, "doctype not terminated")
  stop
}
