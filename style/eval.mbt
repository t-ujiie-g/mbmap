///|
/// A feature as expressions read it (`geometry_type` "Point", "LineString", "Polygon" or
/// "Unknown"), with the JavaScript host's `Math` (`trig`), `String(number)`, `Number(string)`
/// and `Intl` as MapLibre calls it (None or NaN where `Intl` throws; `style/intl_js.mbt`).
pub(open) trait FeatureContext {
  fn property(Self, String) -> Value?
  fn geometry_type(Self) -> String
  fn id(Self) -> Value = _
  fn state(Self, String) -> Value? = _
  fn trig(Self) -> @core.Trig = _
  fn number_text(Self, Double) -> String = _
  fn text_number(Self, String) -> Double = _
  fn line_progress(Self) -> Double = _
  fn heatmap_density(Self) -> Double = _
  fn elevation(Self) -> Double = _
  fn number_format(Self, Double, String?, String?, String?, Double?, Double?) -> String? = _
  fn collate(Self, String, String, Bool, Bool, String?) -> Double = _
  fn resolved_locale(Self, String?) -> String? = _
  fn accumulated(Self) -> Value = _
  fn within(Self, Array[Array[Array[Double]]]) -> Bool = _
  fn distance(Self, Array[Shape]) -> Value = _
}

///|
/// Null: the value so far is known only where cluster properties are reduced.
impl FeatureContext with fn accumulated(_) {
  Null
}

///|
/// False: a feature's geometry is known only where tiles are read
/// (`geometry_within`), as MapLibre's `within` without a canonical tile.
impl FeatureContext with fn within(_, _) {
  false
}

///|
/// NaN: as `within`, for `geometry_distance`.
impl FeatureContext with fn distance(_, _) {
  Num(@double.not_a_number)
}

///|
impl FeatureContext with fn number_format(_, x, l, c, u, min, max) {
  intl_number_format(x, l, c, u, min, max)
}

///|
impl FeatureContext with fn collate(_, a, b, case, diacritic, locale) {
  intl_collate(a, b, case, diacritic, locale)
}

///|
impl FeatureContext with fn resolved_locale(_, locale) {
  intl_resolved_locale(locale)
}

///|
impl FeatureContext with fn id(_) {
  Null
}

///|
impl FeatureContext with fn state(_, _) {
  None
}

///|
/// NaN: `line-progress` is known only where a line gradient is drawn.
impl FeatureContext with fn line_progress(_) {
  @double.not_a_number
}

///|
/// NaN: `heatmap-density` is known only where a heatmap's colors are made.
impl FeatureContext with fn heatmap_density(_) {
  @double.not_a_number
}

///|
/// NaN: `elevation` is known only where a color relief's ramp is made.
impl FeatureContext with fn elevation(_) {
  @double.not_a_number
}

///|
impl FeatureContext with fn trig(_) {
  @core.Trig::moonbit()
}

///|
impl FeatureContext with fn number_text(_, x) {
  x.to_string()
}

///|
impl FeatureContext with fn text_number(_, s) {
  js_number(s)
}

///|
/// A context without a feature, for zoom-only and constant expressions.
pub(all) struct NoFeature {}

///|
pub impl FeatureContext for NoFeature with fn property(_, _) {
  None
}

///|
pub impl FeatureContext for NoFeature with fn geometry_type(_) {
  "Unknown"
}

///|
/// Strict equality as JavaScript's `===` on expression values: values of
/// different types are not equal, nor are colors and arrays.
fn same(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Num(x), Num(y)) => x == y
    (Str(x), Str(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Null, Null) => true
    _ => false
  }
}

///|
/// JavaScript's `<` on strings: by UTF-16 code units.
fn str_compare(a : String, b : String) -> Int32 {
  let n = @cmp.minimum(a.length(), b.length())
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
fn order(op : CmpOp, a : Value, b : Value) -> Value {
  let c = match (a, b) {
    (Num(x), Num(y)) =>
      // NaN compares false either way.
      if x != x || y != y {
        return Bool(false)
      } else {
        x.compare(y)
      }
    (Str(x), Str(y)) => str_compare(x, y)
    _ => return Failed
  }
  Bool(
    match op {
      Lt => c < 0
      Le => c <= 0
      Gt => c > 0
      _ => c >= 0
    },
  )
}

///|
/// MapLibre's exponential interpolation factor between `lower` and `upper`.
fn factor(
  pow : (Double, Double) -> Double,
  base : Double,
  input : Double,
  lower : Double,
  upper : Double,
) -> Double {
  let span = upper - lower
  let progress = input - lower
  if span == 0.0 {
    0.0
  } else if base == 1.0 {
    progress / span
  } else {
    (pow(base, progress) - 1.0) / (pow(base, span) - 1.0)
  }
}

///|
fn blend(a : Value, b : Value, t : Double) -> Value {
  match (a, b) {
    (Num(x), Num(y)) => Num(x + t * (y - x))
    (Color(x), Color(y)) =>
      Color({
        r: x.r + t * (y.r - x.r),
        g: x.g + t * (y.g - x.g),
        b: x.b + t * (y.b - x.b),
        a: x.a + t * (y.a - x.a),
      })
    (List(xs), List(ys)) if xs.length() == ys.length() => {
      let out = []
      for i, x in xs {
        let v = blend(x, ys[i], t)
        if !(v is Num(_)) {
          return Failed
        }
        out.push(v)
      }
      List(out)
    }
    _ => Failed
  }
}

///|
/// Evaluates the expression for a feature at `zoom`; `Failed` where MapLibre
/// raises an evaluation error.
pub fn[C : FeatureContext] Expr::eval(
  self : Expr,
  zoom : Double,
  ctx : C,
) -> Value {
  let go = (e : Expr) => e.eval(zoom, ctx)
  match self {
    Lit(v) => v
    Get(k) => ctx.property(k).unwrap_or(Null)
    Has(k) => Bool(ctx.property(k) is Some(_))
    Id => ctx.id()
    GeometryType => Str(ctx.geometry_type())
    Zoom => Num(zoom)
    LineProgress => {
      let p = ctx.line_progress()
      if p.is_nan() {
        Failed
      } else {
        Num(p)
      }
    }
    HeatmapDensity => {
      let d = ctx.heatmap_density()
      if d.is_nan() {
        Failed
      } else {
        Num(d)
      }
    }
    Elevation => {
      let h = ctx.elevation()
      if h.is_nan() {
        Failed
      } else {
        Num(h)
      }
    }
    Not(e) =>
      match go(e) {
        Bool(b) => Bool(!b)
        _ => Failed
      }
    All(es) | Any(es) => {
      let all = self is All(_)
      for e in es {
        match go(e) {
          Bool(b) => if b != all { return Bool(b) }
          _ => return Failed
        }
      }
      Bool(all)
    }
    Compare(op, a, b) => {
      let (x, y) = (go(a), go(b))
      match (op, x, y) {
        (_, Failed, _) | (_, _, Failed) => Failed
        (Eq, _, _) => Bool(same(x, y))
        (Ne, _, _) => Bool(!same(x, y))
        _ => order(op, x, y)
      }
    }
    Collate(op, a, b, c) => {
      let (x, y) = (go(a), go(b))
      match (op, x, y) {
        (_, Failed, _) | (_, _, Failed) => return Failed
        (_, Str(_), Str(_)) => ()
        (Eq, _, _) => return Bool(same(x, y))
        (Ne, _, _) => return Bool(!same(x, y))
        (_, Num(_), Num(_)) => ()
        _ => return Failed
      }
      guard go(c) is Collator(case, diacritic, locale) else { return Failed }
      let d = ctx.collate(
        js_string(ctx, x),
        js_string(ctx, y),
        case,
        diacritic,
        locale,
      )
      if d != d {
        return Failed
      }
      Bool(
        match op {
          Eq => d == 0.0
          Ne => d != 0.0
          Lt => d < 0.0
          Le => d <= 0.0
          Gt => d > 0.0
          Ge => d >= 0.0
        },
      )
    }
    In(needle, haystack) => {
      let n = go(needle)
      let h = go(haystack)
      match (n, h) {
        (Failed, _) | (_, Failed) => Failed
        (_, Null | Bool(false) | Str("")) => Bool(false)
        (_, Num(x)) if x == 0.0 || x != x => Bool(false)
        (Color(_) | List(_) | Formatted(_) | Collator(_, _, _), _) => Failed
        (_, List(items)) => Bool(items.iter().any(i => same(n, i)))
        (_, Str(s)) => Bool(s.contains(js_string(ctx, n)))
        _ => Failed
      }
    }
    Match(input, cases, fallback) => {
      let v = go(input)
      if v is Failed {
        return Failed
      }
      for c in cases {
        if c.0.iter().any(l => same(v, l)) {
          return go(c.1)
        }
      }
      go(fallback)
    }
    Case(cases, fallback) => {
      for c in cases {
        match go(c.0) {
          Bool(true) => return go(c.1)
          Bool(false) => ()
          _ => return Failed
        }
      }
      go(fallback)
    }
    Coalesce(es) => {
      for e in es {
        let v = go(e)
        if !(v is Null) {
          return v
        }
      }
      Null
    }
    Interpolate(interp, space, input, stops) => {
      let n = stops.length()
      if n == 1 {
        return go(stops[0].1)
      }
      guard go(input) is Num(x) else { return Failed }
      if x <= stops[0].0 {
        return go(stops[0].1)
      }
      if x >= stops[n - 1].0 {
        return go(stops[n - 1].1)
      }
      if x != x {
        return Failed
      }
      let mut i = 1
      while stops[i].0 <= x {
        i += 1
      }
      let (z0, e0) = stops[i - 1]
      let (z1, e1) = stops[i]
      let trig = ctx.trig()
      let t = match interp {
        Exponential(base) => factor(trig.pow, base, x, z0, z1)
        CubicBezier(a, b, c, d) =>
          @core.Bezier::new(a, b, c, d).at(factor(trig.pow, 1.0, x, z0, z1))
      }
      match (space, go(e0), go(e1)) {
        (Rgb, a, b) => blend(a, b, t)
        (_, Color(a), Color(b)) => Color(blend_space(trig, space, a, b, t))
        _ => Failed
      }
    }
    FeatureState(k) => ctx.state(k).unwrap_or(Null)
    Assert(t, es) => {
      for e in es {
        let v = go(e)
        if v is Failed || is_type(t, v) {
          return v
        }
      }
      Failed
    }
    Coerce(t, es) => coerce(t, es, zoom, ctx)
    Step(input, first, stops) => {
      if stops.length() == 0 {
        return go(first)
      }
      guard go(input) is Num(x) && x == x else { return Failed }
      let mut out = first
      for s in stops {
        if x >= s.0 {
          out = s.1
        }
      }
      go(out)
    }
    Call(op, args) => call(op, args, zoom, ctx)
    Accumulated => ctx.accumulated()
    Within(polygons) => Bool(ctx.within(polygons))
    Distance(shapes) => ctx.distance(shapes)
  }
}

///|
/// Whether `v` has type `t` (MapLibre's `checkSubtype` against `typeOf(v)`).
fn is_type(t : Expected, v : Value) -> Bool {
  match (t, v) {
    (AnyType, _) => true
    (BoolType, Bool(_))
    | (NumberType, Num(_))
    | (StringType, Str(_))
    | (ColorType, Color(_)) => true
    (ArrayOf(item, n), List(xs)) =>
      (n < 0 || xs.length() == n) &&
      (item is AnyType || xs.iter().all(x => is_type(item, x)))
    _ => false
  }
}

///|
/// Calls `f` with each sub-expression of `self` (not their own).
fn Expr::each_child(self : Expr, f : (Expr) -> Unit) -> Unit {
  match self {
    Lit(_)
    | Get(_)
    | Has(_)
    | Id
    | GeometryType
    | Zoom
    | LineProgress
    | HeatmapDensity
    | Elevation
    | Accumulated
    | Within(_)
    | Distance(_)
    | FeatureState(_) => ()
    Not(a) => f(a)
    All(es)
    | Any(es)
    | Coalesce(es)
    | Assert(_, es)
    | Coerce(_, es)
    | Call(_, es) => es.each(f)
    Compare(_, a, b) | In(a, b) => {
      f(a)
      f(b)
    }
    Collate(_, a, b, c) => {
      f(a)
      f(b)
      f(c)
    }
    Match(input, cases, fallback) => {
      f(input)
      cases.each(c => f(c.1))
      f(fallback)
    }
    Case(cases, fallback) => {
      cases.each(c => {
        f(c.0)
        f(c.1)
      })
      f(fallback)
    }
    Interpolate(_, _, input, stops) => {
      f(input)
      stops.each(s => f(s.1))
    }
    Step(input, first, stops) => {
      f(input)
      f(first)
      stops.each(s => f(s.1))
    }
  }
}

///|
/// The key `feature_inputs` reports for an expression reading the feature id.
pub const FEATURE_ID_KEY : String = "$id"

///|
/// Property names the expression reads (`FEATURE_ID_KEY` for the id), and
/// whether it reads the geometry (its type, `within`, `distance`): the feature
/// data a value depends on.
pub fn Expr::feature_inputs(self : Expr) -> (Array[String], Bool) {
  let keys = []
  let mut geometry = false
  fn visit(e : Expr) -> Unit {
    match e {
      Get(k) | Has(k) => if !keys.contains(k) { keys.push(k) }
      Id => if !keys.contains(FEATURE_ID_KEY) { keys.push(FEATURE_ID_KEY) }
      GeometryType | Within(_) | Distance(_) => geometry = true
      _ => e.each_child(visit)
    }
  }
  visit(self)
  (keys, geometry)
}

///|
/// Whether `self` or an expression within it satisfies `pred`.
fn Expr::any(self : Expr, pred : (Expr) -> Bool) -> Bool {
  let mut found = false
  fn visit(e : Expr) -> Unit {
    if pred(e) {
      found = true
    } else if !found {
      e.each_child(visit)
    }
  }
  visit(self)
  found
}

///|
/// Whether the expression reads `line-progress`.
fn Expr::reads_line_progress(self : Expr) -> Bool {
  self.any(e => e is LineProgress)
}

///|
/// Whether the expression reads `heatmap-density`.
fn Expr::reads_heatmap_density(self : Expr) -> Bool {
  self.any(e => e is HeatmapDensity)
}

///|
/// Whether the expression reads `elevation`.
fn Expr::reads_elevation(self : Expr) -> Bool {
  self.any(e => e is Elevation)
}

///|
/// Whether the expression reads the feature state (MapLibre allows it in
/// paint properties only).
pub fn Expr::reads_state(self : Expr) -> Bool {
  self.any(e => e is FeatureState(_))
}
