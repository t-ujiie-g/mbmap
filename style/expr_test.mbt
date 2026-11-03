///|
/// A feature with fixed properties, for evaluating expressions in tests.
struct Feature {
  props : Map[String, @style.Value]
  geometry : String
}

///|
impl @style.FeatureContext for Feature with fn property(self, key) {
  self.props.get(key)
}

///|
impl @style.FeatureContext for Feature with fn geometry_type(self) {
  self.geometry
}

///|
fn expr(
  text : String,
  expected~ : @style.Expected = AnyType,
) -> @style.Expr raise {
  @style.compile(@json.parse(text), expected~)
}

///|
fn feature(
  props : Array[(String, @style.Value)],
  geometry~ : String = "Polygon",
) -> Feature {
  { props: Map::from_array(props), geometry, }
}

///|
test "filters from the GSI bench style" {
  let road0 = feature([("rdCtg", Num(0.0))], geometry="LineString")
  let road2 = feature([("rdCtg", Num(2.0))], geometry="LineString")
  let casing = expr(
    (
      #|["any", ["==", ["get", "rdCtg"], 0], ["==", ["get", "rdCtg"], 1]]
    ),
  )
  assert_eq(casing.eval(14.0, road0), Bool(true))
  assert_eq(casing.eval(14.0, road2), Bool(false))
  let rail = expr(
    (
      #|["in", ["get", "snglDbl"], ["literal", [1, 2, 3, 4]]]
    ),
  )
  assert_eq(rail.eval(14.0, feature([("snglDbl", Num(2.0))])), Bool(true))
  assert_eq(rail.eval(14.0, feature([("snglDbl", Num(5.0))])), Bool(false))
  assert_eq(rail.eval(14.0, feature([])), Bool(false))
  let polygon = expr(
    (
      #|["==", ["geometry-type"], "Polygon"]
    ),
  )
  assert_eq(polygon.eval(14.0, feature([])), Bool(true))
  assert_eq(polygon.eval(14.0, road0), Bool(false))
}

///|
test "comparisons do not coerce types" {
  let f = feature([("n", Num(1.0)), ("s", Str("1"))])
  assert_eq(expr("[\"==\", [\"get\", \"n\"], \"1\"]").eval(0.0, f), Bool(false))
  assert_eq(expr("[\"==\", [\"get\", \"s\"], \"1\"]").eval(0.0, f), Bool(true))
  assert_eq(
    expr("[\"!=\", [\"get\", \"missing\"], 1]").eval(0.0, f),
    Bool(true),
  )
  assert_eq(expr("[\"<\", [\"get\", \"n\"], 2]").eval(0.0, f), Bool(true))
  assert_eq(expr("[\">=\", [\"get\", \"s\"], 2]").eval(0.0, f), Failed)
  assert_eq(expr("[\"has\", \"s\"]").eval(0.0, f), Bool(true))
  assert_eq(expr("[\"!\", [\"has\", \"x\"]]").eval(0.0, f), Bool(true))
  assert_eq(expr("[\"in\", \"ab\", \"cabd\"]").eval(0.0, f), Bool(true))
}

///|
test "match, case and coalesce pick outputs; colors compile from strings" {
  let fill = expr(
    (
      #|["match", ["get", "ftCode"], 3103, "#d9c9b6", [3101, 3102], "#e3ddd3", "#000"]
    ),
    expected=ColorType,
  )
  let c = (code : Double) => fill.eval(0.0, feature([("ftCode", Num(code))]))
  assert_eq(c(3103), Color(@style.parse_color("#d9c9b6").unwrap()))
  assert_eq(c(3102), Color(@style.parse_color("#e3ddd3").unwrap()))
  assert_eq(c(1.0), Color(@style.parse_color("#000").unwrap()))
  let pick = expr(
    (
      #|["case", ["has", "a"], ["get", "a"], ["coalesce", ["get", "b"], 7]]
    ),
  )
  assert_eq(pick.eval(0.0, feature([("a", Num(1.0))])), Num(1.0))
  assert_eq(pick.eval(0.0, feature([("b", Num(2.0))])), Num(2.0))
  assert_eq(pick.eval(0.0, feature([])), Num(7.0))
}

///|
test "interpolate and step over zoom" {
  let linear = expr(
    (
      #|["interpolate", ["linear"], ["zoom"], 14, 0.7, 16, 1]
    ),
  )
  let at = (z : Double) => {
    guard linear.eval(z, @style.NoFeature::{ }) is Num(v) else { return -1.0 }
    v
  }
  assert_eq(at(10.0), 0.7)
  assert_true((at(15.0) - 0.85).abs() < 1.0e-12)
  assert_eq(at(20.0), 1.0)
  // Exponential base 2 from 5 at z14 to 40 at z18: at z16 it is 5 + 35 * 3/15.
  let width = expr(
    (
      #|["interpolate", ["exponential", 2], ["zoom"], 14, 5, 18, 40]
    ),
  )
  guard width.eval(16.0, @style.NoFeature::{ }) is Num(w) else {
    fail("not a number")
  }
  assert_true((w - 12.0).abs() < 1.0e-12)
  let step = expr(
    (
      #|["step", ["zoom"], 1.5, 16, 3]
    ),
  )
  assert_eq(step.eval(15.9, @style.NoFeature::{ }), Num(1.5))
  assert_eq(step.eval(16.0, @style.NoFeature::{ }), Num(3.0))
  let colors = expr(
    (
      #|["interpolate", ["linear"], ["zoom"], 0, "#000000", 10, "#ffffff"]
    ),
    expected=ColorType,
  )
  guard colors.eval(5.0, @style.NoFeature::{ }) is Color(mid) else {
    fail("not a color")
  }
  assert_eq((mid.r, mid.a), (0.5, 1.0))
}

///|
test "feature inputs tell data-driven values from zoom-only ones" {
  let composite = expr(
    (
      #|["interpolate", ["exponential", 2], ["zoom"], 14, ["match", ["get", "rdCtg"], [0, 1], 3, 2, 1, 1.5], 18, 20]
    ),
  )
  assert_eq(composite.feature_inputs(), (["rdCtg"], false))
  assert_eq(
    expr("[\"step\", [\"zoom\"], 1, 16, 3]").feature_inputs(),
    ([], false),
  )
  assert_eq(
    expr("[\"==\", [\"geometry-type\"], \"Point\"]").feature_inputs(),
    ([], true),
  )
}

///|
test "malformed expressions are rejected with a path" {
  for
    text in [
      "[\"match\", [\"get\", \"a\"], 1, 2]", "[\"interpolate\", [\"linear\"], [\"zoom\"], 2, 1, 1, 0]",
      "[\"step\", [\"zoom\"]]", "[1, 2]", "[\"interpolate\", [\"cubic-bezier\", 0, 0, 2, 1], [\"zoom\"], 0, 0, 1, 1]",
    ] {
    try expr(text) catch {
      @style.Invalid(_) | @style.Unsupported(_) => ()
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected an error for \{text}")
    }
  }
}

///|
test "nesting beyond MAX_EXPR_DEPTH is Invalid, not a stack overflow" {
  let deep = (open : String, inner : String, n : Int32) => {
    let b = StringBuilder()
    for _ in 0..<n {
      b.write_string(open)
    }
    b.write_string(inner)
    for _ in 0..<n {
      b.write_string("]")
    }
    b.to_string()
  }
  let ok = deep("[\"!\", ", "true", @style.MAX_EXPR_DEPTH)
  assert_eq(
    expr(ok).eval(0.0, @style.NoFeature::{ }),
    Bool(@style.MAX_EXPR_DEPTH % 2 == 0),
  )
  for
    text in [
      deep("[\"!\", ", "true", 1000),
      "[\"literal\", " + deep("[", "1", 1000) + "]",
    ] {
    try expr(text) catch {
      @style.Invalid(_) => ()
      e => fail("unexpected \{Repr(e)}")
    } noraise {
      _ => fail("expected Invalid")
    }
  }
}

///|
test "interpolation types ignore extra arguments as MapLibre does" {
  let at = (text : String) => {
    guard expr(text).eval(16.0, @style.NoFeature::{ }) is Num(v) else {
      return -1.0
    }
    v
  }
  assert_eq(
    at(
      (
        #|["interpolate", ["linear", 1], ["zoom"], 14, 0, 18, 4]
      ),
    ),
    2.0,
  )
  assert_true(
    (at(
      (
        #|["interpolate", ["exponential", 2, 9], ["zoom"], 14, 5, 18, 40]
      ),
    ) -
    12.0).abs() <
    1.0e-12,
  )
}
