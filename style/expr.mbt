///|
/// A value an expression produces.
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  Color(Color)
  List(Array[Value])
} derive(Debug, Eq)

///|
pub(all) enum CmpOp {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Debug, Eq)

///|
/// How `interpolate` blends between stops; `Exponential(1.0)` is linear.
pub(all) enum Interpolation {
  Exponential(Double)
} derive(Debug, Eq)

///|
/// A compiled MapLibre expression (the subset this engine supports).
pub(all) enum Expr {
  Lit(Value)
  Get(String)
  Has(String)
  GeometryType
  Zoom
  Not(Expr)
  All(Array[Expr])
  Any(Array[Expr])
  Compare(CmpOp, Expr, Expr)
  In(Expr, Expr)
  Match(Expr, Array[(Array[Value], Expr)], Expr)
  Case(Array[(Expr, Expr)], Expr)
  Coalesce(Array[Expr])
  Interpolate(Interpolation, Expr, Array[(Double, Expr)])
  Step(Expr, Expr, Array[(Double, Expr)])
} derive(Debug, Eq)

///|
/// What a compiled expression must produce. `Color` turns string literals
/// into colors at compile time, as MapLibre does for color properties.
pub(all) enum Expected {
  AnyType
  ColorType
  NumberType
  BoolType
} derive(Debug, Eq)

///|

///|
/// Deepest nesting of expressions and literal arrays a style may use; deeper
/// input is rejected instead of recursing without bound.
pub const MAX_EXPR_DEPTH : Int32 = 32

///|
fn json_value(
  json : Json,
  path : String,
  depth~ : Int32 = 0,
) -> Value raise StyleError {
  if depth > MAX_EXPR_DEPTH {
    raise Invalid(path~, "nested deeper than \{MAX_EXPR_DEPTH}")
  }
  match json {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Num(n)
    String(s) => Str(s)
    Array(items) =>
      List(
        items.mapi((i, j) => json_value(j, "\{path}[\{i}]", depth=depth + 1)),
      )
    Object(_) => raise Unsupported(path~, "object values")
  }
}

///|
fn literal(
  value : Value,
  expected : Expected,
  path : String,
) -> Expr raise StyleError {
  match (expected, value) {
    (ColorType, Str(s)) =>
      match parse_color(s) {
        Some(c) => Lit(Color(c))
        None => raise Invalid(path~, "not a color: \{s}")
      }
    _ => Lit(value)
  }
}

///|
fn args_of(
  items : Array[Json],
  n : Int32,
  path : String,
) -> Unit raise StyleError {
  if items.length() != n + 1 {
    raise Invalid(path~, "expected \{n} arguments")
  }
}

///|
fn key_of(json : Json, path : String) -> String raise StyleError {
  match json {
    String(s) => s
    _ => raise Unsupported(path~, "only literal property names")
  }
}

///|
/// Compiles a MapLibre expression (or a plain literal) from JSON.
pub fn compile(
  json : Json,
  expected~ : Expected = AnyType,
  path~ : String = "",
) -> Expr raise StyleError {
  compile_at(json, expected, path, 0)
}

///|
fn compile_at(
  json : Json,
  expected : Expected,
  path : String,
  depth : Int32,
) -> Expr raise StyleError {
  if depth > MAX_EXPR_DEPTH {
    raise Invalid(path~, "nested deeper than \{MAX_EXPR_DEPTH}")
  }
  guard json is Array(items) && items.length() > 0 && items[0] is String(op) else {
    return match json {
      Array(_) =>
        raise Invalid(
          path~,
          "an array literal must be wrapped in [\"literal\", ...]",
        )
      _ => literal(json_value(json, path, depth~), expected, path)
    }
  }
  let arg = (i : Int32, e : Expected) => {
    compile_at(items[i], e, "\{path}[\{i}]", depth + 1)
  }
  match op {
    "literal" => {
      args_of(items, 1, path)
      literal(json_value(items[1], "\{path}[1]", depth~), expected, path)
    }
    "get" | "has" => {
      if items.length() != 2 {
        raise Unsupported(path~, "\{op} with an object argument")
      }
      let key = key_of(items[1], "\{path}[1]")
      if op == "get" {
        Get(key)
      } else {
        Has(key)
      }
    }
    "geometry-type" => GeometryType
    "zoom" => Zoom
    "!" => {
      args_of(items, 1, path)
      Not(arg(1, BoolType))
    }
    "all" | "any" => {
      let parts = []
      for i in 1..<items.length() {
        parts.push(arg(i, BoolType))
      }
      if op == "all" {
        All(parts)
      } else {
        Any(parts)
      }
    }
    "==" | "!=" | "<" | "<=" | ">" | ">=" => {
      args_of(items, 2, path)
      let cmp = match op {
        "==" => CmpOp::Eq
        "!=" => Ne
        "<" => Lt
        "<=" => Le
        ">" => Gt
        _ => Ge
      }
      Compare(cmp, arg(1, AnyType), arg(2, AnyType))
    }
    "in" => {
      args_of(items, 2, path)
      In(arg(1, AnyType), arg(2, AnyType))
    }
    "match" => {
      if items.length() < 5 || items.length() % 2 == 0 {
        raise Invalid(
          path~,
          "match needs input, label/output pairs and a fallback",
        )
      }
      let cases = []
      for i = 2; i < items.length() - 1; i = i + 2 {
        let labels = match json_value(items[i], "\{path}[\{i}]", depth~) {
          List(ls) => ls
          v => [v]
        }
        cases.push((labels, arg(i + 1, expected)))
      }
      Match(arg(1, AnyType), cases, arg(items.length() - 1, expected))
    }
    "case" => {
      if items.length() < 4 || items.length() % 2 == 1 {
        raise Invalid(path~, "case needs condition/output pairs and a fallback")
      }
      let cases = []
      for i = 1; i < items.length() - 1; i = i + 2 {
        cases.push((arg(i, BoolType), arg(i + 1, expected)))
      }
      Case(cases, arg(items.length() - 1, expected))
    }
    "coalesce" => {
      let parts = []
      for i in 1..<items.length() {
        parts.push(arg(i, expected))
      }
      Coalesce(parts)
    }
    "interpolate" => {
      if items.length() < 5 || items.length() % 2 == 0 {
        raise Invalid(
          path~,
          "interpolate needs a type, an input and stop/output pairs",
        )
      }
      let interp = match items[1] {
        Array([String("linear")]) => Exponential(1.0)
        Array([String("exponential"), Number(base, ..)]) => Exponential(base)
        _ =>
          raise Unsupported(
            path="\{path}[1]",
            "only linear and exponential interpolation",
          )
      }
      Interpolate(
        interp,
        arg(2, NumberType),
        stops(items, 3, expected, path, depth),
      )
    }
    "step" => {
      if items.length() < 3 || items.length() % 2 == 0 {
        raise Invalid(
          path~,
          "step needs an input, a first output and stop/output pairs",
        )
      }
      Step(
        arg(1, NumberType),
        arg(2, expected),
        stops(items, 3, expected, path, depth),
      )
    }
    _ => raise Unsupported(path~, "expression \{op}")
  }
}

///|
/// Stop/output pairs from `items[from..]`, with strictly increasing stops.
fn stops(
  items : Array[Json],
  from : Int32,
  expected : Expected,
  path : String,
  depth : Int32,
) -> Array[(Double, Expr)] raise StyleError {
  let out : Array[(Double, Expr)] = []
  for i = from; i + 1 < items.length(); i = i + 2 {
    guard items[i] is Number(stop, ..) else {
      raise Invalid(path="\{path}[\{i}]", "stops must be number literals")
    }
    if out.length() > 0 && stop <= out[out.length() - 1].0 {
      raise Invalid(path="\{path}[\{i}]", "stops must increase")
    }
    out.push(
      (stop, compile_at(items[i + 1], expected, "\{path}[\{i + 1}]", depth + 1)),
    )
  }
  out
}
