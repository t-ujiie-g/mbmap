// Ported from @xmldom/xmldom 0.9.12: MIT License, Copyright 2019 - present Christopher J. Brody
// and other contributors, Copyright 2012 - 2017 @jindw and other contributors. See NOTICE.

///|
/// A state of xmldom's `parseElementStartPart`: reading the tag's name.
let s_tag : Int32 = 0

///|
/// Reading an attribute's name.
let s_attr : Int32 = 1

///|
/// Spaces after an attribute's name.
let s_attr_space : Int32 = 2

///|
/// After `=`.
let s_eq : Int32 = 3

///|
/// Reading an unquoted value.
let s_noquote : Int32 = 4

///|
/// After a quoted value.
let s_attr_end : Int32 = 5

///|
/// Spaces between attributes.
let s_tag_space : Int32 = 6

///|
/// After `/`.
let s_tag_close : Int32 = 7

///|
/// A start tag as `parseElementStartPart` and `appendElement` read it; the end
/// to resume from, `recover` or `stop`.
fn Parser::start_tag(self : Parser, tag : Int32) -> Int32 {
  if self.state == past_document {
    return recover
  }
  self.attr_names.clear()
  self.attr_values.clear()
  self.attr_starts.clear()
  self.attr_tag = tag
  let b = self.b
  let n = self.n
  let mut p = tag + 1
  let mut start = p
  let mut s = s_tag
  let mut name = (0, 0)
  let mut attr = (0, 0)
  let mut closed = false
  let mut end = -1
  while end < 0 {
    if p >= n {
      if s == s_tag {
        name = (start, p)
        if !is_qname(self.text(start, p)) {
          return recover
        }
      }
      end = p
      break
    }
    let c = b[p]
    if s == s_tag && c == b'<' {
      return recover
    }
    let mut width = 1
    if c == b'=' {
      if s == s_attr {
        attr = (start, p)
        s = s_eq
      } else if s == s_attr_space {
        s = s_eq
      } else {
        return recover
      }
    } else if c == b'"' || c == b'\'' {
      if s == s_eq || s == s_attr {
        if s == s_attr {
          attr = (start, p)
        }
        start = p + 1
        p = self.index_of(c, start)
        if p < 0 {
          return recover
        }
        if !self.add_attr(attr, (start, p)) {
          return recover
        }
        s = s_attr_end
      } else if s == s_noquote {
        if !self.add_attr(attr, (start, p)) {
          return recover
        }
        start = p + 1
        s = s_attr_end
      } else {
        return recover
      }
    } else if c == b'/' {
      if s == s_tag {
        name = (start, p)
        if !is_qname(self.text(start, p)) {
          return recover
        }
        s = s_tag_close
        closed = true
      } else if s == s_attr_end || s == s_tag_space || s == s_tag_close {
        s = s_tag_close
        closed = true
      } else if s == s_attr_space {
        closed = true
      } else if s != s_noquote && s != s_attr {
        return recover
      }
    } else if c == b'>' {
      if s == s_tag {
        name = (start, p)
        if !is_qname(self.text(start, p)) {
          return recover
        }
      } else if s == s_noquote || s == s_attr {
        let mut v = (start, p)
        if p > start && b[p - 1] == b'/' {
          closed = true
          v = (start, p - 1)
        }
        let ok = if s == s_noquote {
          self.add_attr(attr, v)
        } else {
          self.add_attr(v, v)
        }
        if !ok {
          return recover
        }
      } else if s == s_attr_space {
        if !self.add_attr(attr, attr) {
          return recover
        }
      } else if s == s_eq {
        self.fail(p, "AttValue: ' or \" expected")
        return stop
      }
      end = p
      break
    } else {
      let space = c <= b' ' ||
        (c == b'\xC2' && p + 1 < n && b[p + 1] == b'\x80')
      if space {
        if c == b'\xC2' {
          width = 2
        }
        if s == s_tag {
          name = (start, p)
          if !is_qname(self.text(start, p)) {
            return recover
          }
          s = s_tag_space
        } else if s == s_attr {
          attr = (start, p)
          s = s_attr_space
        } else if s == s_noquote {
          if !self.add_attr(attr, (start, p)) {
            return recover
          }
          s = s_tag_space
        } else if s == s_attr_end {
          s = s_tag_space
        }
      } else if s == s_attr_space {
        if !self.add_attr(attr, attr) {
          return recover
        }
        start = p
        s = s_attr
      } else if s == s_attr_end || s == s_tag_space {
        s = s_attr
        start = p
      } else if s == s_eq {
        s = s_noquote
        start = p
      } else if s == s_tag_close {
        return recover
      }
    }
    if self.fatal is Some(_) {
      return stop
    }
    p += width
  }
  if self.fatal is Some(_) {
    return stop
  }
  self.append_element(tag, self.text(name.0, name.1), closed)
  end + 1
}

///|
/// xmldom's `addAttribute`: true if added; a repeated name or a `<` in the value
/// is fatal, an invalid name recovers (false).
fn Parser::add_attr(
  self : Parser,
  qname : (Int32, Int32),
  value : (Int32, Int32),
) -> Bool {
  let name = self.text(qname.0, qname.1)
  if self.attr_seen.get(name) == Some(self.attr_tag) {
    self.fail(qname.0, "attribute redefined")
    return true
  }
  for i in value.0..<value.1 {
    if self.b[i] == b'<' {
      self.fail(value.0, "unescaped < in an attribute value")
      return true
    }
  }
  if !is_qname(name) {
    return false
  }
  if self.attr_names.length() >= MAX_XML_ATTRIBUTES {
    self.fail(qname.0, "too many attributes")
    return true
  }
  // `[\t\n\r]` become spaces before references are replaced.
  let raw = self.text(value.0, value.1)
  let out = StringBuilder()
  for i in 0..<raw.length() {
    let c = raw[i]
    out.write_char(
      if c == '\t' || c == '\n' || c == '\r' {
        ' '
      } else {
        c.to_int().unsafe_to_char()
      },
    )
  }
  self.attr_seen[name] = self.attr_tag
  self.attr_names.push(name)
  self.attr_values.push(entities(out.to_string()))
  self.attr_starts.push(qname.0)
  true
}

///|
/// Where the colon of a qualified name is, -1 without one.
fn colon(q : String) -> Int32 {
  for i in 0..<q.length() {
    if q[i] == ':' {
      return i
    }
  }
  -1
}

///|
/// The prefix of a qualified name, `""` without one.
fn prefix_of(q : String) -> String {
  let c = colon(q)
  if c < 0 {
    ""
  } else {
    units(q, 0, c)
  }
}

///|
fn local_of(q : String) -> String {
  units(q, colon(q) + 1, q.length())
}

///|
/// The id of `prefix` in the binding chains, made if new.
fn Parser::prefix_id(self : Parser, prefix : String) -> Int32 {
  let id = self.prefixes.add(prefix)
  if id == self.heads.length() {
    self.heads.push(-1)
  }
  id
}

///|
/// Binds `prefix` to namespace id `uri` until the bindings are cut back.
fn Parser::bind(self : Parser, prefix : String, uri : Int32) -> Unit {
  let p = self.prefix_id(prefix)
  self.bind_uris.push(uri)
  self.bind_prev.push(self.heads[p])
  self.bind_prefixes.push(p)
  self.heads[p] = self.bind_uris.length() - 1
}

///|
/// Undoes the bindings made after the first `count`.
fn Parser::unbind(self : Parser, count : Int32) -> Unit {
  while self.bind_uris.length() > count {
    let i = self.bind_uris.length() - 1
    self.heads[self.bind_prefixes[i]] = self.bind_prev[i]
    self.bind_uris.truncate(i)
    self.bind_prev.truncate(i)
    self.bind_prefixes.truncate(i)
  }
}

///|
/// The namespace `prefix` is bound to (-1: none).
fn Parser::lookup(self : Parser, prefix : String) -> Int32 {
  let p = self.prefixes.find(prefix)
  let h = if p >= 0 { self.heads[p] } else { -1 }
  if h >= 0 {
    self.bind_uris[h]
  } else {
    -1
  }
}

///|
/// DOM's `validateAndExtract` for an element or attribute in namespace `ns`.
fn Parser::valid_ns(self : Parser, qname : String, ns : Int32) -> Bool {
  let prefix = prefix_of(qname)
  let uri = if ns >= 0 { self.doc.uris.at(ns) } else { "" }
  if colon(qname) >= 0 && ns < 0 {
    return false
  }
  if prefix == "xml" && uri != xml_namespace {
    return false
  }
  (prefix == "xmlns" || qname == "xmlns") == (uri == xmlns_namespace)
}

///|
/// xmldom's `appendElement` and the DOM handler's `startElement`: namespace
/// declarations bound, the element and its attributes checked as
/// `createElementNS` / `createAttributeNS` check them, and added.
fn Parser::append_element(
  self : Parser,
  tag : Int32,
  qname : String,
  closed : Bool,
) -> Unit {
  let d = self.doc
  let count = self.attr_names.length()
  let attr_ns = Array::make(count, -1)
  let bound = self.bind_uris.length()
  let xmlns = d.uri_id(xmlns_namespace)
  for i = count - 1; i >= 0; i = i - 1 {
    let name = self.attr_names[i]
    let prefix = prefix_of(name)
    if prefix == "xmlns" || name == "xmlns" {
      self.bind(
        if prefix == "xmlns" {
          local_of(name)
        } else {
          ""
        },
        d.uri_id(self.attr_values[i]),
      )
      attr_ns[i] = xmlns
    }
  }
  for i in 0..<count {
    let prefix = prefix_of(self.attr_names[i])
    if prefix != "" && prefix != "xmlns" {
      attr_ns[i] = self.lookup(prefix)
    }
  }
  let ns = self.lookup(prefix_of(qname))
  if !self.valid_ns(qname, ns) {
    self.fail(tag, "namespace error in element " + qname)
    return
  }
  if self.state == after_root {
    self.fail(tag, "only one root element is allowed")
    return
  }
  if self.open.length() >= MAX_XML_DEPTH {
    self.fail(tag, "elements nested too deep")
    return
  }
  let e = self.node(d.name_id(qname), d.attr_names.length(), 0)
  d.nss[e] = ns
  for i in 0..<count {
    let name = self.attr_names[i]
    if !self.valid_ns(name, attr_ns[i]) {
      self.fail(self.attr_starts[i], "namespace error in attribute " + name)
      return
    }
    // One with the same namespace and local name is replaced (`setNamedItem`).
    let mut at = d.attr_names.length()
    if attr_ns[i] >= 0 {
      let key = "\{attr_ns[i]}:" + local_of(name)
      match self.attr_seen.get(key) {
        Some(a) if a >= d.starts[e] => at = a
        _ => self.attr_seen[key] = at
      }
    }
    if at == d.attr_names.length() {
      d.attr_names.push(name)
      d.attr_values.push(self.attr_values[i])
      d.attr_nss.push(attr_ns[i])
    } else {
      d.attr_names[at] = name
      d.attr_values[at] = self.attr_values[i]
    }
  }
  d.stops[e] = d.attr_names.length()
  if self.state == before_root {
    self.state = in_root
    self.root_name = qname
  }
  if closed {
    self.unbind(bound)
    if self.open.length() == 0 {
      self.state = after_root
    }
  } else {
    self.open.push(e)
    self.bound.push(bound)
  }
}
