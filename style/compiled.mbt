///|
/// Value tags past `@core.PROP_STRING` (docs/FORMATS.md "Compiled style").
const VALUE_COLOR : Int32 = 6

///|
const VALUE_LIST : Int32 = 7

///|
const VALUE_FAILED : Int32 = 8

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
let anchors : FixedArray[TextAnchor] = [
  Center,
  Left,
  Right,
  Top,
  Bottom,
  TopLeft,
  TopRight,
  BottomLeft,
  BottomRight,
]

///|
let justifies : FixedArray[TextJustify] = [Auto, Left, Center, Right]

///|
let placements : FixedArray[SymbolPlacement] = [Point, Line, LineCenter]

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

///|
/// The writer of docs/FORMATS.md "Compiled style".
priv struct StyleWriter {
  w : @core.ByteWriter
}

///|
fn StyleWriter::code(self : StyleWriter, v : Int32) -> Unit {
  self.w.u8(v)
}

///|
fn StyleWriter::flag(self : StyleWriter, b : Bool) -> Unit {
  self.w.u8(if b { 1 } else { 0 })
}

///|
fn StyleWriter::value(self : StyleWriter, v : Value) -> Unit {
  match v {
    Null => self.code(@core.PROP_NULL)
    Bool(b) => self.code(if b { @core.PROP_TRUE } else { @core.PROP_FALSE })
    Num(n) => {
      self.code(@core.PROP_NUMBER)
      self.w.f64(n)
    }
    Str(s) => {
      self.code(@core.PROP_STRING)
      self.w.utf8(s)
    }
    Color(c) => {
      self.code(VALUE_COLOR)
      self.w.f64(c.r)
      self.w.f64(c.g)
      self.w.f64(c.b)
      self.w.f64(c.a)
    }
    List(vs) => {
      self.code(VALUE_LIST)
      self.w.u32(vs.length())
      vs.each(v => self.value(v))
    }
    Failed => self.code(VALUE_FAILED)
  }
}

///|
fn StyleWriter::expected(self : StyleWriter, e : Expected) -> Unit {
  match e {
    AnyType => self.code(0)
    ColorType => self.code(1)
    NumberType => self.code(2)
    BoolType => self.code(3)
    StringType => self.code(4)
    ArrayOf(item, n) => {
      self.code(5)
      self.expected(item)
      self.w.u32(n)
    }
  }
}

///|
fn StyleWriter::exprs(self : StyleWriter, es : Array[Expr]) -> Unit {
  self.w.u32(es.length())
  es.each(e => self.expr(e))
}

///|
fn StyleWriter::stops(
  self : StyleWriter,
  stops : Array[(Double, Expr)],
) -> Unit {
  self.w.u32(stops.length())
  for s in stops {
    self.w.f64(s.0)
    self.expr(s.1)
  }
}

///|
fn StyleWriter::expr(self : StyleWriter, e : Expr) -> Unit {
  match e {
    Lit(v) => {
      self.code(0)
      self.value(v)
    }
    Get(k) => {
      self.code(1)
      self.w.utf8(k)
    }
    Has(k) => {
      self.code(2)
      self.w.utf8(k)
    }
    Id => self.code(3)
    GeometryType => self.code(4)
    Zoom => self.code(5)
    LineProgress => self.code(6)
    HeatmapDensity => self.code(7)
    Elevation => self.code(8)
    Not(a) => {
      self.code(9)
      self.expr(a)
    }
    All(es) => {
      self.code(10)
      self.exprs(es)
    }
    Any(es) => {
      self.code(11)
      self.exprs(es)
    }
    Compare(op, a, b) => {
      self.code(12)
      self.code(code_of(cmp_ops, op))
      self.expr(a)
      self.expr(b)
    }
    In(a, b) => {
      self.code(13)
      self.expr(a)
      self.expr(b)
    }
    Match(input, arms, other) => {
      self.code(14)
      self.expr(input)
      self.w.u32(arms.length())
      for arm in arms {
        self.w.u32(arm.0.length())
        arm.0.each(v => self.value(v))
        self.expr(arm.1)
      }
      self.expr(other)
    }
    Case(arms, other) => {
      self.code(15)
      self.w.u32(arms.length())
      for arm in arms {
        self.expr(arm.0)
        self.expr(arm.1)
      }
      self.expr(other)
    }
    Coalesce(es) => {
      self.code(16)
      self.exprs(es)
    }
    Interpolate(how, space, input, stops) => {
      self.code(17)
      match how {
        Exponential(base) => {
          self.code(0)
          self.w.f64(base)
        }
        CubicBezier(a, b, c, d) => {
          self.code(1)
          self.w.f64(a)
          self.w.f64(b)
          self.w.f64(c)
          self.w.f64(d)
        }
      }
      self.code(code_of(spaces, space))
      self.expr(input)
      self.stops(stops)
    }
    Step(input, first, stops) => {
      self.code(18)
      self.expr(input)
      self.expr(first)
      self.stops(stops)
    }
    FeatureState(k) => {
      self.code(19)
      self.w.utf8(k)
    }
    Assert(t, es) => {
      self.code(20)
      self.expected(t)
      self.exprs(es)
    }
    Coerce(t, es) => {
      self.code(21)
      self.expected(t)
      self.exprs(es)
    }
    Call(op, es) => {
      self.code(22)
      self.code(code_of(ops, op))
      self.exprs(es)
    }
  }
}

///|
fn StyleWriter::opt_expr(self : StyleWriter, e : Expr?) -> Unit {
  match e {
    None => self.flag(false)
    Some(e) => {
      self.flag(true)
      self.expr(e)
    }
  }
}

///|
fn StyleWriter::pair(self : StyleWriter, p : (Double, Double)) -> Unit {
  self.w.f64(p.0)
  self.w.f64(p.1)
}

///|
fn StyleWriter::sides(
  self : StyleWriter,
  p : (Double, Double, Double, Double),
) -> Unit {
  self.w.f64(p.0)
  self.w.f64(p.1)
  self.w.f64(p.2)
  self.w.f64(p.3)
}

///|
fn StyleWriter::text(self : StyleWriter, t : TextLayout) -> Unit {
  self.exprs(t.field)
  self.expr(t.size)
  self.code(code_of(placements, t.placement))
  self.w.f64(t.spacing)
  self.w.f64(t.max_angle)
  self.flag(t.keep_upright)
  self.code(code_of(anchors, t.anchor))
  self.pair(t.offset)
  self.code(code_of(justifies, t.justify))
  self.w.u32(t.variable.length())
  for v in t.variable {
    self.code(code_of(anchors, v.0))
    self.w.f64(v.1)
    self.w.f64(v.2)
  }
  self.w.f64(t.max_width)
  self.w.f64(t.line_height)
  self.w.f64(t.padding)
  self.flag(t.allow_overlap)
  self.flag(t.ignore_placement)
  self.flag(t.vertical)
  self.opt_expr(t.sort_key)
}

///|
fn StyleWriter::icon(self : StyleWriter, i : IconLayout) -> Unit {
  self.exprs(i.image)
  self.expr(i.size)
  self.expr(i.rotate)
  self.code(code_of(anchors, i.anchor))
  self.pair(i.offset)
  self.sides(i.padding)
  for
    b in [
      i.allow_overlap,
      i.ignore_placement,
      i.optional,
      i.text_optional,
      i.rotate_with_map,
      i.pitch_with_map,
      i.keep_upright,
    ] {
    self.flag(b)
  }
  self.code(code_of(fits, i.text_fit))
  self.sides(i.text_fit_padding)
}

///|
fn[T] StyleWriter::opt(self : StyleWriter, v : T?, write : (T) -> Unit) -> Unit {
  match v {
    None => self.flag(false)
    Some(v) => {
      self.flag(true)
      write(v)
    }
  }
}

///|
fn StyleWriter::layer(self : StyleWriter, l : StyleLayer) -> Unit {
  self.w.utf8(l.id)
  self.code(code_of(layer_kinds, l.kind))
  self.w.utf8(l.source)
  self.w.utf8(l.source_layer)
  self.w.f64(l.min_zoom)
  self.w.f64(l.max_zoom)
  self.opt_expr(l.filter)
  self.w.u32(l.filter_id)
  for
    e in [
      l.color,
      l.opacity,
      l.width,
      l.radius,
      l.stroke_width,
      l.stroke_color,
      l.stroke_opacity,
      l.halo_color,
      l.halo_width,
    ] {
    self.expr(e)
  }
  self.opt(l.text, t => self.text(t))
  self.opt(l.icon, i => self.icon(i))
  self.opt(l.icon_paint, p => self.exprs(p.exprs()))
  self.opt(l.extrusion, x => {
    self.expr(x.height)
    self.expr(x.base)
    self.flag(x.vertical_gradient)
  })
  self.opt(l.heatmap, h => self.exprs([h.weight, h.intensity, h.color]))
  self.code(code_of(joins, l.join))
  self.code(code_of(caps, l.cap))
  self.w.f64(l.miter_limit)
  self.w.f64(l.round_limit)
  self.flag(l.antialias)
  self.opt_expr(l.outline_color)
  self.opt_expr(l.dasharray)
  self.opt_expr(l.gradient)
  self.opt_expr(l.pattern)
}

///|
fn StyleWriter::source(self : StyleWriter, s : Source) -> Unit {
  self.w.utf8(s.id)
  self.code(code_of(source_kinds, s.kind))
  self.w.u32(s.min_zoom)
  self.w.u32(s.max_zoom)
  self.w.u32(s.tile_size)
  match s.encoding {
    Mapbox => self.code(0)
    Terrarium => self.code(1)
    Gsi => self.code(2)
    Custom(r, g, b, base) => {
      self.code(3)
      self.sides((r, g, b, base))
    }
  }
  self.w.u32(s.buffer)
  self.w.f64(s.tolerance)
  match s.promote_id {
    FeatureId => self.code(0)
    Property(p) => {
      self.code(1)
      self.w.utf8(p)
    }
    ByLayer(m) => {
      self.code(2)
      self.w.u32(m.length())
      for k, v in m {
        self.w.utf8(k)
        self.w.utf8(v)
      }
    }
  }
}

///|
/// Writes `e` (None as a 0 byte) in docs/FORMATS.md "Compiled style"'s form,
/// for `read_expr`.
pub fn write_expr(w : @core.ByteWriter, e : Expr?) -> Unit {
  ({ w, } : StyleWriter).opt_expr(e)
}

///|
/// The style as display workers take it (docs/FORMATS.md "Compiled style"):
/// what tiles are made from, without the paint only the main thread draws.
pub fn Style::to_compiled(self : Style) -> Bytes {
  let out : StyleWriter = { w: @core.ByteWriter::new(), }
  out.w.u32(self.sources.length())
  self.sources.each(s => out.source(s))
  out.w.u32(self.layers.length())
  self.layers.each(l => out.layer(l))
  out.w.to_bytes()
}

///|
/// The reader of docs/FORMATS.md "Compiled style": `left` counts the nodes the
/// current expression may still have (`MAX_EXPR_NODES`).
priv struct StyleReader {
  r : @core.ByteReader
  mut left : Int32
}

///|
/// A count of items of at least one byte each; 0 (and the reader failed) past
/// what is left.
fn StyleReader::count(self : StyleReader) -> Int32 {
  let n = self.r.u32()
  if n < 0 || n > self.r.remaining() {
    self.r.fail()
    return 0
  }
  n
}

///|
fn[T] StyleReader::from(
  self : StyleReader,
  table : FixedArray[T],
  default : T,
) -> T {
  let i = self.r.u8()
  if i < table.length() {
    table[i]
  } else {
    self.r.fail()
    default
  }
}

///|
fn StyleReader::flag(self : StyleReader) -> Bool {
  match self.r.u8() {
    0 => false
    1 => true
    _ => {
      self.r.fail()
      false
    }
  }
}

///|
fn[T] StyleReader::list(self : StyleReader, item : () -> T) -> Array[T] {
  let n = self.count()
  let out = Array(capacity=n)
  for _ in 0..<n {
    guard self.r.ok() else { break }
    out.push(item())
  }
  out
}

///|
fn StyleReader::spend(self : StyleReader, depth : Int32) -> Bool {
  self.left -= 1
  if self.left < 0 || depth > 4 * MAX_EXPR_DEPTH {
    self.r.fail()
    return false
  }
  self.r.ok()
}

///|
fn StyleReader::value(self : StyleReader, depth : Int32) -> Value {
  guard self.spend(depth) else { return Null }
  match self.r.u8() {
    @core.PROP_NULL => Null
    @core.PROP_FALSE => Bool(false)
    @core.PROP_TRUE => Bool(true)
    @core.PROP_NUMBER => Num(self.r.f64())
    @core.PROP_STRING => Str(self.r.utf8())
    VALUE_COLOR => {
      let r = self.r.f64()
      let g = self.r.f64()
      let b = self.r.f64()
      Color({ r, g, b, a: self.r.f64(), })
    }
    VALUE_LIST => List(self.list(() => self.value(depth + 1)))
    VALUE_FAILED => Failed
    _ => {
      self.r.fail()
      Null
    }
  }
}

///|
fn StyleReader::expected(self : StyleReader, depth : Int32) -> Expected {
  match self.r.u8() {
    0 => AnyType
    1 => ColorType
    2 => NumberType
    3 => BoolType
    4 => StringType
    5 if depth <= MAX_EXPR_DEPTH => {
      let item = self.expected(depth + 1)
      ArrayOf(item, self.r.u32())
    }
    _ => {
      self.r.fail()
      AnyType
    }
  }
}

///|
fn StyleReader::stops(
  self : StyleReader,
  depth : Int32,
) -> Array[(Double, Expr)] {
  self.list(() => {
    let z = self.r.f64()
    (z, self.expr(depth))
  })
}

///|
fn StyleReader::expr(self : StyleReader, depth : Int32) -> Expr {
  guard self.spend(depth) else { return Lit(Null) }
  let d = depth + 1
  let exprs = () => self.list(() => self.expr(d))
  match self.r.u8() {
    0 => Lit(self.value(d))
    1 => Get(self.r.utf8())
    2 => Has(self.r.utf8())
    3 => Id
    4 => GeometryType
    5 => Zoom
    6 => LineProgress
    7 => HeatmapDensity
    8 => Elevation
    9 => Not(self.expr(d))
    10 => All(exprs())
    11 => Any(exprs())
    12 => {
      let op = self.from(cmp_ops, Eq)
      let a = self.expr(d)
      Compare(op, a, self.expr(d))
    }
    13 => {
      let a = self.expr(d)
      In(a, self.expr(d))
    }
    14 => {
      let input = self.expr(d)
      let arms = self.list(() => {
        let labels = self.list(() => self.value(d))
        (labels, self.expr(d))
      })
      Match(input, arms, self.expr(d))
    }
    15 => {
      let arms = self.list(() => {
        let cond = self.expr(d)
        (cond, self.expr(d))
      })
      Case(arms, self.expr(d))
    }
    16 => Coalesce(exprs())
    17 => {
      let how = match self.r.u8() {
        0 => Exponential(self.r.f64())
        1 => {
          let a = self.r.f64()
          let b = self.r.f64()
          let c = self.r.f64()
          CubicBezier(a, b, c, self.r.f64())
        }
        _ => {
          self.r.fail()
          Exponential(1.0)
        }
      }
      let space = self.from(spaces, Rgb)
      let input = self.expr(d)
      Interpolate(how, space, input, self.stops(d))
    }
    18 => {
      let input = self.expr(d)
      let first = self.expr(d)
      Step(input, first, self.stops(d))
    }
    19 => FeatureState(self.r.utf8())
    20 => {
      let t = self.expected(0)
      Assert(t, exprs())
    }
    21 => {
      let t = self.expected(0)
      Coerce(t, exprs())
    }
    22 => {
      let op = self.from(ops, Add)
      Call(op, exprs())
    }
    _ => {
      self.r.fail()
      Lit(Null)
    }
  }
}

///|
/// A whole expression, with its own node budget.
fn StyleReader::top(self : StyleReader) -> Expr {
  self.left = MAX_EXPR_NODES
  self.expr(0)
}

///|
fn StyleReader::opt_expr(self : StyleReader) -> Expr? {
  if self.flag() {
    Some(self.top())
  } else {
    None
  }
}

///|
fn StyleReader::exprs(self : StyleReader) -> Array[Expr] {
  self.list(() => self.top())
}

///|
fn[T] StyleReader::opt(self : StyleReader, read : () -> T) -> T? {
  if self.flag() {
    Some(read())
  } else {
    None
  }
}

///|
fn StyleReader::pair(self : StyleReader) -> (Double, Double) {
  let a = self.r.f64()
  (a, self.r.f64())
}

///|
fn StyleReader::sides(self : StyleReader) -> (Double, Double, Double, Double) {
  let a = self.r.f64()
  let b = self.r.f64()
  let c = self.r.f64()
  (a, b, c, self.r.f64())
}

///|
fn StyleReader::text(self : StyleReader) -> TextLayout {
  let field = self.exprs()
  let size = self.top()
  let placement = self.from(placements, Point)
  let spacing = self.r.f64()
  let max_angle = self.r.f64()
  let keep_upright = self.flag()
  let anchor = self.from(anchors, Center)
  let offset = self.pair()
  let justify = self.from(justifies, Center)
  let variable = self.list(() => {
    let a = self.from(anchors, Center)
    let x = self.r.f64()
    (a, x, self.r.f64())
  })
  let max_width = self.r.f64()
  let line_height = self.r.f64()
  let padding = self.r.f64()
  let allow_overlap = self.flag()
  let ignore_placement = self.flag()
  let vertical = self.flag()
  {
    field,
    size,
    placement,
    spacing,
    max_angle,
    keep_upright,
    anchor,
    offset,
    justify,
    variable,
    max_width,
    line_height,
    padding,
    allow_overlap,
    ignore_placement,
    vertical,
    sort_key: self.opt_expr(),
  }
}

///|
fn StyleReader::icon(self : StyleReader) -> IconLayout {
  let image = self.exprs()
  let size = self.top()
  let rotate = self.top()
  let anchor = self.from(anchors, Center)
  let offset = self.pair()
  let padding = self.sides()
  let allow_overlap = self.flag()
  let ignore_placement = self.flag()
  let optional = self.flag()
  let text_optional = self.flag()
  let rotate_with_map = self.flag()
  let pitch_with_map = self.flag()
  let keep_upright = self.flag()
  let text_fit = self.from(fits, NoFit)
  {
    layout: Json::null(),
    image,
    size,
    rotate,
    anchor,
    offset,
    padding,
    allow_overlap,
    ignore_placement,
    optional,
    text_optional,
    rotate_with_map,
    pitch_with_map,
    keep_upright,
    text_fit,
    text_fit_padding: self.sides(),
  }
}

///|
/// `IconPaint::exprs`, in its order.
fn StyleReader::icon_paint(self : StyleReader) -> IconPaint {
  let es = self.exprs()
  guard es is [color, opacity, halo_color, halo_width, halo_blur] else {
    self.r.fail()
    let none = Lit(Null)
    return {
      color: none,
      opacity: none,
      halo_color: none,
      halo_width: none,
      halo_blur: none,
    }
  }
  { color, opacity, halo_color, halo_width, halo_blur, }
}

///|
fn StyleReader::heatmap(self : StyleReader) -> HeatmapPaint {
  let es = self.exprs()
  guard es is [weight, intensity, color] else {
    self.r.fail()
    return { weight: Lit(Null), intensity: Lit(Null), color: Lit(Null), }
  }
  { weight, intensity, color, }
}

///|
fn StyleReader::layer(self : StyleReader) -> StyleLayer {
  let id = self.r.utf8()
  let kind = self.from(layer_kinds, Background)
  let source = self.r.utf8()
  let source_layer = self.r.utf8()
  let min_zoom = self.r.f64()
  let max_zoom = self.r.f64()
  let filter = self.opt_expr()
  let filter_id = self.r.u32()
  let color = self.top()
  let opacity = self.top()
  let width = self.top()
  let radius = self.top()
  let stroke_width = self.top()
  let stroke_color = self.top()
  let stroke_opacity = self.top()
  let halo_color = self.top()
  let halo_width = self.top()
  let text = self.opt(() => self.text())
  let icon = self.opt(() => self.icon())
  let icon_paint = self.opt(() => self.icon_paint())
  let extrusion = self.opt(() => {
    let height = self.top()
    let base = self.top()
    { height, base, vertical_gradient: self.flag(), }
  })
  let heatmap = self.opt(() => self.heatmap())
  let join = self.from(joins, Miter)
  let cap = self.from(caps, Butt)
  let miter_limit = self.r.f64()
  let round_limit = self.r.f64()
  let antialias = self.flag()
  let outline_color = self.opt_expr()
  let dasharray = self.opt_expr()
  let gradient = self.opt_expr()
  {
    id,
    kind,
    source,
    source_layer,
    min_zoom,
    max_zoom,
    filter,
    filter_id,
    color,
    opacity,
    width,
    radius,
    stroke_width,
    stroke_color,
    stroke_opacity,
    halo_color,
    halo_width,
    text,
    icon,
    icon_paint,
    hillshade: None,
    relief: None,
    extrusion,
    raster: None,
    heatmap,
    join,
    cap,
    miter_limit,
    round_limit,
    antialias,
    outline_color,
    dasharray,
    gradient,
    pattern: self.opt_expr(),
  }
}

///|
fn StyleReader::source(self : StyleReader) -> Source {
  let id = self.r.utf8()
  let kind = self.from(source_kinds, Vector)
  let min_zoom = self.r.u32()
  let max_zoom = self.r.u32()
  let tile_size = self.r.u32()
  let encoding = match self.r.u8() {
    0 => Mapbox
    1 => Terrarium
    2 => Gsi
    3 => {
      let (r, g, b, base) = self.sides()
      Custom(r, g, b, base)
    }
    _ => {
      self.r.fail()
      Mapbox
    }
  }
  let buffer = self.r.u32()
  let tolerance = self.r.f64()
  let promote_id = match self.r.u8() {
    0 => FeatureId
    1 => Property(self.r.utf8())
    2 => {
      let m = Map([])
      for _ in 0..<self.count() {
        guard self.r.ok() else { break }
        let k = self.r.utf8()
        m.set(k, self.r.utf8())
      }
      ByLayer(m)
    }
    _ => {
      self.r.fail()
      FeatureId
    }
  }
  {
    id,
    kind,
    tiles: [],
    min_zoom,
    max_zoom,
    tile_size,
    encoding,
    buffer,
    tolerance,
    promote_id,
    bounds: None,
    tms: false,
  }
}

///|
/// Reads `write_expr`'s form; `r` fails when it is malformed.
pub fn read_expr(r : @core.ByteReader) -> Expr? {
  ({ r, left: 0, } : StyleReader).opt_expr()
}

///|
/// Reads `Style::to_compiled`'s bytes. Sources lack their tile URLs, bounds and
/// scheme, layers their main-thread paint (hillshade, color relief, raster) and
/// icon `layout`, and the style its terrain, sky, light and warnings.
pub fn Style::from_compiled(bytes : BytesView) -> Style raise StyleError {
  let i : StyleReader = { r: @core.ByteReader::new(bytes), left: 0, }
  let sources = i.list(() => i.source())
  let layers = i.list(() => i.layer())
  guard i.r.done() else { raise Invalid(path="", "malformed compiled style") }
  {
    sources,
    layers,
    terrain: None,
    sky: None,
    light: {
      viewport: true,
      color: Lit(Null),
      intensity: Lit(Null),
      position: (0.0, 0.0, 0.0),
    },
    warnings: [],
  }
}
