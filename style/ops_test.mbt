///|
/// A feature with properties and an id.
struct Thing {
  props : Map[String, @style.Value]
  id : @style.Value
}

///|
impl @style.FeatureContext for Thing with fn property(self, key) {
  self.props.get(key)
}

///|
impl @style.FeatureContext for Thing with fn geometry_type(_) {
  "Point"
}

///|
impl @style.FeatureContext for Thing with fn id(self) {
  self.id
}

///|
fn thing() -> Thing {
  {
    props: Map::from_array([
      ("n", Num(3.0)),
      ("neg", Num(-2.5)),
      ("s", Str("Abc")),
      ("num", Str(" 12.5 ")),
      ("t", Bool(true)),
      ("z", Null),
      ("ja", Str("東京𠮷")),
    ]),
    id: Num(42.0),
  }
}

///|
fn ev(
  text : String,
  expected~ : @style.Expected = AnyType,
) -> @style.Value raise {
  @style.compile(@json.parse(text), expected~).eval(10.0, thing())
}

///|
fn num(text : String) -> Double raise {
  guard ev(text) is Num(x) else { fail("not a number: \{text}") }
  x
}

///|
fn near(a : Double, b : Double) -> Bool {
  (a - b).abs() <= 1.0e-12 * @cmp.maximum(1.0, b.abs())
}

///|
test "arithmetic follows JavaScript" {
  assert_eq(ev("[\"+\"]"), Num(0.0))
  assert_eq(ev("[\"+\", 1, 2, [\"get\", \"n\"]]"), Num(6.0))
  assert_eq(ev("[\"*\", 2, [\"get\", \"n\"], 0.5]"), Num(3.0))
  assert_eq(ev("[\"-\", [\"get\", \"n\"]]"), Num(-3.0))
  assert_eq(ev("[\"-\", 10, [\"get\", \"n\"]]"), Num(7.0))
  assert_eq(ev("[\"/\", 1, 4]"), Num(0.25))
  assert_true(num("[\"/\", 1, 0]") == @double.infinity)
  assert_eq(ev("[\"%\", -7, 3]"), Num(-1.0))
  assert_eq(ev("[\"%\", 5.5, 2]"), Num(1.5))
  assert_eq(ev("[\"^\", 2, 10]"), Num(1024.0))
  assert_eq(ev("[\"sqrt\", 16]"), Num(4.0))
  assert_true(num("[\"sqrt\", -1]").is_nan())
  assert_true(near(num("[\"log10\", 1000]"), 3.0))
  assert_true(near(num("[\"log2\", 8]"), 3.0))
  assert_true(near(num("[\"ln\", [\"e\"]]"), 1.0))
  assert_eq(ev("[\"ln2\"]"), Num(0.6931471805599453))
  assert_eq(ev("[\"pi\"]"), Num(3.141592653589793))
  assert_eq(ev("[\"sin\", 0]"), Num(0.0))
  assert_eq(ev("[\"cos\", 0]"), Num(1.0))
  assert_true(near(num("[\"tan\", [\"/\", [\"pi\"], 4]]"), 1.0))
  assert_true(near(num("[\"asin\", 1]"), 3.141592653589793 / 2.0))
  assert_true(near(num("[\"acos\", 0]"), 3.141592653589793 / 2.0))
  assert_true(near(num("[\"atan\", 1]"), 3.141592653589793 / 4.0))
  assert_eq(ev("[\"abs\", [\"get\", \"neg\"]]"), Num(2.5))
  assert_eq(ev("[\"ceil\", 1.2]"), Num(2.0))
  assert_eq(ev("[\"floor\", -1.2]"), Num(-2.0))
}

///|
test "round goes half away from zero; min and max as Math's" {
  assert_eq(ev("[\"round\", 2.5]"), Num(3.0))
  assert_eq(ev("[\"round\", [\"get\", \"neg\"]]"), Num(-3.0))
  assert_eq(ev("[\"round\", 0.49999999999999994]"), Num(0.0))
  assert_eq(ev("[\"min\", 3, 1, 2]"), Num(1.0))
  assert_eq(ev("[\"max\", 3, 1, 2]"), Num(3.0))
  assert_true(num("[\"min\"]") == @double.infinity)
  assert_true(num("[\"max\", 1, [\"sqrt\", -1]]").is_nan())
  assert_true(1.0 / num("[\"min\", 0, [\"-\", 0]]") < 0.0)
  assert_true(1.0 / num("[\"max\", [\"-\", 0], 0]") > 0.0)
}

///|
test "arithmetic on a value that is not a number fails" {
  assert_eq(ev("[\"+\", [\"get\", \"s\"], 1]"), Failed)
  assert_eq(ev("[\"sqrt\", [\"get\", \"missing\"]]"), Failed)
  assert_eq(ev("[\"-\", [\"get\", \"t\"]]"), Failed)
  assert_eq(ev("[\"coalesce\", [\"number\", [\"get\", \"s\"]], 1]"), Failed)
  assert_eq(
    ev("[\"to-string\", [\"*\", [\"get\", \"s\"], 2]]", expected=StringType),
    Failed,
  )
}

///|
test "to-number, to-string and to-boolean convert as JavaScript" {
  assert_eq(ev("[\"to-number\", [\"get\", \"num\"]]"), Num(12.5))
  assert_eq(ev("[\"to-number\", [\"get\", \"z\"]]"), Num(0.0))
  assert_eq(ev("[\"to-number\", [\"get\", \"t\"]]"), Num(1.0))
  assert_eq(ev("[\"to-number\", [\"get\", \"s\"], \"0x10\"]"), Num(16.0))
  assert_eq(ev("[\"to-number\", [\"literal\", [\"7\"]]]"), Num(7.0))
  assert_eq(ev("[\"to-number\", [\"get\", \"s\"]]"), Failed)
  assert_eq(ev("[\"to-string\", 1.5]"), Str("1.5"))
  assert_eq(ev("[\"to-string\", [\"get\", \"z\"]]"), Str(""))
  assert_eq(ev("[\"to-string\", [\"get\", \"t\"]]"), Str("true"))
  assert_eq(
    ev("[\"to-string\", [\"rgba\", 255, 0, 0, 0.5]]"),
    Str("rgba(255,0,0,0.5)"),
  )
  assert_eq(
    ev("[\"to-string\", [\"literal\", [1, \"a\\\"\\n\", null, true, [2]]]]"),
    Str("[1,\"a\\\"\\n\",null,true,[2]]"),
  )
  assert_eq(ev("[\"to-boolean\", 0]"), Bool(false))
  assert_eq(ev("[\"to-boolean\", \"\"]"), Bool(false))
  assert_eq(ev("[\"to-boolean\", [\"get\", \"z\"]]"), Bool(false))
  assert_eq(ev("[\"to-boolean\", [\"sqrt\", -1]]"), Bool(false))
  assert_eq(ev("[\"to-boolean\", \"0\"]"), Bool(true))
  assert_eq(ev("[\"to-boolean\", [\"literal\", []]]"), Bool(true))
}

///|
test "to-color takes the first argument that is a color" {
  let red = @style.parse_color("#f00").unwrap()
  assert_eq(ev("[\"to-color\", \"#f00\"]"), Color(red))
  assert_eq(ev("[\"to-color\", [\"get\", \"s\"], 5, \"#f00\"]"), Color(red))
  assert_eq(ev("[\"to-color\", [\"literal\", [255, 0, 0]]]"), Color(red))
  // MapLibre takes the channels of an array as premultiplied by its alpha.
  assert_eq(
    ev("[\"to-color\", [\"literal\", [255, 0, 0, 0.5]]]"),
    Color({ r: 2.0, g: 0.0, b: 0.0, a: 0.5, }),
  )
  assert_eq(ev("[\"to-color\", [\"literal\", [300, 0, 0]]]"), Failed)
  assert_eq(ev("[\"to-color\", [\"get\", \"s\"]]"), Failed)
  assert_eq(ev("[\"get\", \"s\"]", expected=ColorType), Failed)
}

///|
test "rgb, rgba and to-rgba" {
  assert_eq(
    ev("[\"rgb\", 255, 0, 0]"),
    Color({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }),
  )
  assert_eq(
    ev("[\"rgba\", 0, 51, 255, 0.5]"),
    Color({ r: 0.0, g: 0.2, b: 1.0, a: 0.5, }),
  )
  assert_eq(ev("[\"rgb\", 256, 0, 0]"), Failed)
  assert_eq(ev("[\"rgba\", 0, 0, 0, 2]"), Failed)
  assert_eq(ev("[\"rgb\", [\"get\", \"s\"], 0, 0]"), Failed)
  assert_eq(
    ev("[\"to-rgba\", \"#ff0000\"]"),
    List([Num(255.0), Num(0.0), Num(0.0), Num(1.0)]),
  )
  assert_eq(ev("[\"to-rgba\", [\"get\", \"s\"]]"), Failed)
}

///|
test "typeof and array assertions name MapLibre's types" {
  assert_eq(ev("[\"typeof\", [\"get\", \"n\"]]"), Str("number"))
  assert_eq(ev("[\"typeof\", [\"get\", \"z\"]]"), Str("null"))
  assert_eq(ev("[\"typeof\", [\"get\", \"missing\"]]"), Str("null"))
  assert_eq(ev("[\"typeof\", [\"get\", \"t\"]]"), Str("boolean"))
  assert_eq(ev("[\"typeof\", [\"get\", \"s\"]]"), Str("string"))
  assert_eq(ev("[\"typeof\", [\"to-color\", \"red\", \"#fff\"]]"), Str("color"))
  assert_eq(ev("[\"typeof\", [\"literal\", [1, 2]]]"), Str("array<number, 2>"))
  assert_eq(ev("[\"typeof\", [\"literal\", []]]"), Str("array<value, 0>"))
  assert_eq(
    ev("[\"typeof\", [\"literal\", [1, \"a\"]]]"),
    Str("array<value, 2>"),
  )
  assert_eq(
    ev("[\"typeof\", [\"literal\", [[1]]]]"),
    Str("array<array<number, 1>, 1>"),
  )
  assert_eq(
    ev("[\"typeof\", [\"literal\", [[1], [2]]]]"),
    Str("array<value, 2>"),
  )
  assert_eq(
    ev("[\"array\", \"number\", 2, [\"literal\", [1, 2]]]"),
    List([Num(1.0), Num(2.0)]),
  )
  assert_eq(ev("[\"array\", \"number\", 3, [\"literal\", [1, 2]]]"), Failed)
  assert_eq(ev("[\"array\", \"string\", [\"literal\", [1]]]"), Failed)
  assert_eq(ev("[\"array\", [\"get\", \"s\"], [\"literal\", []]]"), List([]))
  assert_eq(ev("[\"array\", [\"get\", \"s\"]]"), Failed)
}

///|
test "string operators count code points" {
  assert_eq(
    ev("[\"concat\", \"a\", 1, [\"get\", \"z\"], [\"get\", \"t\"]]"),
    Str("a1true"),
  )
  assert_eq(ev("[\"concat\", \"a\", [\"+\", [\"get\", \"s\"], 1]]"), Failed)
  assert_eq(ev("[\"upcase\", \"aé ß ｚ\"]"), Str("AÉ SS Ｚ"))
  assert_eq(ev("[\"downcase\", [\"get\", \"s\"]]"), Str("abc"))
  assert_eq(ev("[\"upcase\", 1]"), Failed)
  assert_eq(ev("[\"length\", [\"get\", \"ja\"]]"), Num(3.0))
  assert_eq(ev("[\"length\", [\"literal\", [1, 2]]]"), Num(2.0))
  assert_eq(ev("[\"length\", 1]"), Failed)
  assert_eq(ev("[\"slice\", [\"get\", \"ja\"], 1]"), Str("京𠮷"))
  assert_eq(ev("[\"slice\", [\"get\", \"s\"], -2]"), Str("bc"))
  assert_eq(ev("[\"slice\", [\"get\", \"s\"], 0, 1.9]"), Str("A"))
  assert_eq(
    ev("[\"slice\", [\"literal\", [1, 2, 3]], 1, -1]"),
    List([Num(2.0)]),
  )
  assert_eq(ev("[\"slice\", 5, 1]"), Failed)
  assert_eq(ev("[\"index-of\", \"𠮷\", [\"get\", \"ja\"]]"), Num(2.0))
  assert_eq(ev("[\"index-of\", \"b\", [\"get\", \"s\"], 2]"), Num(-1.0))
  assert_eq(ev("[\"index-of\", 1, \"x1\"]"), Num(1.0))
  assert_eq(ev("[\"index-of\", 2, [\"literal\", [1, 2, 2]], -1]"), Num(2.0))
  assert_eq(
    ev("[\"index-of\", [\"literal\", [1]], [\"literal\", [1]]]"),
    Failed,
  )
  assert_eq(ev("[\"index-of\", 1, 1]"), Failed)
  assert_eq(ev("[\"at\", 1, [\"literal\", [\"a\", \"b\"]]]"), Str("b"))
  assert_eq(ev("[\"at\", 2, [\"literal\", [\"a\", \"b\"]]]"), Failed)
  assert_eq(ev("[\"at\", 0.5, [\"literal\", [\"a\", \"b\"]]]"), Failed)
  assert_eq(ev("[\"at\", 0, [\"get\", \"s\"]]"), Failed)
}

///|
test "in, comparisons and logic fail on values of the wrong type" {
  assert_eq(ev("[\"in\", 1, \"x1\"]"), Bool(true))
  assert_eq(ev("[\"in\", [\"get\", \"z\"], \"null\"]"), Bool(true))
  assert_eq(ev("[\"in\", \"a\", [\"get\", \"z\"]]"), Bool(false))
  assert_eq(ev("[\"in\", \"a\", 0]"), Bool(false))
  assert_eq(ev("[\"in\", \"a\", 5]"), Failed)
  assert_eq(ev("[\"in\", [\"literal\", [1]], \"a\"]"), Failed)
  assert_eq(ev("[\"<\", \"b\", \"ab\"]"), Bool(false))
  assert_eq(ev("[\"<\", \"ab\", \"b\"]"), Bool(true))
  assert_eq(ev("[\"<\", [\"sqrt\", -1], 1]"), Bool(false))
  assert_eq(ev("[\"<\", [\"get\", \"z\"], [\"get\", \"z\"]]"), Failed)
  assert_eq(ev("[\"==\", [\"get\", \"z\"], null]"), Bool(true))
  assert_eq(
    ev("[\"==\", [\"get\", \"n\"], [\"+\", [\"get\", \"s\"], 1]]"),
    Failed,
  )
  assert_eq(ev("[\"!\", [\"get\", \"n\"]]"), Failed)
  assert_eq(ev("[\"any\", true, [\"get\", \"n\"]]"), Bool(true))
  assert_eq(ev("[\"any\", false, [\"get\", \"n\"]]"), Failed)
  assert_eq(ev("[\"all\", false, [\"get\", \"n\"]]"), Bool(false))
  assert_eq(ev("[\"case\", [\"get\", \"n\"], 1, 2]"), Failed)
  assert_eq(ev("[\"match\", [\"+\", [\"get\", \"s\"], 1], 1, 1, 2]"), Failed)
}

///|
test "id, properties and the feature id key" {
  assert_eq(ev("[\"id\"]"), Num(42.0))
  assert_eq(ev("[\"get\", \"n\", [\"properties\"]]"), Num(3.0))
  assert_eq(ev("[\"has\", \"z\", [\"properties\"]]"), Bool(true))
  let e = @style.compile(@json.parse("[\"==\", [\"id\"], 1]"))
  assert_eq(e.feature_inputs(), ([@style.FEATURE_ID_KEY], false))
  assert_eq(@style.NoFeature::{ }.id(), Null)
}

///|
test "let binds names for var" {
  assert_eq(
    ev("[\"let\", \"a\", 2, [\"*\", [\"var\", \"a\"], [\"var\", \"a\"]]]"),
    Num(4.0),
  )
  assert_eq(
    ev("[\"let\", \"a\", 1, [\"let\", \"a\", 5, [\"var\", \"a\"]]]"),
    Num(5.0),
  )
  assert_eq(
    ev(
      "[\"let\", \"x\", [\"get\", \"s\"], [\"var\", \"x\"]]",
      expected=NumberType,
    ),
    Failed,
  )
  for
    text in [
      "[\"var\", \"a\"]", "[\"let\", \"a\", 1, \"b\", [\"var\", \"a\"], 0]", "[\"let\", \"a-b\", 1, 0]",
      "[\"let\", \"a\", 1]",
    ] {
    let json = @json.parse(text)
    try @style.compile(json) catch {
      @style.Invalid(_) => ()
      e => fail("unexpected \{e.message()}")
    } noraise {
      _ => fail("expected Invalid for \{text}")
    }
  }
}

///|
test "var bound expressions count toward MAX_EXPR_NODES" {
  let b = StringBuilder()
  for i in 0..<13 {
    b.write_string(
      "[\"let\", \"v\{i + 1}\", [\"+\", [\"var\", \"v\{i}\"], [\"var\", \"v\{i}\"]], ",
    )
  }
  let text = "[\"let\", \"v0\", 1, " +
    b.to_string() +
    "[\"var\", \"v13\"]" +
    "]".repeat(14)
  let json = @json.parse(text)
  try @style.compile(json) catch {
    e => assert_true(e.message().contains("\{@style.MAX_EXPR_NODES}"))
  } noraise {
    _ => fail("expected Invalid")
  }
}

///|
test "types MapLibre rejects when parsing are Invalid" {
  for
    case_ in [
      ("[\"==\", 1, \"a\"]", @style.Expected::AnyType),
      ("5", ColorType),
      ("\"a\"", NumberType),
      ("[\"+\", 1, 2]", StringType),
      (
        "[\"interpolate\", [\"cubic-bezier\", 0, 0, 1], [\"zoom\"], 0, 0, 1, 1]",
        AnyType,
      ),
    ] {
    let (text, expected) = case_
    let json = @json.parse(text)
    try @style.compile(json, expected~) catch {
      @style.Invalid(_) => ()
      e => fail("unexpected \{e.message()}")
    } noraise {
      _ => fail("expected Invalid for \{text}")
    }
  }
}

///|
test "cubic-bezier, hcl and lab interpolation" {
  let ctx = @style.NoFeature::{ }
  let bezier = @style.compile(
    @json.parse(
      "[\"interpolate\", [\"cubic-bezier\", 0.42, 0, 0.58, 1], [\"zoom\"], 0, 0, 10, 100]",
    ),
  )
  guard bezier.eval(2.5, ctx) is Num(v) else { fail("not a number") }
  assert_true(near(v, 100.0 * @core.Bezier::new(0.42, 0.0, 0.58, 1.0).at(0.25)))
  let red = @style.parse_color("#ff0000").unwrap()
  let blue = @style.parse_color("#0000ff").unwrap()
  for op in ["interpolate-hcl", "interpolate-lab"] {
    let e = @style.compile(
      @json.parse(
        "[\"\{op}\", [\"linear\"], [\"zoom\"], 0, \"#ff0000\", 10, \"#0000ff\"]",
      ),
      expected=ColorType,
    )
    guard (e.eval(0.0, ctx), e.eval(10.0, ctx), e.eval(5.0, ctx))
      is (Color(a), Color(b), Color(mid)) else {
      fail("not colors")
    }
    assert_eq((a, b), (red, blue))
    // Neither blends channel by channel, which would give (0.5, 0, 0.5).
    assert_true((mid.r - 0.5).abs() > 0.01 || (mid.g - 0.0).abs() > 0.01)
  }
  let gray = @style.compile(
    @json.parse(
      "[\"interpolate-hcl\", [\"linear\"], [\"zoom\"], 0, \"#000000\", 10, \"#ff0000\"]",
    ),
    expected=ColorType,
  )
  guard gray.eval(10.0, ctx) is Color(c) else { fail("not a color") }
  assert_eq(c, red)
}

///|
test "js_number reads what JavaScript's Number reads" {
  let cases = [
    ("  12.5e1 ", 125.0),
    ("", 0.0),
    ("\u{3000}12\n", 12.0),
    ("007", 7.0),
    ("+.5", 0.5),
    ("5.", 5.0),
    ("-0x10", @double.not_a_number),
    ("0x1F", 31.0),
    ("0o17", 15.0),
    ("0b101", 5.0),
    ("-Infinity", @double.neg_infinity),
    ("1e", @double.not_a_number),
    (".", @double.not_a_number),
    ("1_000", @double.not_a_number),
    ("abc", @double.not_a_number),
  ]
  for c in cases {
    let x = @style.js_number(c.0)
    assert_true(x == c.1 || (x.is_nan() && c.1.is_nan()), msg="\{c.0}: \{x}")
  }
}
