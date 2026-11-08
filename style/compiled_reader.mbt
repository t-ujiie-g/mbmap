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
  // Sized as the bytes say only up to a point: every nesting level reserves its own.
  let out = Array(capacity=@cmp.minimum(n, 64))
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
    EXPR_LIT => Lit(self.value(d))
    EXPR_GET => Get(self.r.utf8())
    EXPR_HAS => Has(self.r.utf8())
    EXPR_ID => Id
    EXPR_GEOMETRY_TYPE => GeometryType
    EXPR_ZOOM => Zoom
    EXPR_LINE_PROGRESS => LineProgress
    EXPR_HEATMAP_DENSITY => HeatmapDensity
    EXPR_ELEVATION => Elevation
    EXPR_NOT => Not(self.expr(d))
    EXPR_ALL => All(exprs())
    EXPR_ANY => Any(exprs())
    EXPR_COMPARE => {
      let op = self.from(cmp_ops, Eq)
      let a = self.expr(d)
      Compare(op, a, self.expr(d))
    }
    EXPR_IN => {
      let a = self.expr(d)
      In(a, self.expr(d))
    }
    EXPR_MATCH => {
      let input = self.expr(d)
      let arms = self.list(() => {
        let labels = self.list(() => self.value(d))
        (labels, self.expr(d))
      })
      Match(input, arms, self.expr(d))
    }
    EXPR_CASE => {
      let arms = self.list(() => {
        let cond = self.expr(d)
        (cond, self.expr(d))
      })
      Case(arms, self.expr(d))
    }
    EXPR_COALESCE => Coalesce(exprs())
    EXPR_INTERPOLATE => {
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
      let stops = self.stops(d)
      // Evaluation reads the first stop.
      if stops.is_empty() {
        self.r.fail()
      }
      Interpolate(how, space, input, stops)
    }
    EXPR_STEP => {
      let input = self.expr(d)
      let first = self.expr(d)
      Step(input, first, self.stops(d))
    }
    EXPR_FEATURE_STATE => FeatureState(self.r.utf8())
    EXPR_ASSERT => {
      let t = self.expected(0)
      Assert(t, exprs())
    }
    EXPR_COERCE => {
      let t = self.expected(0)
      Coerce(t, exprs())
    }
    EXPR_CALL => {
      let op = self.from(ops, Add)
      let args = exprs()
      if !arity_fits(op, args.length()) {
        self.r.fail()
      }
      Call(op, args)
    }
    EXPR_COLLATE => {
      let op = self.from(cmp_ops, Eq)
      let a = self.expr(d)
      let b = self.expr(d)
      Collate(op, a, b, self.expr(d))
    }
    EXPR_WITHIN => Within(self.list(() => self.rings()))
    EXPR_ACCUMULATED => Accumulated
    EXPR_DISTANCE =>
      Distance(
        self.list(() => {
          match self.r.u8() {
            0 => {
              let x = self.r.f64()
              Shape::Point(x, self.r.f64())
            }
            1 => Line(self.coords())
            2 => Polygon(self.rings())
            3 => Other
            _ => {
              self.r.fail()
              Other
            }
          }
        }),
      )
    _ => {
      self.r.fail()
      Lit(Null)
    }
  }
}

///|
/// Longitude, latitude pairs: an even count, the first pair always there, as
/// `compile` takes positions.
fn StyleReader::coords(self : StyleReader) -> Array[Double] {
  let c = self.list(() => self.r.f64())
  if c.length() == 0 || c.length() % 2 != 0 {
    self.r.fail()
  }
  c
}

///|
/// A polygon's rings: at least one.
fn StyleReader::rings(self : StyleReader) -> Array[Array[Double]] {
  let rings = self.list(() => self.coords())
  if rings.length() == 0 {
    self.r.fail()
  }
  rings
}

///|
/// Reads what `write_cluster_properties` wrote; None if malformed or followed by more.
pub fn read_cluster_properties(
  bytes : BytesView,
) -> Array[(String, Expr, Expr)]? {
  let r = StyleReader::{ r: @core.ByteReader::new(bytes), left: 0, }
  let props = r.list(() => {
    let key = r.r.utf8()
    let map = r.top()
    (key, map, r.top())
  })
  if r.r.done() {
    Some(props)
  } else {
    None
  }
}

///|
/// Whether `op` takes `n` arguments, as `compile` makes its calls.
fn arity_fits(op : Op, n : Int32) -> Bool {
  match op {
    Add | Mul | Min | Max | Concat => true
    Sub => n is (1 | 2)
    Div | Rem | Pow | At | Split | Join => n == 2
    Slice | IndexOf => n is (2 | 3)
    Rgba => n is (3 | 4)
    Format => n > 0 && n % 5 == 0
    NumberFormat => n == 6
    Collator => n == 3
    _ => n == 1
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
fn StyleReader::anchors(
  self : StyleReader,
) -> Array[(TextAnchor, Double, Double)] {
  self.list(() => {
    let a = self.from(anchor_values, Center)
    let x = self.r.f64()
    (a, x, self.r.f64())
  })
}

///|
fn StyleReader::text(self : StyleReader) -> TextLayout {
  let field = self.exprs()
  let size = self.top()
  let placement = self.from(placements, Point)
  let spacing = self.r.f64()
  let max_angle = self.r.f64()
  let keep_upright = self.flag()
  let anchor = self.from(anchor_values, Center)
  let offset = self.pair()
  let justify = self.from(justify_values, Center)
  let variable = self.anchors()
  let variable_stops = self.list(() => {
    let z = self.r.f64()
    (z, self.anchors())
  })
  let max_width = self.r.f64()
  let line_height = self.r.f64()
  let padding = self.top()
  let allow_overlap = self.flag()
  let ignore_placement = self.flag()
  let vertical = self.flag()
  let sort_key = self.opt_expr()
  let font = self.opt_expr()
  let (letter_spacing, transform, rotate) = match self.exprs() {
    [a, b, c] => (a, b, c)
    _ => {
      self.r.fail()
      (Lit(Null), Lit(Null), Lit(Null))
    }
  }
  let cooperative = self.flag()
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
    variable_stops,
    max_width,
    line_height,
    padding,
    allow_overlap,
    ignore_placement,
    vertical,
    sort_key,
    font,
    letter_spacing,
    transform,
    rotate,
    cooperative,
    z_order: self.from(z_orders, Auto),
  }
}

///|
fn StyleReader::icon(self : StyleReader) -> IconLayout {
  let image = self.exprs()
  let size = self.top()
  let rotate = self.top()
  let anchor = self.from(anchor_values, Center)
  let offset = self.pair()
  let padding = self.top()
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
    cooperative: self.flag(),
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
      translate: no_translate(),
      translate_viewport: false,
    }
  }
  {
    color,
    opacity,
    halo_color,
    halo_width,
    halo_blur,
    translate: no_translate(),
    translate_viewport: false,
  }
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
  let pattern = self.opt_expr()
  let gap_width = self.top()
  let offset = self.top()
  let blur = self.top()
  let translate = self.top()
  let translate_viewport = self.flag()
  let scale_with_map = self.flag()
  let pitch_with_map = self.flag()
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
    pattern,
    gap_width,
    offset,
    blur,
    translate,
    translate_viewport,
    scale_with_map,
    pitch_with_map,
    sort_key: self.opt_expr(),
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
/// icon `layout`, and the style its terrain, sky, light, projection and warnings.
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
    projection: Mercator,
    atmosphere_blend: Lit(Num(0.0)),
    warnings: [],
  }
}
