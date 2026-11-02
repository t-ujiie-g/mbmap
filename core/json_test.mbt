///|
test "strconv_number parses JSON numbers and gives NaN otherwise" {
  assert_eq(@core.strconv_number(b"-1.25e-3"[:]), -0.00125)
  assert_eq(
    @core.strconv_number(b"0.30000000000000004"[:]),
    0.30000000000000004,
  )
  assert_true(@core.strconv_number(b"x"[:]).is_nan())
}

///|
test "read_json_number takes the fast path up to 15 digits and the slow one beyond" {
  let slow = (s : Int32, e : Int32) => (e - s).to_double() * 1000.0
  assert_eq(@core.read_json_number(b"12.5e2,"[:], 0, slow), (1250.0, 6))
  assert_eq(@core.read_json_number(b"[-0.125]"[:], 1, slow), (-0.125, 7))
  // 17 digits go to the slow path, given the number's range.
  assert_eq(
    @core.read_json_number(b"1.2345678901234567"[:], 0, slow),
    (18000.0, 18),
  )
  for bad in [b"-"[:], b".5"[:], b"1."[:], b"1e"[:], b"x"[:]] {
    let (v, end) = @core.read_json_number(bad, 0, slow)
    assert_true(v.is_nan() && end == 0)
  }
  let nan = (_s : Int32, _e : Int32) => @double.not_a_number
  assert_eq(@core.read_json_number(b"1.2345678901234567"[:], 0, nan).1, 0)
}

///|
test "json_string_text resolves escapes and replaces what is not text" {
  assert_eq(@core.json_string_text(b"plain"[:]), "plain")
  assert_eq(
    @core.json_string_text(b"a\\\"b\\\\c\\/d\\n\\u00e9\\u0041"[:]),
    "a\"b\\c/d\né\u{41}",
  )
  assert_eq(@core.json_string_text(b"\\uzzzz\\q"[:]), "\u{FFFD}\u{FFFD}")
}

///|
test "parse_json builds Json and reports where it stops" {
  let v = @core.parse_json(
    b" {\"a\": [1, -2.5e1, true, false, null], \"b\": {\"c\": \"x\\u0079\"}} "[:],
  )
  assert_eq(v, {
    "a": [1.0, -25.0, true, false, Json::null()],
    "b": { "c": "xy" },
  })
  assert_eq(@core.parse_json(b"[]"[:]), Json::array([]))
  assert_eq(@core.parse_json(b"{}"[:]), Json::object(Map([])))
  let fails = [
    (b"{\"a\" 1}"[:], "expected ':' at 5"),
    (b"[1,]"[:], "invalid value at 3"),
    (b"[1] 2"[:], "unexpected text after the value at 4"),
    (b"\"a"[:], "unterminated string at 2"),
    (b"\"a\nb\""[:], "control character in string at 2"),
    (b"tru"[:], "invalid literal at 0"),
    (b"[[[1]]]"[:], "nested deeper than 2 at 2"),
  ]
  for f in fails {
    let (text, why) = f
    try @core.parse_json(text, max_depth=2) catch {
      e => assert_eq(e.message(), why)
    } noraise {
      _ => fail("\{why}: expected an error")
    }
  }
}

///|
test "parse_json hands long numbers to slow_number" {
  let v = @core.parse_json(b"[3.14159265358979323]"[:], slow_number=(_, _) => {
    7.0
  })
  assert_eq(v, Json::array([Json::number(7.0)]))
}
