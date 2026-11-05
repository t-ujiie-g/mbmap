///|
test "a document past its node cap is refused" {
  let p = Parser::new(b"<a><b/>text<![CDATA[x]]></a>", 4)
  p.run()
  assert_true(p.fatal is Some((_, "too many nodes")))
  let q = Parser::new(b"<a><b/>text<![CDATA[x]]></a>", 5)
  q.run()
  assert_true(q.fatal is None)
}

///|
test "Parser::gt_from reads each byte once however many tags ask" {
  let p = Parser::new(b"ab>cd>ef", 10)
  assert_eq(p.gt_from(0), 2)
  assert_eq(p.next_gt, 2)
  assert_eq(p.gt_from(1), 2)
  assert_eq(p.gt_from(2), 2)
  assert_eq(p.gt_from(3), 5)
  assert_eq(p.gt_from(6), -1)
  assert_eq(p.next_gt, 8)
  assert_eq(p.gt_from(7), -1)
}

///|
test "end tags past the document keep one far > for all of them" {
  let tags = "</a\n".repeat(5000)
  let doc = @utf8.encode("<r></r></r>" + tags + ">")
  let p = Parser::new(doc, 10)
  p.run()
  assert_eq(p.fatal, None)
  assert_eq(p.state, past_document)
  assert_eq(p.next_gt, doc.length() - 1)
}

///|
test "an attribute name may come back in the next tag, never in its own" {
  let p = Parser::new(b"<a x=\"1\"><b x=\"2\"/></a>", 10)
  p.run()
  assert_eq(p.fatal, None)
  let q = Parser::new(b"<a x=\"1\" y=\"2\" x=\"3\"/>", 10)
  q.run()
  assert_true(q.fatal is Some((15, "attribute redefined")))
}

///|
test "attributes of one namespace and local name replace each other per element" {
  let d = Document::parse(
    b"<a xmlns:p=\"u\" xmlns:q=\"u\" p:x=\"1\" q:x=\"2\" q:y=\"3\"><b p:x=\"4\"/></a>",
  )
  let a = d.first(0, "a").unwrap()
  assert_eq(d.attribute(a, "p:x"), None)
  assert_eq(d.attribute(a, "q:x"), Some("2"))
  assert_eq(d.attribute(a, "q:y"), Some("3"))
  assert_eq(d.attribute(d.first(0, "b").unwrap(), "p:x"), Some("4"))
}
