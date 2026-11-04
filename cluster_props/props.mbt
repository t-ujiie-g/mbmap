///|
/// The host hooks expressions take (`@style.FeatureContext`'s `trig`, `number_text`,
/// `text_number` and `intl`).
pub(all) struct Hooks {
  trig : @core.Trig
  number_text : (Double) -> String
  text_number : (String) -> Double
  intl : @style.Intl
}

///|
/// MoonBit's own, for tests and the js backend.
pub fn Hooks::default() -> Hooks {
  {
    trig: @core.Trig::moonbit(),
    number_text: Double::to_string,
    text_number: @style.js_number,
    intl: @style.Intl::fallback(),
  }
}

///|
/// What a map or reduce expression reads: a point's properties (`table` at `row`) or a
/// point's or cluster's mapped values (`values` by `keys`), and `acc`, the value so far.
priv struct Props {
  table : @geom.Table?
  mut row : Int32
  keys : Array[String]
  mut values : Array[@geom.Prop]
  mut acc : @style.Value
  hooks : Hooks
}

///|
fn value_of(p : @geom.Prop) -> @style.Value {
  match p {
    Null => Null
    Bool(b) => Bool(b)
    Num(n) => Num(n)
    Str(s) => Str(s)
  }
}

///|
/// A result as MapLibre's `StyleExpression.evaluate` keeps it: errors and NaN become
/// null (its default without a property specification); colors, arrays, formatted text
/// and collators are left out as null.
fn prop_of(v : @style.Value) -> @geom.Prop {
  match v {
    Bool(b) => Bool(b)
    Num(n) if !n.is_nan() => Num(n)
    Str(s) => Str(s)
    _ => Null
  }
}

///|
impl @style.FeatureContext for Props with fn property(self, key) {
  match self.table {
    Some(t) => t.column(key).bind(c => c.values[self.row]).map(value_of)
    None =>
      match self.keys.search(key) {
        Some(k) if k < self.values.length() => Some(value_of(self.values[k]))
        _ => None
      }
  }
}

///|
/// MapLibre passes only the properties (`{properties}`), so the type is not known.
impl @style.FeatureContext for Props with fn geometry_type(_) {
  "Unknown"
}

///|
impl @style.FeatureContext for Props with fn accumulated(self) {
  self.acc
}

///|
impl @style.FeatureContext for Props with fn trig(self) {
  self.hooks.trig
}

///|
impl @style.FeatureContext for Props with fn number_text(self, x) {
  (self.hooks.number_text)(x)
}

///|
impl @style.FeatureContext for Props with fn text_number(self, s) {
  (self.hooks.text_number)(s)
}

///|
impl @style.FeatureContext for Props with fn number_format(
  self,
  x,
  locale,
  currency,
  unit,
  min,
  max,
) {
  (self.hooks.intl.number_format)(x, locale, currency, unit, min, max)
}

///|
impl @style.FeatureContext for Props with fn collate(
  self,
  a,
  b,
  case,
  diacritic,
  locale,
) {
  (self.hooks.intl.collate)(a, b, case, diacritic, locale)
}

///|
impl @style.FeatureContext for Props with fn resolved_locale(self, locale) {
  (self.hooks.intl.resolved_locale)(locale)
}

///|
/// `props` (`@style.compile_cluster_properties`) over `table`'s points as MapLibre's
/// `getSuperclusterOptions`: each key mapped from a point's properties at zoom 0, and
/// reduced with `["accumulated"]` the cluster's value and the other's values as properties.
pub fn cluster_properties(
  table : @geom.Table,
  props : Array[(String, @style.Expr, @style.Expr)],
  hooks~ : Hooks = Hooks::default(),
) -> @tiler.ClusterProperties {
  let keys = props.map(p => p.0)
  let point : Props = {
    table: Some(table),
    row: 0,
    keys,
    values: [],
    acc: Null,
    hooks,
  }
  let other : Props = {
    table: None,
    row: 0,
    keys,
    values: [],
    acc: Null,
    hooks,
  }
  {
    keys,
    map: row => {
      point.row = row
      props.map(p => prop_of(p.1.eval(0.0, point)))
    },
    reduce: (acc, values) => {
      other.values = values
      for k, p in props {
        other.acc = value_of(acc[k])
        acc[k] = prop_of(p.2.eval(0.0, other))
      }
    },
  }
}
