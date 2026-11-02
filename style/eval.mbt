///|
/// What an expression can read about the feature being styled: its
/// properties, its geometry type ("Point", "LineString", "Polygon" or
/// "Unknown") and its feature state (none by default).
pub(open) trait FeatureContext {
  fn property(Self, String) -> Value?
  fn geometry_type(Self) -> String
  fn state(Self, String) -> Value? = _
}

///|
impl FeatureContext with fn state(_, _) {
  None
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
fn truthy(v : Value) -> Bool {
  v is Bool(true)
}

///|
/// Equality without coercion: values of different types are not equal.
fn same(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Num(x), Num(y)) => x == y
    (Str(x), Str(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Null, Null) => true
    (Color(x), Color(y)) => x == y
    (List(x), List(y)) =>
      x.length() == y.length() &&
      x.iter().zip(y.iter()).all(p => same(p.0, p.1))
    _ => false
  }
}

///|
fn order(op : CmpOp, a : Value, b : Value) -> Bool {
  let c = match (a, b) {
    (Num(x), Num(y)) => x.compare(y)
    (Str(x), Str(y)) => x.compare(y)
    _ => return false
  }
  match op {
    Lt => c < 0
    Le => c <= 0
    Gt => c > 0
    _ => c >= 0
  }
}

///|
/// MapLibre's exponential interpolation factor between `lower` and `upper`.
fn factor(
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
    (@math.pow(base, progress) - 1.0) / (@math.pow(base, span) - 1.0)
  }
}

///|
fn blend(a : Value, b : Value, t : Double) -> Value {
  match (a, b) {
    (Num(x), Num(y)) => Num(x + (y - x) * t)
    (Color(x), Color(y)) =>
      Color({
        r: x.r + (y.r - x.r) * t,
        g: x.g + (y.g - x.g) * t,
        b: x.b + (y.b - x.b) * t,
        a: x.a + (y.a - x.a) * t,
      })
    _ => if t < 1.0 { a } else { b }
  }
}

///|
/// Evaluates the expression for a feature at `zoom`.
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
    GeometryType => Str(ctx.geometry_type())
    Zoom => Num(zoom)
    Not(e) => Bool(!truthy(go(e)))
    All(es) => Bool(es.iter().all(e => truthy(go(e))))
    Any(es) => Bool(es.iter().any(e => truthy(go(e))))
    Compare(Eq, a, b) => Bool(same(go(a), go(b)))
    Compare(Ne, a, b) => Bool(!same(go(a), go(b)))
    Compare(op, a, b) => Bool(order(op, go(a), go(b)))
    In(needle, haystack) =>
      match (go(needle), go(haystack)) {
        (n, List(items)) => Bool(items.iter().any(i => same(n, i)))
        (Str(n), Str(h)) => Bool(h.contains(n))
        _ => Bool(false)
      }
    Match(input, cases, fallback) => {
      let v = go(input)
      for c in cases {
        if c.0.iter().any(l => same(v, l)) {
          return go(c.1)
        }
      }
      go(fallback)
    }
    Case(cases, fallback) => {
      for c in cases {
        if truthy(go(c.0)) {
          return go(c.1)
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
    Interpolate(Exponential(base), input, stops) => {
      guard go(input) is Num(x) else { return Null }
      let n = stops.length()
      if x <= stops[0].0 {
        return go(stops[0].1)
      }
      if x >= stops[n - 1].0 {
        return go(stops[n - 1].1)
      }
      let mut i = 1
      while stops[i].0 < x {
        i += 1
      }
      let (z0, e0) = stops[i - 1]
      let (z1, e1) = stops[i]
      blend(go(e0), go(e1), factor(base, x, z0, z1))
    }
    FeatureState(k) => ctx.state(k).unwrap_or(Null)
    // The first argument of the type asked for (MapLibre fails over to the
    // property's default otherwise; Null does the same).
    Assert(t, es) => {
      for e in es {
        let v = go(e)
        match (t, v) {
          (BoolType, Bool(_)) | (NumberType, Num(_)) | (StringType, Str(_)) =>
            return v
          _ => ()
        }
      }
      Null
    }
    Step(input, first, stops) => {
      guard go(input) is Num(x) else { return go(first) }
      let mut out = first
      for s in stops {
        if x >= s.0 {
          out = s.1
        }
      }
      go(out)
    }
  }
}

///|
/// Property names the expression reads, and whether it reads the geometry
/// type: the feature data a value depends on.
pub fn Expr::feature_inputs(self : Expr) -> (Array[String], Bool) {
  let keys = []
  let mut geometry = false
  fn visit(e : Expr) -> Unit {
    match e {
      Lit(_) | Zoom | FeatureState(_) => ()
      Assert(_, es) => es.each(visit)
      Get(k) | Has(k) => if !keys.contains(k) { keys.push(k) }
      GeometryType => geometry = true
      Not(a) => visit(a)
      All(es) | Any(es) | Coalesce(es) => es.each(visit)
      Compare(_, a, b) | In(a, b) => {
        visit(a)
        visit(b)
      }
      Match(input, cases, fallback) => {
        visit(input)
        cases.each(c => visit(c.1))
        visit(fallback)
      }
      Case(cases, fallback) => {
        cases.each(c => {
          visit(c.0)
          visit(c.1)
        })
        visit(fallback)
      }
      Interpolate(_, input, stops) => {
        visit(input)
        stops.each(s => visit(s.1))
      }
      Step(input, first, stops) => {
        visit(input)
        visit(first)
        stops.each(s => visit(s.1))
      }
    }
  }
  visit(self)
  (keys, geometry)
}

///|
/// Whether the expression reads the feature state (MapLibre allows it in
/// paint properties only).
pub fn Expr::reads_state(self : Expr) -> Bool {
  match self {
    FeatureState(_) => true
    Lit(_) | Get(_) | Has(_) | GeometryType | Zoom => false
    Not(a) => a.reads_state()
    All(es) | Any(es) | Coalesce(es) | Assert(_, es) =>
      es.iter().any(e => e.reads_state())
    Compare(_, a, b) | In(a, b) => a.reads_state() || b.reads_state()
    Match(input, cases, fallback) =>
      input.reads_state() ||
      cases.iter().any(c => c.1.reads_state()) ||
      fallback.reads_state()
    Case(cases, fallback) =>
      cases.iter().any(c => c.0.reads_state() || c.1.reads_state()) ||
      fallback.reads_state()
    Interpolate(_, input, stops) =>
      input.reads_state() || stops.iter().any(s => s.1.reads_state())
    Step(input, first, stops) =>
      input.reads_state() ||
      first.reads_state() ||
      stops.iter().any(s => s.1.reads_state())
  }
}
