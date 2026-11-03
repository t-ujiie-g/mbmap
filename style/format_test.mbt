///|
/// A feature whose host `Intl` writes what it was asked and compares by length.
struct Intlish {
  values : Map[String, @style.Value]
}

///|
impl @style.FeatureContext for Intlish with fn property(self, key) {
  self.values.get(key)
}

///|
impl @style.FeatureContext for Intlish with fn geometry_type(_) {
  "Point"
}

///|
impl @style.FeatureContext for Intlish with fn number_format(
  _,
  x,
  locale,
  currency,
  unit,
  min,
  max,
) {
  guard locale != Some("bad") else { return None }
  let opt = (s : String?) => s.unwrap_or("-")
  let digits = (d : Double?) => {
    d.map(d => d.to_int().to_string()).unwrap_or("-")
  }
  Some(
    "\{x.to_int()} \{opt(locale)} \{opt(currency)} \{opt(unit)} \{digits(min)} \{digits(max)}",
  )
}

///|
impl @style.FeatureContext for Intlish with fn collate(_, a, b, case, _, locale) {
  if locale == Some("bad") {
    return @double.not_a_number
  }
  let fold = (s : String) => if case { s } else { s.to_lower() }
  if fold(a) == fold(b) {
    0.0
  } else {
    a.compare(b).to_double()
  }
}

///|
impl @style.FeatureContext for Intlish with fn resolved_locale(_, locale) {
  locale.map(l => "resolved-" + l)
}

///|
fn intlish(
  text : String,
  expected~ : @style.Expected = AnyType,
) -> @style.Value raise {
  let f = Intlish::{
    values: Map::from_array([
      ("n", @style.Value::Num(3.0)),
      ("s", Str("a b")),
      ("name", Str("東京")),
    ]),
  }
  @style.compile(@json.parse(text), expected~).eval(10.0, f)
}

///|
fn section(
  text : String,
  scale~ : Double? = None,
  font~ : String? = None,
  color~ : @style.Color? = None,
  align~ : String? = None,
) -> @style.Section {
  { text, scale, font, color, align, }
}

///|
test "format makes sections of text with their options, as MapLibre's FormattedSection" {
  let text =
    #|["format", ["get", "name"], {"font-scale": 1.5, "text-font": ["literal", ["A", "B"]]},
    #| "\n", {}, ["get", "n"], {"text-color": "red", "vertical-align": "top"}, ["get", "x"]]
  assert_eq(
    intlish(text),
    Formatted([
      section("東京", scale=Some(1.5), font=Some("A,B")),
      section("\n"),
      section(
        "3",
        color=Some({ r: 1.0, g: 0.0, b: 0.0, a: 1.0, }),
        align=Some("top"),
      ),
      section(""),
    ]),
  )
  // Falsy options are left out, as MapLibre's `if (arg['font-scale'])` does.
  assert_eq(
    intlish("[\"format\", \"a\", {\"font-scale\": 0, \"text-font\": null}]"),
    Formatted([section("a")]),
  )
  assert_eq(
    intlish("[\"to-string\", [\"format\", \"a\", {}, \"b\", {}]]"),
    Str("ab"),
  )
  assert_eq(intlish("[\"typeof\", [\"format\", \"a\", {}]]"), Str("formatted"))
  assert_eq(
    intlish("[\"format\", \"a\", {\"font-scale\": [\"get\", \"s\"]}]"),
    Failed,
  )
}

///|
test "format refuses what MapLibre's parser refuses, and images are unsupported" {
  for
    bad in [
      "[\"format\", {}]", "[\"format\", \"a\", {}, {}]", "[\"format\", 1]", "[\"format\", \"a\", {\"vertical-align\": \"middle\"}]",
      "[\"format\", \"a\", {\"font-scale\": \"big\"}]",
    ] {
    guard compile_error(bad) is Some(Invalid(_, ..)) else {
      fail("expected \{bad} to be invalid")
    }
  }
  guard compile_error("[\"format\", [\"image\", \"x\"], {}]")
    is Some(Unsupported(path~, _)) else {
    fail("expected images to be unsupported")
  }
  assert_eq(path, "[1]")
}

///|
test "is-supported-script is always true, as MapLibre's hosts never say otherwise" {
  assert_eq(
    intlish("[\"is-supported-script\", [\"get\", \"name\"]]"),
    Bool(true),
  )
  assert_eq(intlish("[\"is-supported-script\", [\"get\", \"n\"]]"), Bool(true))
  guard compile_error("[\"is-supported-script\", 1]") is Some(Invalid(_, ..)) else {
    fail("expected a string argument")
  }
}

///|
test "number-format hands its options to the host's Intl.NumberFormat" {
  assert_eq(
    intlish(
      "[\"number-format\", [\"get\", \"n\"], {\"locale\": \"ja\", \"currency\": \"JPY\", \"max-fraction-digits\": 2}]",
    ),
    Str("3 ja JPY - - 2"),
  )
  assert_eq(
    intlish(
      "[\"number-format\", 5, {\"unit\": \"meter\", \"min-fraction-digits\": 1, \"locale\": \"\"}]",
    ),
    Str("5 - - meter 1 -"),
  )
  assert_eq(
    intlish(
      "[\"number-format\", 5, {\"locale\": \"bad\"}]",
      expected=StringType,
    ),
    Failed,
  )
  assert_eq(intlish("[\"number-format\", [\"get\", \"s\"], {}]"), Failed)
  for
    bad in [
      "[\"number-format\", 1, 2]", "[\"number-format\", 1, {\"currency\": \"EUR\", \"unit\": \"meter\"}]",
      "[\"number-format\", 1]",
    ] {
    guard compile_error(bad) is Some(Invalid(_, ..)) else {
      fail("expected \{bad} to be invalid")
    }
  }
}

///|
test "split and join work on UTF-16 code units as JavaScript's" {
  let strs = (xs : Array[String]) => @style.Value::List(xs.map(x => Str(x)))
  let surrogates = "𠮷"
  assert_eq(intlish("[\"split\", [\"get\", \"s\"], \" \"]"), strs(["a", "b"]))
  assert_eq(intlish("[\"split\", \"a,,b,\", \",\"]"), strs(["a", "", "b", ""]))
  assert_eq(intlish("[\"split\", \"\", \",\"]"), strs([""]))
  assert_eq(intlish("[\"split\", \"\", \"\"]"), strs([]))
  assert_eq(
    intlish("[\"split\", \"𠮷a\", \"\"]"),
    strs([
      surrogates.unsafe_substring(start=0, end=1),
      surrogates.unsafe_substring(start=1, end=2),
      "a",
    ]),
  )
  assert_eq(intlish("[\"split\", [\"get\", \"n\"], \",\"]"), Failed)
  assert_eq(
    intlish("[\"join\", [\"split\", [\"get\", \"s\"], \" \"], \"-\"]"),
    Str("a-b"),
  )
  assert_eq(intlish("[\"join\", [\"literal\", []], \"-\"]"), Str(""))
  assert_eq(intlish("[\"join\", [\"literal\", [\"a\", 1]], \"-\"]"), Failed)
}

///|
test "collators compare strings through the host's Intl.Collator" {
  assert_eq(
    intlish("[\"==\", \"ABC\", \"abc\", [\"collator\", {}]]"),
    Bool(true),
  )
  assert_eq(
    intlish(
      "[\"==\", \"ABC\", \"abc\", [\"collator\", {\"case-sensitive\": true}]]",
    ),
    Bool(false),
  )
  assert_eq(
    intlish("[\"<\", \"ab\", \"abc\", [\"collator\", {\"locale\": \"de\"}]]"),
    Bool(true),
  )
  // Equality of other values is strict; ordering compares their text.
  assert_eq(
    intlish("[\"==\", [\"get\", \"n\"], 3, [\"collator\", {}]]"),
    Bool(true),
  )
  assert_eq(
    intlish("[\">\", [\"get\", \"n\"], 10, [\"collator\", {}]]"),
    Bool(false),
  )
  assert_eq(
    intlish("[\"<\", [\"get\", \"n\"], \"a\", [\"collator\", {}]]"),
    Failed,
  )
  assert_eq(
    intlish("[\"==\", \"a\", \"b\", [\"collator\", {\"locale\": \"bad\"}]]"),
    Failed,
  )
  assert_eq(
    intlish("[\"resolved-locale\", [\"collator\", {\"locale\": \"ja\"}]]"),
    Str("resolved-ja"),
  )
  assert_eq(
    intlish(
      "[\"let\", \"c\", [\"collator\", {}], [\"==\", \"A\", \"a\", [\"var\", \"c\"]]]",
    ),
    Bool(true),
  )
  assert_eq(
    intlish("[\"collator\", {\"diacritic-sensitive\": true}]"),
    Collator(false, true, None),
  )
  for
    bad in [
      "[\"typeof\", [\"collator\", {}]]", "[\"==\", 1, 2, [\"collator\", {}]]", "[\"==\", \"a\", \"b\", \"c\"]",
      "[\"collator\", 1]", "[\"resolved-locale\", \"en\"]",
    ] {
    guard compile_error(bad) is Some(Invalid(_, ..)) else {
      fail("expected \{bad} to be invalid")
    }
  }
}

///|
test "global-state takes the style's state defaults, or the state it is compiled with" {
  let style =
    #|{"state": {"min": {"default": 3}, "none": {}},
    #| "layers": [{"id": "a", "type": "background",
    #|   "paint": {"background-opacity": ["/", ["global-state", "min"], 10]}},
    #|  {"id": "b", "type": "background",
    #|   "paint": {"background-opacity": ["coalesce", ["global-state", "none"], ["global-state", "x"], 0.5]}}]}
  let s = @style.Style::parse(style)
  let at = (i : Int32) => s.layers[i].opacity.eval(0.0, @style.NoFeature::{ })
  assert_eq(at(0), Num(0.3))
  assert_eq(at(1), Num(0.5))
  let state = @style.state_defaults(@json.parse(style))
  assert_eq(state.get("min"), Some(Json::number(3.0)))
  assert_eq(state.get("none"), Some(Json::null()))
  let key = @json.parse("[\"global-state\", \"k\"]")
  let e = @style.with_global_state(
    Map::from_array([("k", Json::string("on"))]),
    () => @style.compile(key, expected=StringType),
  )
  assert_eq(e.eval(0.0, @style.NoFeature::{ }), Str("on"))
  // Outside, the state is empty again: the key reads null.
  let e = @style.compile(@json.parse("[\"global-state\", \"k\"]"))
  assert_eq(e.eval(0.0, @style.NoFeature::{ }), Null)
  guard compile_error("[\"global-state\", 1]") is Some(Invalid(_, ..)) else {
    fail("expected a string key")
  }
}

///|
test "the fallback Intl formats, compares and resolves without a host" {
  let intl = @style.Intl::fallback()
  guard (intl.number_format)(1.23456, None, None, None, None, None) is Some(s) else {
    fail("no text")
  }
  assert_true(s.has_prefix("1.23"))
  assert_eq((intl.collate)("abc", "ABC", false, false, None), 0.0)
  assert_true((intl.collate)("a", "b", true, false, None) < 0.0)
  assert_true((intl.resolved_locale)(Some("ja")) is Some(_))
}

///|
/// Why `text` does not compile, or None.
fn compile_error(text : String) -> @style.StyleError? raise {
  let json = @json.parse(text)
  try {
    @style.compile(json) |> ignore
    None
  } catch {
    e => Some(e)
  }
}
