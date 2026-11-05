///|
/// A value an expression produces. `Failed` is MapLibre's runtime error: it goes up through
/// the expressions above it, and a property takes its default. `Collator` holds a
/// collator's case and diacritic sensitivity and locale.
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  Color(Color)
  List(Array[Value])
  Formatted(Array[Section])
  Collator(Bool, Bool, String?)
  Failed
} derive(Debug, Eq)

///|
/// A section of `format`'s text (MapLibre's `FormattedSection`): `font` is its
/// `text-font` joined by commas, `align` its `vertical-align`; None where the
/// section has no such option.
pub(all) struct Section {
  text : String
  scale : Double?
  font : String?
  color : Color?
  align : String?
} derive(Debug, Eq)

///|
/// The comparison operators `==`, `!=`, `<`, `<=`, `>` and `>=`.
pub(all) enum CmpOp {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Debug, Eq)

///|
/// How `interpolate` blends between stops: `Exponential(1.0)` is linear,
/// `CubicBezier` takes the curve's two control points.
pub(all) enum Interpolation {
  Exponential(Double)
  CubicBezier(Double, Double, Double, Double)
} derive(Debug, Eq)

///|
/// The color space `interpolate` (`Rgb`), `interpolate-hcl` and
/// `interpolate-lab` blend colors in.
pub(all) enum ColorSpace {
  Rgb
  Hcl
  Lab
} derive(Debug, Eq)

///|
/// The operators with fixed arguments (`-` with one argument negates). `Format` takes per
/// section its text, `font-scale`, `text-font`, `text-color` and `vertical-align`, and
/// `NumberFormat` and `Collator` their options in order; `Lit(Null)` where one is not given.
pub(all) enum Op {
  Add
  Sub
  Mul
  Div
  Rem
  Pow
  Sqrt
  Log10
  Ln
  Log2
  Sin
  Cos
  Tan
  Asin
  Acos
  Atan
  Min
  Max
  Round
  Abs
  Ceil
  Floor
  Concat
  Upcase
  Downcase
  TypeOf
  Length
  Slice
  IndexOf
  At
  Rgba
  ToRgba
  Split
  Join
  ResolvedLocale
  Format
  NumberFormat
  Collator
} derive(Debug, Eq)

///|
/// A compiled MapLibre expression (the subset this engine supports). Compiling resolves `let`,
/// `var` and `global-state` (its value in the style's `state`); `Collate` compares with the
/// collator last, `Within` holds polygons as rings of longitude, latitude pairs.
pub(all) enum Expr {
  Lit(Value)
  Get(String)
  Has(String)
  Id
  GeometryType
  Zoom
  LineProgress
  HeatmapDensity
  Elevation
  Accumulated
  Not(Expr)
  All(Array[Expr])
  Any(Array[Expr])
  Compare(CmpOp, Expr, Expr)
  In(Expr, Expr)
  Match(Expr, Array[(Array[Value], Expr)], Expr)
  Case(Array[(Expr, Expr)], Expr)
  Coalesce(Array[Expr])
  Interpolate(Interpolation, ColorSpace, Expr, Array[(Double, Expr)])
  Step(Expr, Expr, Array[(Double, Expr)])
  FeatureState(String)
  Assert(Expected, Array[Expr])
  Coerce(Expected, Array[Expr])
  Call(Op, Array[Expr])
  Collate(CmpOp, Expr, Expr, Expr)
  Within(Array[Array[Array[Double]]])
  Distance(Array[Shape])
} derive(Debug, Eq)

///|
/// A type an expression produces or must produce: `AnyType` is MapLibre's
/// `value`, `ArrayOf(item, n)` an array (`n` -1 for any length); `compile`
/// annotates for it as MapLibre's parser does.
pub(all) enum Expected {
  AnyType
  ColorType
  NumberType
  BoolType
  StringType
  ArrayOf(Expected, Int32)
} derive(Debug, Eq)

///|
/// Deepest nesting of expressions and literal arrays a style may use; deeper
/// input is rejected instead of recursing without bound.
pub const MAX_EXPR_DEPTH : Int32 = 32

///|
/// Most nodes a compiled expression may have once its `var`s are replaced by
/// what they are bound to, which keeps evaluation bounded.
pub const MAX_EXPR_NODES : Int32 = 4096

///|
/// Compiles a MapLibre expression (or a plain literal) from JSON.
pub fn compile(
  json : Json,
  expected~ : Expected = AnyType,
  path~ : String = "",
) -> Expr raise StyleError {
  let c = { scope: [], error: None, collator: expected is AnyType, nodes: 0, }
  let e = c.compile(json, expected, path, 0)
  if c.error is Some(err) {
    raise err
  }
  if e.size(MAX_EXPR_NODES, 0) < 0 {
    raise Invalid(path~, "more than \{MAX_EXPR_NODES} expressions")
  }
  e
}

///|
/// Nodes left of `budget` after counting `self`'s, or -1 past it or past four
/// times `MAX_EXPR_DEPTH` levels.
fn Expr::size(self : Expr, budget : Int32, depth : Int32) -> Int32 {
  if budget <= 0 || depth > 4 * MAX_EXPR_DEPTH {
    return -1
  }
  let mut left = budget - 1
  self.each_child(c => if left >= 0 { left = c.size(left, depth + 1) })
  left
}

///|
/// Compiling state: the `let` bindings in scope (innermost last) with their
/// sizes, the first error, after which nothing more is compiled, and the nodes
/// compiled so far with `var`s counted as what they stand for.
priv struct Compiler {
  scope : Array[(String, Expr, Int32)]
  mut error : StyleError?
  mut collator : Bool
  mut nodes : Int32
}

///|
fn Compiler::fail(self : Compiler, e : StyleError) -> Expr {
  if self.error is None {
    self.error = Some(e)
  }
  Lit(Null)
}

///|
fn sub(path : String, i : Int32) -> String {
  "\{path}[\{i}]"
}

///|
fn Compiler::value(
  self : Compiler,
  json : Json,
  path : String,
  depth : Int32,
) -> Value {
  if depth > MAX_EXPR_DEPTH {
    self.fail(Invalid(path~, "nested deeper than \{MAX_EXPR_DEPTH}")) |> ignore
    return Null
  }
  match json {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Num(n)
    String(s) => Str(s)
    Array(items) =>
      List(items.mapi((i, j) => self.value(j, sub(path, i), depth + 1)))
    Object(_) => {
      self.fail(Unsupported(path~, "object values")) |> ignore
      Null
    }
  }
}

///|
fn Compiler::key(self : Compiler, json : Json, path : String) -> String {
  guard json is String(s) else {
    self.fail(Unsupported(path~, "only literal property names")) |> ignore
    return ""
  }
  s
}

///|
/// The type `e` produces, as far as compiling can tell.
fn Expr::static_type(self : Expr) -> Expected {
  match self {
    Lit(Num(_))
    | Zoom
    | LineProgress
    | HeatmapDensity
    | Elevation
    | Distance(_) => NumberType
    Call(op, _) => op_type(op)
    Lit(Str(_)) | GeometryType => StringType
    Lit(Bool(_))
    | Has(_)
    | Not(_)
    | All(_)
    | Any(_)
    | Compare(_, _, _)
    | Collate(_, _, _, _)
    | Within(_)
    | In(_, _) => BoolType
    Lit(Color(_)) => ColorType
    Assert(t, _) | Coerce(t, _) => t
    Match(_, cases, _) => cases[0].1.static_type()
    Case(cases, _) => cases[0].1.static_type()
    Step(_, first, _) => first.static_type()
    Interpolate(_, Rgb, _, stops) => stops[0].1.static_type()
    Interpolate(_, _, _, _) => ColorType
    Coalesce(es) => {
      let t = es[0].static_type()
      for e in es[1:] {
        if e.static_type() != t {
          return AnyType
        }
      }
      t
    }
    _ => AnyType
  }
}

///|
/// The type a `Call` of `op` produces.
fn op_type(op : Op) -> Expected {
  match op {
    Concat
    | Upcase
    | Downcase
    | TypeOf
    | Join
    | ResolvedLocale
    | NumberFormat => StringType
    Rgba => ColorType
    Split => ArrayOf(StringType, -1)
    At | Slice | ToRgba | Format | Collator => AnyType
    _ => NumberType
  }
}

///|
fn type_name(t : Expected) -> String {
  match t {
    AnyType => "value"
    ColorType => "color"
    NumberType => "number"
    BoolType => "boolean"
    StringType => "string"
    ArrayOf(_, _) => "array"
  }
}

///|
/// Compiles `json` to produce `expected` as MapLibre's parser does: unless
/// `annotated` is false, an expression of type `value` is wrapped in an
/// assertion or `to-color`, and one of another type is an error.
fn Compiler::compile(
  self : Compiler,
  json : Json,
  expected : Expected,
  path : String,
  depth : Int32,
  annotated~ : Bool = true,
) -> Expr {
  // Counted as it goes: types are read off the tree, so it must stay small.
  self.nodes += 1
  if self.nodes > MAX_EXPR_NODES {
    return self.fail(Invalid(path~, "more than \{MAX_EXPR_NODES} expressions"))
  }
  let e = self.compile_at(json, expected, path, depth)
  let actual = e.static_type()
  match (expected, actual) {
    _ if !annotated || self.error is Some(_) || actual == expected => e
    (AnyType, _) => e
    (ColorType, AnyType | StringType) => Coerce(ColorType, [e])
    (ArrayOf(_, _), _) | (_, AnyType) => Assert(expected, [e])
    _ => self.fail(Invalid(path~, "expected \{type_name(expected)}"))
  }
}

///|
/// The fewest and most arguments of `op`, and the parity their count must have
/// (-1 for any).
fn arity(op : String) -> (Int32, Int32, Int32) {
  match op {
    "id" | "geometry-type" | "zoom" | "pi" | "e" | "ln2" | "accumulated" =>
      (0, 0, -1)
    "literal"
    | "feature-state"
    | "!"
    | "to-string"
    | "to-boolean"
    | "var"
    | "image"
    | "collator"
    | "global-state"
    | "resolved-locale"
    | "within"
    | "distance"
    | "is-supported-script" => (1, 1, -1)
    "get" | "has" => (1, 2, -1)
    "in" | "number-format" => (2, 2, -1)
    "==" | "!=" | "<" | "<=" | ">" | ">=" => (2, 3, -1)
    "format" => (1, 1 << 20, -1)
    "all" | "any" => (0, 1 << 20, -1)
    "match" | "interpolate" | "interpolate-hcl" | "interpolate-lab" =>
      (4, 1 << 20, 0)
    "case" | "let" => (3, 1 << 20, 1)
    "step" => (2, 1 << 20, 0)
    "boolean"
    | "number"
    | "string"
    | "array"
    | "to-number"
    | "to-color"
    | "coalesce" => (1, 1 << 20, -1)
    _ =>
      match op_of(op) {
        Some((_, min, max)) => (min, max, -1)
        None => (0, 1 << 20, -1)
      }
  }
}

///|
fn Compiler::compile_at(
  self : Compiler,
  json : Json,
  expected : Expected,
  path : String,
  depth : Int32,
) -> Expr {
  if self.error is Some(_) {
    return Lit(Null)
  }
  if depth > MAX_EXPR_DEPTH {
    return self.fail(Invalid(path~, "nested deeper than \{MAX_EXPR_DEPTH}"))
  }
  // Only the top, a binding and a comparison's collator may make a collator.
  let collator = self.collator
  self.collator = false
  guard json is Array(items) && items.length() > 0 && items[0] is String(op) else {
    if json is Array(_) {
      return self.fail(
        Invalid(path~, "an array literal must be wrapped in [\"literal\", ...]"),
      )
    }
    return self.literal(self.value(json, path, depth), expected, path)
  }
  let n = items.length() - 1
  let (min, max, parity) = arity(op)
  if n < min || n > max || (parity >= 0 && n % 2 != parity) {
    return self.fail(
      Invalid(
        path~,
        if n == 0 {
          "\{op} needs a value"
        } else {
          "\{op}: wrong number of arguments"
        },
      ),
    )
  }
  let arg = (i : Int32, e : Expected) => {
    self.compile(items[i], e, sub(path, i), depth + 1)
  }
  let rest = (from : Int32, e : Expected) => {
    Array::makei(n + 1 - from, k => arg(from + k, e))
  }
  // Outputs after the first must have the first one's type (MapLibre's
  // `outputType`).
  let mut out = expected
  let output = (i : Int32) => {
    let e = arg(i, out)
    if out is AnyType {
      out = e.static_type()
    }
    e
  }
  let stops = (from : Int32) => {
    let stops : Array[(Double, Expr)] = []
    for i = from; i < n; i = i + 2 {
      guard items[i] is Number(stop, ..) &&
        (stops.length() == 0 || stop > stops[stops.length() - 1].0) else {
        return [
          (
            0.0,
            self.fail(
              Invalid(path=sub(path, i), "stops must be increasing numbers"),
            ),
          ),
        ]
      }
      stops.push((stop, output(i + 1)))
    }
    stops
  }
  match op {
    "literal" =>
      self.literal(self.value(items[1], sub(path, 1), depth), expected, path)
    "get" | "has" => {
      if n == 2 && !(items[2] is Array([String("properties")])) {
        return self.fail(Unsupported(path~, "\{op} with an object argument"))
      }
      let key = self.key(items[1], sub(path, 1))
      if op == "get" {
        Get(key)
      } else {
        Has(key)
      }
    }
    "id" => Id
    "geometry-type" => GeometryType
    "zoom" => Zoom
    "line-progress" => LineProgress
    "heatmap-density" => HeatmapDensity
    "elevation" => Elevation
    "accumulated" => Accumulated
    "pi" => Lit(Num(pi))
    "e" => Lit(Num(2.718281828459045))
    "ln2" => Lit(Num(0.6931471805599453))
    "feature-state" => FeatureState(self.key(items[1], sub(path, 1)))
    "boolean" => Assert(BoolType, rest(1, AnyType))
    "number" => Assert(NumberType, rest(1, AnyType))
    "string" => Assert(StringType, rest(1, AnyType))
    "array" => {
      // ["array", item type?, length?, value...]
      let (item, i) = match items[1] {
        String("string") if n > 1 => (StringType, 2)
        String("number") if n > 1 => (NumberType, 2)
        String("boolean") if n > 1 => (BoolType, 2)
        _ => (AnyType, 1)
      }
      let (len, i) = match items[i] {
        Number(len, ..) if i == 2 &&
          n > 2 &&
          len >= 0.0 &&
          len == len.floor() &&
          len < 1.0e9 => (len.to_int(), 3)
        Null if i == 2 && n > 2 => (-1, 3)
        _ => (-1, i)
      }
      Assert(ArrayOf(item, len), rest(i, AnyType))
    }
    "to-number" => Coerce(NumberType, rest(1, AnyType))
    "to-color" => Coerce(ColorType, rest(1, AnyType))
    "to-string" => Coerce(StringType, rest(1, AnyType))
    // An image is known by its name (MapLibre's ResolvedImage).
    "image" => Coerce(StringType, rest(1, AnyType))
    "to-boolean" => Coerce(BoolType, rest(1, AnyType))
    "!" => Not(arg(1, BoolType))
    "all" => All(rest(1, BoolType))
    "any" => Any(rest(1, BoolType))
    "==" | "!=" | "<" | "<=" | ">" | ">=" => {
      let cmp = match op {
        "==" => CmpOp::Eq
        "!=" => Ne
        "<" => Lt
        "<=" => Le
        ">" => Gt
        _ => Ge
      }
      let (a, b) = (arg(1, AnyType), arg(2, AnyType))
      let (ta, tb) = (a.static_type(), b.static_type())
      if ta != tb && ta != AnyType && tb != AnyType {
        return self.fail(
          Invalid(path~, "cannot compare \{type_name(ta)} and \{type_name(tb)}"),
        )
      }
      if n == 2 {
        return Compare(cmp, a, b)
      }
      if !(ta is (StringType | AnyType)) && !(tb is (StringType | AnyType)) {
        return self.fail(
          Invalid(path~, "cannot use collator to compare non-string types"),
        )
      }
      Collate(cmp, a, b, self.collator(items[3], sub(path, 3), depth))
    }
    "collator" => {
      if !collator {
        return self.fail(Invalid(path~, "a collator only goes in comparisons"))
      }
      guard items[1] is Object(o) else {
        return self.fail(Invalid(path~, "collator options must be an object"))
      }
      let at = sub(path, 1)
      let flag = (key : String) => {
        match o.get(key) {
          None => Lit(Bool(false))
          Some(j) => self.compile(j, BoolType, "\{at}.\{key}", depth + 1)
        }
      }
      Call(Collator, [
        flag("case-sensitive"),
        flag("diacritic-sensitive"),
        self.option(o, "locale", StringType, at, depth),
      ])
    }
    "resolved-locale" =>
      Call(ResolvedLocale, [self.collator(items[1], sub(path, 1), depth)])
    "number-format" => {
      guard items[2] is Object(o) else {
        return self.fail(
          Invalid(path~, "number-format options must be an object"),
        )
      }
      let at = sub(path, 2)
      let option = (key : String, t : Expected) => {
        self.option(o, key, t, at, depth)
      }
      let currency = option("currency", StringType)
      let unit = option("unit", StringType)
      if !(currency is Lit(Null)) && !(unit is Lit(Null)) {
        return self.fail(
          Invalid(path=at, "currency and unit are mutually exclusive"),
        )
      }
      Call(NumberFormat, [
        arg(1, NumberType),
        option("locale", StringType),
        currency,
        unit,
        option("min-fraction-digits", NumberType),
        option("max-fraction-digits", NumberType),
      ])
    }
    "format" => self.format(items, path, depth)
    // MapLibre's hosts never pass `isSupportedScript`, so every script is.
    "is-supported-script" => {
      arg(1, StringType) |> ignore
      Lit(Bool(true))
    }
    "global-state" => {
      guard items[1] is String(key) else {
        return self.fail(
          Invalid(path~, "global state property must be a string"),
        )
      }
      let v = match style_state.val.get(key) {
        Some(j) => self.value(j, sub(path, 1), depth)
        None => Null
      }
      Assert(AnyType, [Lit(v)])
    }
    "within" =>
      match within_polygons(items[1]) {
        Some(p) => Within(p)
        None =>
          self.fail(
            Invalid(path~, "within needs a GeoJSON polygon or multipolygon"),
          )
      }
    "distance" =>
      match distance_shapes(items[1]) {
        Some(s) => Distance(s)
        None => self.fail(Invalid(path~, "distance needs a GeoJSON geometry"))
      }
    "in" => In(arg(1, AnyType), arg(2, AnyType))
    "match" => {
      let cases = []
      for i = 2; i < n; i = i + 2 {
        let labels = match self.value(items[i], sub(path, i), depth) {
          List(ls) => ls
          v => [v]
        }
        cases.push((labels, output(i + 1)))
      }
      Match(arg(1, AnyType), cases, output(n))
    }
    "case" => {
      let cases = []
      for i = 1; i < n; i = i + 2 {
        cases.push((arg(i, BoolType), output(i + 1)))
      }
      Case(cases, output(n))
    }
    "coalesce" => {
      let parts = []
      for i in 1..<=n {
        let e = self.compile(
          items[i],
          out,
          sub(path, i),
          depth + 1,
          annotated=false,
        )
        if out is AnyType {
          out = e.static_type()
        }
        parts.push(e)
      }
      Coalesce(parts)
    }
    "interpolate" | "interpolate-hcl" | "interpolate-lab" => {
      let interp = match items[1] {
        Array([String("linear"), ..]) => Exponential(1.0)
        Array([String("exponential"), Number(base, ..), ..]) =>
          Exponential(base)
        Array(
          [
            String("cubic-bezier"),
            Number(a, ..),
            Number(b, ..),
            Number(c, ..),
            Number(d, ..),
          ]
        ) if [a, b, c, d].iter().all(x => x >= 0.0 && x <= 1.0) =>
          CubicBezier(a, b, c, d)
        _ =>
          return self.fail(Invalid(path=sub(path, 1), "unknown interpolation"))
      }
      let space = match op {
        "interpolate" => Rgb
        "interpolate-hcl" => Hcl
        _ => Lab
      }
      if !(space is Rgb) {
        out = ColorType
      }
      Interpolate(interp, space, arg(2, NumberType), stops(3))
    }
    "step" => Step(arg(1, NumberType), output(2), stops(3))
    "let" => {
      let bound = []
      for i = 1; i < n; i = i + 2 {
        guard items[i] is String(name) &&
          name != "" &&
          name.iter().all(word_char) else {
          return self.fail(Invalid(path=sub(path, i), "not a variable name"))
        }
        self.collator = true
        let e = arg(i + 1, AnyType)
        let left = e.size(MAX_EXPR_NODES, 0)
        bound.push(
          (
            name,
            e,
            if left < 0 {
              MAX_EXPR_NODES
            } else {
              MAX_EXPR_NODES - left
            },
          ),
        )
      }
      let k = self.scope.length()
      self.scope.append(bound)
      let result = self.compile(
        items[n],
        expected,
        sub(path, n),
        depth + 1,
        annotated=false,
      )
      self.scope.truncate(k)
      result
    }
    "var" => {
      let name = self.key(items[1], sub(path, 1))
      for i = self.scope.length() - 1; i >= 0; i = i - 1 {
        if self.scope[i].0 == name {
          self.nodes += self.scope[i].2 - 1
          if self.nodes > MAX_EXPR_NODES {
            return self.fail(
              Invalid(path~, "more than \{MAX_EXPR_NODES} expressions"),
            )
          }
          return self.scope[i].1
        }
      }
      self.fail(Invalid(path~, "unknown variable \{name}"))
    }
    _ =>
      match op_of(op) {
        Some((o, _, _)) =>
          Call(o, rest(1, if o is ToRgba { ColorType } else { AnyType }))
        None => self.fail(Unsupported(path~, "expression \{op}"))
      }
  }
}

///|
/// `option` of `o` compiled for `t`, or `Lit(Null)` when it is absent or
/// falsy in JavaScript, as MapLibre leaves such options out.
fn Compiler::option(
  self : Compiler,
  o : Map[String, Json],
  key : String,
  t : Expected,
  path : String,
  depth : Int32,
) -> Expr {
  match o.get(key) {
    None | Some(Null | False | String("")) => Lit(Null)
    Some(Number(x, ..)) if x == 0.0 => Lit(Null)
    Some(j) => self.compile(j, t, "\{path}.\{key}", depth + 1)
  }
}

///|
/// A collator argument: an expression that makes one.
fn Compiler::collator(
  self : Compiler,
  json : Json,
  path : String,
  depth : Int32,
) -> Expr {
  self.collator = true
  let e = self.compile(json, AnyType, path, depth + 1)
  guard e is Call(Collator, _) || self.error is Some(_) else {
    return self.fail(Invalid(path~, "expected collator"))
  }
  e
}

///|
/// `format`: per section its text and options (`Op::Format`).
fn Compiler::format(
  self : Compiler,
  items : Array[Json],
  path : String,
  depth : Int32,
) -> Expr {
  if items[1] is Object(_) {
    return self.fail(
      Invalid(path~, "the first argument must be an image or text section"),
    )
  }
  let args = []
  let mut options = false
  for i in 1..<items.length() {
    let at = sub(path, i)
    match items[i] {
      Object(o) if options => {
        options = false
        let k = args.length() - 4
        args[k] = self.option(o, "font-scale", NumberType, at, depth)
        args[k + 1] = self.option(
          o,
          "text-font",
          ArrayOf(StringType, -1),
          at,
          depth,
        )
        args[k + 2] = self.option(o, "text-color", ColorType, at, depth)
        if o.get("vertical-align") is Some(String(a)) &&
          !(a is ("bottom" | "center" | "top")) {
          return self.fail(
            Invalid(
              path="\{at}.vertical-align",
              "not one of bottom, center and top",
            ),
          )
        }
        args[k + 3] = self.option(o, "vertical-align", StringType, at, depth)
      }
      Object(_) =>
        return self.fail(Invalid(path=at, "an object must follow a section"))
      Array([String("image"), ..]) =>
        return self.fail(Unsupported(path=at, "images in format"))
      j => {
        let content = self.compile(j, AnyType, at, depth + 1)
        if !(content.static_type() is (StringType | AnyType)) {
          return self.fail(
            Invalid(path=at, "a section must be a string, a value or null"),
          )
        }
        args.push(content)
        for _ in 0..<4 {
          args.push(Lit(Null))
        }
        options = true
      }
    }
  }
  Call(Format, args)
}

///|
/// The global state while a style's expressions compile: `global-state`
/// takes its value from here.
let style_state : Ref[Map[String, Json]] = { val: Map([]), }

///|
/// `f()` with `global-state` reading `state` (MapLibre's global state: each
/// key's value), as `Style::from_json` compiles with its style's `state`.
pub fn[T] with_global_state(
  state : Map[String, Json],
  f : () -> T raise StyleError,
) -> T raise StyleError {
  let saved = style_state.val
  style_state.val = state
  defer {
    style_state.val = saved
  }
  f()
}

///|
/// MapLibre's global state of a style: each key of its `state` with its
/// `default` (null without one).
fn state_defaults(json : Json) -> Map[String, Json] {
  let out = Map([])
  if json is Object(root) && root.get("state") is Some(Object(state)) {
    for k, v in state {
      out[k] = match v {
        Object(o) => o.get("default").unwrap_or(Json::null())
        _ => Json::null()
      }
    }
  }
  out
}

///|
fn Compiler::literal(
  self : Compiler,
  value : Value,
  expected : Expected,
  path : String,
) -> Expr {
  match (expected, value) {
    (ColorType, Str(s)) =>
      match parse_color(s) {
        Some(c) => Lit(Color(c))
        None => self.fail(Invalid(path~, "not a color: \{s}"))
      }
    _ => Lit(value)
  }
}

///|
fn word_char(c : Char) -> Bool {
  c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_')
}

///|
/// The `Op` named `name`, with its fewest and most arguments.
fn op_of(name : String) -> (Op, Int32, Int32)? {
  let (op, min, max) = match name {
    "+" => (Add, 0, 1 << 20)
    "*" => (Mul, 0, 1 << 20)
    "min" => (Min, 0, 1 << 20)
    "max" => (Max, 0, 1 << 20)
    "concat" => (Concat, 0, 1 << 20)
    "-" => (Sub, 1, 2)
    "/" => (Div, 2, 2)
    "%" => (Rem, 2, 2)
    "^" => (Pow, 2, 2)
    "slice" => (Slice, 2, 3)
    "index-of" => (IndexOf, 2, 3)
    "at" => (At, 2, 2)
    "split" => (Split, 2, 2)
    "join" => (Join, 2, 2)
    "rgb" => (Rgba, 3, 3)
    "rgba" => (Rgba, 4, 4)
    _ => {
      let op = match name {
        "sqrt" => Sqrt
        "log10" => Log10
        "ln" => Ln
        "log2" => Log2
        "sin" => Sin
        "cos" => Cos
        "tan" => Tan
        "asin" => Asin
        "acos" => Acos
        "atan" => Atan
        "round" => Round
        "abs" => Abs
        "ceil" => Ceil
        "floor" => Floor
        "upcase" => Upcase
        "downcase" => Downcase
        "typeof" => TypeOf
        "length" => Length
        "to-rgba" => ToRgba
        _ => return None
      }
      (op, 1, 1)
    }
  }
  Some((op, min, max))
}

///|
/// A GeoJSON source's `clusterProperties` as MapLibre's GeoJSON worker takes them: per
/// key its map expression and reduce expression (an operator's name `op` stands for
/// `[op, ["accumulated"], ["get", key]]`).
pub fn compile_cluster_properties(
  json : Json,
  path~ : String = "",
) -> Array[(String, Expr, Expr)] raise StyleError {
  guard json is Object(o) else { raise Invalid(path~, "not an object") }
  let out = []
  for key, v in o {
    let at = "\{path}.\{key}"
    guard v is Array([operator, map]) else {
      raise Invalid(path=at, "not [operator, map expression]")
    }
    let reduce = match operator {
      String(op) =>
        Json::array([
          Json::string(op),
          Json::array([Json::string("accumulated")]),
          Json::array([Json::string("get"), Json::string(key)]),
        ])
      j => j
    }
    out.push(
      (key, compile(map, path="\{at}[1]"), compile(reduce, path="\{at}[0]")),
    )
  }
  out
}
