///|
/// Value tags past `@core.PROP_STRING` (docs/FORMATS.md "Compiled style").
const VALUE_COLOR : Int32 = 6

///|
const VALUE_LIST : Int32 = 7

///|
const VALUE_FAILED : Int32 = 8

///|
/// Tags of `Expr` variants (docs/FORMATS.md "Compiled style").
const EXPR_LIT : Int32 = 0

///|
const EXPR_GET : Int32 = 1

///|
const EXPR_HAS : Int32 = 2

///|
const EXPR_ID : Int32 = 3

///|
const EXPR_GEOMETRY_TYPE : Int32 = 4

///|
const EXPR_ZOOM : Int32 = 5

///|
const EXPR_LINE_PROGRESS : Int32 = 6

///|
const EXPR_HEATMAP_DENSITY : Int32 = 7

///|
const EXPR_ELEVATION : Int32 = 8

///|
const EXPR_NOT : Int32 = 9

///|
const EXPR_ALL : Int32 = 10

///|
const EXPR_ANY : Int32 = 11

///|
const EXPR_COMPARE : Int32 = 12

///|
const EXPR_IN : Int32 = 13

///|
const EXPR_MATCH : Int32 = 14

///|
const EXPR_CASE : Int32 = 15

///|
const EXPR_COALESCE : Int32 = 16

///|
const EXPR_INTERPOLATE : Int32 = 17

///|
const EXPR_STEP : Int32 = 18

///|
const EXPR_FEATURE_STATE : Int32 = 19

///|
const EXPR_ASSERT : Int32 = 20

///|
const EXPR_COERCE : Int32 = 21

///|
const EXPR_CALL : Int32 = 22

///|
const EXPR_COLLATE : Int32 = 23

///|
const EXPR_WITHIN : Int32 = 24

///|
const EXPR_DISTANCE : Int32 = 25

///|
const EXPR_ACCUMULATED : Int32 = 26

///|
let ops : FixedArray[Op] = [
  Add,
  Sub,
  Mul,
  Div,
  Rem,
  Pow,
  Sqrt,
  Log10,
  Ln,
  Log2,
  Sin,
  Cos,
  Tan,
  Asin,
  Acos,
  Atan,
  Min,
  Max,
  Round,
  Abs,
  Ceil,
  Floor,
  Concat,
  Upcase,
  Downcase,
  TypeOf,
  Length,
  Slice,
  IndexOf,
  At,
  Rgba,
  ToRgba,
  Split,
  Join,
  ResolvedLocale,
  Format,
  NumberFormat,
  Collator,
]

///|
let cmp_ops : FixedArray[CmpOp] = [Eq, Ne, Lt, Le, Gt, Ge]

///|
let layer_kinds : FixedArray[LayerKind] = [
  Background,
  Fill,
  Line,
  Circle,
  Symbol,
  Hillshade,
  FillExtrusion,
  Raster,
  Heatmap,
  ColorRelief,
  Custom,
]

///|
let source_kinds : FixedArray[SourceKind] = [
  Vector,
  GeoJSON,
  RasterDem,
  Raster,
  Image,
]

///|
let placements : FixedArray[SymbolPlacement] = [Point, Line, LineCenter]

///|
let z_orders : FixedArray[SymbolZOrder] = [Auto, ViewportY, Source]

///|
let fits : FixedArray[IconTextFit] = [NoFit, Width, Height, Both]

///|
let joins : FixedArray[Join] = [Miter, Bevel, Round]

///|
let caps : FixedArray[Cap] = [Butt, Square, Round]

///|
let spaces : FixedArray[ColorSpace] = [Rgb, Hcl, Lab]

///|
fn[T : Eq] code_of(table : FixedArray[T], v : T) -> Int32 {
  for i, t in table {
    if t == v {
      return i
    }
  }
  abort("missing from its table")
}
