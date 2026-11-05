///|
test "a document past its node cap is refused" {
  let p = Parser::new(b"<a><b/>text<![CDATA[x]]></a>", 4)
  p.run()
  assert_true(p.fatal is Some((_, "too many nodes")))
  let q = Parser::new(b"<a><b/>text<![CDATA[x]]></a>", 5)
  q.run()
  assert_true(q.fatal is None)
}
