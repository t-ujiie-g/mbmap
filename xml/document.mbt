///|
/// What a node is. The document itself is node 0; comments, processing
/// instructions and the doctype are not kept.
pub(all) enum NodeKind {
  DocumentNode
  Element
  Text
  CData
} derive(Debug, Eq)

///|
let text_name : Int32 = -1

///|
let cdata_name : Int32 = -2

///|
let document_name : Int32 = -3

///|
/// `XMLNS` and `XML`: the namespaces of `xmlns` declarations and of the `xml` prefix.
pub let xmlns_namespace : String = "http://www.w3.org/2000/xmlns/"

///|
pub let xml_namespace : String = "http://www.w3.org/XML/1998/namespace"

///|
/// A parsed document: nodes numbered in document order, so an element's
/// descendants are the nodes after it up to its `end`. Per node, `names` holds
/// the element's name id (or `text_name`, `cdata_name`, `document_name`);
/// `starts`/`stops` its text's byte range, or an element's attribute range;
/// `nss` an element's namespace id (-1: none).
pub struct Document {
  priv src : Bytes
  priv names : Array[Int32]
  priv ends : Array[Int32]
  priv parents : Array[Int32]
  priv starts : Array[Int32]
  priv stops : Array[Int32]
  priv nss : Array[Int32]
  priv attr_names : Array[String]
  priv attr_values : Array[String]
  priv attr_nss : Array[Int32]
  priv qnames : Names
  priv locals : Array[String]
  priv uris : Names
}

///|
fn Document::new(src : Bytes) -> Document {
  {
    src,
    names: [document_name],
    ends: [0],
    parents: [-1],
    starts: [0],
    stops: [0],
    nss: [-1],
    attr_names: [],
    attr_values: [],
    attr_nss: [],
    qnames: Names::new(),
    locals: [],
    uris: Names::new(),
  }
}

///|
fn Document::name_id(self : Document, qname : String) -> Int32 {
  let id = self.qnames.add(qname)
  if id == self.locals.length() {
    self.locals.push(local_of(qname))
  }
  id
}

///|
fn Document::uri_id(self : Document, u : String) -> Int32 {
  if u == "" {
    -1
  } else {
    self.uris.add(u)
  }
}

///|
/// How many nodes the document has, itself included.
pub fn Document::length(self : Document) -> Int32 {
  self.names.length()
}

///|
pub fn Document::kind(self : Document, node : Int32) -> NodeKind {
  let n = self.names[node]
  if n >= 0 {
    Element
  } else if n == text_name {
    Text
  } else if n == cdata_name {
    CData
  } else {
    DocumentNode
  }
}

///|
/// An element's qualified name as written (`gx:Track`); `""` for other nodes.
pub fn Document::name(self : Document, node : Int32) -> String {
  let n = self.names[node]
  if n >= 0 {
    self.qnames.at(n)
  } else {
    ""
  }
}

///|
/// An element's lname name (after its prefix); `""` for other nodes.
pub fn Document::local_name(self : Document, node : Int32) -> String {
  let n = self.names[node]
  if n >= 0 {
    self.locals[n]
  } else {
    ""
  }
}

///|
/// An element's namespace, None without one.
pub fn Document::namespace_uri(self : Document, node : Int32) -> String? {
  let u = self.nss[node]
  if u >= 0 {
    Some(self.uris.at(u))
  } else {
    None
  }
}

///|
/// The node's parent; None for the document.
pub fn Document::parent(self : Document, node : Int32) -> Int32? {
  let p = self.parents[node]
  if p >= 0 {
    Some(p)
  } else {
    None
  }
}

///|
/// The node's children in order.
pub fn Document::children(self : Document, node : Int32) -> Array[Int32] {
  let out = []
  let mut i = node + 1
  while i < self.ends[node] {
    out.push(i)
    i = self.ends[i]
  }
  out
}

///|
/// The descendant elements named `qname` in document order
/// (`getElementsByTagName`); `"*"` takes every element.
pub fn Document::elements(
  self : Document,
  node : Int32,
  qname : String,
) -> Array[Int32] {
  let out = []
  let all = qname == "*"
  let id = self.qnames.find(qname)
  if id < 0 && !all {
    return out
  }
  for i in (node + 1)..<self.ends[node] {
    let n = self.names[i]
    if (n == id && n >= 0) || (all && n >= 0) {
      out.push(i)
    }
  }
  out
}

///|
/// The first descendant element named `qname`, if any.
pub fn Document::first(self : Document, node : Int32, qname : String) -> Int32? {
  let id = self.qnames.find(qname)
  guard id >= 0 else { return None }
  for i in (node + 1)..<self.ends[node] {
    if self.names[i] == id {
      return Some(i)
    }
  }
  None
}

///|
/// The descendant elements in namespace `uri` with lname name `lname`, None
/// standing for any (`getElementsByTagNameNS` with `"*"`).
pub fn Document::elements_ns(
  self : Document,
  node : Int32,
  uri~ : String?,
  lname~ : String?,
) -> Array[Int32] {
  let out = []
  let want = match uri {
    Some(u) => {
      let id = self.uris.find(u)
      if id < 0 {
        return out
      }
      id
    }
    None => -2
  }
  for i in (node + 1)..<self.ends[node] {
    let n = self.names[i]
    if n >= 0 &&
      (want == -2 || self.nss[i] == want) &&
      (match lname {
        Some(l) => self.locals[n] == l
        None => true
      }) {
      out.push(i)
    }
  }
  out
}

///|
/// The value of an element's attribute named `qname`, None if it has none.
pub fn Document::attribute(
  self : Document,
  node : Int32,
  qname : String,
) -> String? {
  guard self.names[node] >= 0 else { return None }
  for a in self.starts[node]..<self.stops[node] {
    if self.attr_names[a] == qname {
      return Some(self.attr_values[a])
    }
  }
  None
}

///|
/// How many attributes an element has.
pub fn Document::attribute_count(self : Document, node : Int32) -> Int32 {
  if self.names[node] >= 0 {
    self.stops[node] - self.starts[node]
  } else {
    0
  }
}

///|
/// The qualified name of an element's attribute `i` (in order).
pub fn Document::attribute_name(
  self : Document,
  node : Int32,
  i : Int32,
) -> String {
  self.attr_names[self.starts[node] + i]
}

///|
/// The value of an element's attribute `i`.
pub fn Document::attribute_value(
  self : Document,
  node : Int32,
  i : Int32,
) -> String {
  self.attr_values[self.starts[node] + i]
}

///|
/// The node's text (`textContent`): a text node's own, or the text of every
/// text and CDATA node under an element or the document, in order.
pub fn Document::text(self : Document, node : Int32) -> String {
  match self.kind(node) {
    Text => entities(self.decode(node))
    CData => self.decode(node)
    _ => {
      let out = StringBuilder()
      for i in (node + 1)..<self.ends[node] {
        let n = self.names[i]
        if n == text_name {
          out.write_string(entities(self.decode(i)))
        } else if n == cdata_name {
          out.write_string(self.decode(i))
        }
      }
      out.to_string()
    }
  }
}

///|
fn Document::decode(self : Document, node : Int32) -> String {
  @core.utf8_lossy(self.src[self.starts[node]:self.stops[node]])
}
