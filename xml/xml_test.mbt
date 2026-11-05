///|
fn parse(s : String) -> @xml.Document raise @xml.XmlError {
  @xml.Document::parse(@utf8.encode(s))
}

///|
fn fails(s : String) -> Bool {
  (parse(s) catch { _ => return true }) |> ignore
  false
}

///|
/// The root element (the document's first element child).
fn root(d : @xml.Document) -> Int32 {
  d.elements(0, "*")[0]
}

///|
fn attrs(d : @xml.Document, e : Int32) -> Array[(String, String)] {
  Array::makei(d.attribute_count(e), i => {
    (d.attribute_name(e, i), d.attribute_value(e, i))
  })
}

///|
test "elements, attributes and text in document order" {
  let d = parse(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<a x='1' y=\"2\"><b>one</b><c/><b>two<![CDATA[ <three> ]]></b></a>",
  )
  let a = root(d)
  assert_eq(d.name(a), "a")
  assert_eq(d.attribute(a, "x"), Some("1"))
  assert_eq(d.attribute(a, "z"), None)
  assert_eq(attrs(d, a), [("x", "1"), ("y", "2")])
  let bs = d.elements(a, "b")
  assert_eq(bs.length(), 2)
  assert_eq(d.text(bs[1]), "two <three> ")
  assert_eq(d.text(a), "onetwo <three> ")
  assert_eq(d.first(a, "c").map(c => d.name(c)), Some("c"))
  assert_eq(d.first(a, "nothing"), None)
  assert_eq(d.children(a).map(c => d.name(c)), ["b", "c", "b"])
  assert_eq(d.children(bs[1]).map(c => d.kind(c)), [Text, CData])
  assert_eq(d.parent(bs[0]), Some(a))
  assert_eq(d.parent(0), None)
  assert_eq(d.kind(0), DocumentNode)
  assert_eq(d.length(), 8)
}

///|
test "entities: the five, character references, the rest kept as written" {
  let d = parse(
    "<a t=\"&lt;&#60;&#x3C;\">&amp;&apos;&gt;&quot; &#65;&#x1F600; &lol; &amp &#12a; &#X41; &</a>",
  )
  let a = root(d)
  assert_eq(d.attribute(a, "t"), Some("<<<"))
  assert_eq(d.text(a), "&'>\" A\u{1F600} &lol; &amp &#12a; &#X41; &")
  // xmldom's fromCharCode arithmetic above U+10FFFF.
  let big = parse("<a>&#1114112;</a>")
  assert_eq(big.text(root(big)).length(), 2)
}

///|
test "declared entities are never expanded" {
  let d = parse(
    "<!DOCTYPE a [<!ENTITY x \"&y;&y;\"><!ENTITY y \"zz\"><!ELEMENT a (#PCDATA)><!ATTLIST a b CDATA \"x>y\"><!-- c --><?p d?>]><a>&x;</a>",
  )
  assert_eq(d.text(root(d)), "&x;")
}

///|
test "namespaces as xmldom resolves them, prefixes kept in names" {
  let d = parse(
    "<k xmlns=\"urn:k\" xmlns:gx=\"urn:gx\"><gx:Track><gx:coord>1 2</gx:coord></gx:Track><p xmlns:gx=\"urn:other\"><gx:coord/></p><coord/></k>",
  )
  let k = root(d)
  assert_eq(d.namespace_uri(k), Some("urn:k"))
  let track = d.elements(k, "gx:Track")[0]
  assert_eq(d.local_name(track), "Track")
  assert_eq(d.namespace_uri(track), Some("urn:gx"))
  assert_eq(d.elements_ns(k, uri=None, lname=Some("coord")).length(), 3)
  assert_eq(d.elements_ns(k, uri=Some("urn:gx"), lname=None).length(), 2)
  assert_eq(d.elements_ns(k, uri=Some("urn:other"), lname=None).length(), 1)
  assert_eq(d.elements_ns(k, uri=Some("urn:none"), lname=None).length(), 0)
  assert_eq(d.elements(k, "coord").length(), 1)
}

///|
test "line ends normalized, a BOM dropped, malformed UTF-8 as U+FFFD" {
  let bytes : Bytes = b"\xEF\xBB\xBF<a b=\"\t\r\nc\">x\r\ny\rz\xC2\x85w\xE2\x80\xA8v\xFF</a>"
  let d = @xml.Document::parse(bytes)
  let a = root(d)
  assert_eq(d.attribute(a, "b"), Some("  c"))
  assert_eq(d.text(a), "x\ny\nz\nw\nv\u{FFFD}")
}

///|
test "xmldom's recoveries: a lone <, unquoted and valueless attributes" {
  let d = parse("<a b=1 c d=\"x>\"><e>1 < 2</e><f>a <1b/> c</f></a>")
  let a = root(d)
  assert_eq(attrs(d, a), [("b", "1"), ("c", "c"), ("d", "x>")])
  assert_eq(d.text(d.elements(a, "e")[0]), "1 < 2")
  assert_eq(d.text(d.elements(a, "f")[0]), "a <1b/> c")
  assert_eq(d.elements(a, "*").length(), 2)
  // Text after the root, a second end tag of the root and a start tag after that.
  assert_true(parse("<a/>x").length() == 2)
  assert_true(parse("<a/></a><b/>").length() == 2)
  assert_true(parse("<a></a\nfoo>").length() == 2)
}

///|
test "fatal errors as xmldom's ParseError" {
  for
    s in [
      "", "x", "<a>", "<a></b>", "<a/><b/>", "<a b=\"1\" b=\"2\"/>", "<a b=\"<\"/>",
      "<a><!-- x -- y --></a>", "<a><![CDATA[x</a>", "<a><?pi</a>", " <?xml version=\"1.0\"?><a/>",
      "<a><gx:b/></a>", "<a x:y=\"1\"/>", "<xmlns/>", "<a xmlns:p=\"\"><p:b/></a>",
      "<a/></b>", "</a><a/>", "<a/></a><![CDATA[x]]>", "<![CDATA[x]]><a/>", "<a><!DOCTYPE a></a>",
      "<!DOCTYPEa><a/>", "<a b=/>", "<1a/>", "<a:b:c/>", "<a><!x></a>", "<a b=>",
    ] {
    assert_true(fails(s), msg=s)
  }
  for
    s in [
      "<a/>", "<a/> <!--c--> <?p d?> ", "<!DOCTYPE a SYSTEM \"x\"><a/>", "<a/><![CDATA[x]]>",
      "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?><a/>", "<a/ >",
      "<a b='x\"y'/>", "<a xmlns:p=\"u\" xmlns:q=\"u\" p:x=\"1\" q:x=\"2\"/>", "<xml:a/>",
      "<a/><", "<a/",
      // xmldom refuses these two; declarations are not checked here.
       "<?xml version=\"2.0\"?><a/>", "<!DOCTYPE a [ <!ENTITY a \"%x\"> ]><a/>",
    ] {
    assert_true(!fails(s), msg=s)
  }
  let d = parse("<a xmlns:p=\"u\" xmlns:q=\"u\" p:x=\"1\" q:x=\"2\"/>")
  assert_eq(d.attribute(root(d), "q:x"), Some("2"))
  assert_eq(d.attribute(root(d), "p:x"), None)
}

///|
test "caps on depth, attributes and nodes" {
  let deep = StringBuilder()
  for _ in 0..<(@xml.MAX_XML_DEPTH + 1) {
    deep.write_string("<a>")
  }
  for _ in 0..<(@xml.MAX_XML_DEPTH + 1) {
    deep.write_string("</a>")
  }
  assert_true(fails(deep.to_string()))
  let many = StringBuilder()
  many.write_string("<a")
  for i in 0..<(@xml.MAX_XML_ATTRIBUTES + 1) {
    many.write_string(" a\{i}=\"\"")
  }
  many.write_string("/>")
  assert_true(fails(many.to_string()))
  let msg = try parse("<a>") catch {
    e => e.message()
  } noraise {
    _ => ""
  }
  assert_eq(msg, "malformed XML at 3: unclosed xml tag(s)")
}

///|
test "units copies code units, surrogate halves included" {
  assert_eq(@xml.units("a\u{1F600}b", 0, 2).length(), 2)
  let s = "a\u{1F600}b"
  assert_eq(@xml.units(s, 1, 2) + @xml.units(s, 2, 3), "\u{1F600}")
  assert_eq(@xml.units("abc", 1, 3), "bc")
}

///|
test "is_js_space is JavaScript's white space" {
  assert_true(@xml.is_js_space(0x20))
  assert_true(@xml.is_js_space(0xFEFF))
  assert_true(@xml.is_js_space(0x3000))
  assert_true(!@xml.is_js_space(0x85))
  assert_true(!@xml.is_js_space(0x41))
}

///|
test "Names numbers strings in the order first added" {
  let names = @xml.Names::new()
  assert_eq(names.add("a"), 0)
  assert_eq(names.add("b"), 1)
  assert_eq(names.add("a"), 0)
  assert_eq(names.find("b"), 1)
  assert_eq(names.find("c"), -1)
  assert_eq(names.length(), 2)
  assert_eq(names.at(1), "b")
}
