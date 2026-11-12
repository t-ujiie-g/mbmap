///|
/// A value an expression produces. `Failed` is MapLibre's runtime error: it goes up through
/// the expressions above it, and a property takes its default. `Collator` holds a
/// collator's case and diacritic sensitivity and locale.
#derive(Debug, Eq)
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
}

///|
/// A section of `format`'s text (MapLibre's `FormattedSection`): `font` is its
/// `text-font` joined by commas, `align` its `vertical-align`; None where the
/// section has no such option.
#derive(Debug, Eq)
pub(all) struct Section {
  text : String
  scale : Double?
  font : String?
  color : Color?
  align : String?
}

///|
/// The comparison operators `==`, `!=`, `<`, `<=`, `>` and `>=`.
#derive(Debug, Eq)
pub(all) enum CmpOp {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
}

///|
/// How `interpolate` blends between stops: `Exponential(1.0)` is linear,
/// `CubicBezier` takes the curve's two control points.
#derive(Debug, Eq)
pub(all) enum Interpolation {
  Exponential(Double)
  CubicBezier(Double, Double, Double, Double)
}

///|
/// The color space `interpolate` (`Rgb`), `interpolate-hcl` and
/// `interpolate-lab` blend colors in.
#derive(Debug, Eq)
pub(all) enum ColorSpace {
  Rgb
  Hcl
  Lab
}

///|
/// The operators with fixed arguments (`-` with one argument negates). `Format` takes per
/// section its text, `font-scale`, `text-font`, `text-color` and `vertical-align`, and
/// `NumberFormat` and `Collator` their options in order; `Lit(Null)` where one is not given.
#derive(Debug, Eq)
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
}

///|
/// A compiled MapLibre expression (the subset this engine supports). Compiling resolves `let`,
/// `var` and `global-state` (its value in the style's `state`); `Collate` compares with the
/// collator last, `Within` holds polygons as rings of longitude, latitude pairs.
#derive(Debug, Eq)
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
}

///|
/// A type an expression produces or must produce: `AnyType` is MapLibre's
/// `value`, `ArrayOf(item, n)` an array (`n` -1 for any length); `compile`
/// annotates for it as MapLibre's parser does.
#derive(Debug, Eq)
pub(all) enum Expected {
  AnyType
  ColorType
  NumberType
  BoolType
  StringType
  ArrayOf(Expected, Int32)
}

///|
/// Deepest nesting of expressions and literal arrays a style may use; deeper
/// input is rejected instead of recursing without bound.
pub const MAX_EXPR_DEPTH : Int32 = 32

///|
/// Most nodes a compiled expression may have once its `var`s are replaced by
/// what they are bound to, which keeps evaluation bounded.
pub const MAX_EXPR_NODES : Int32 = 4096
