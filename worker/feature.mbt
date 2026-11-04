///|
/// Feature `index` of a layer's features, as expressions see it, with the processor's
/// hooks, and `place` (its tile) for `within` and `distance`, decoded through `scratch`.
/// Property names are resolved to key indices once per layer.
priv struct FeatureRef {
  features : Features
  mut index : Int32
  keys : Map[String, Int32]
  place : @style.TileGeometry
  scratch : @mvt.Geometry
  trig : @core.Trig
  text_number : (String) -> Double
  number_text : (Double) -> String
  intl : @style.Intl
}

///|
fn TileProcessor::feature_ref(
  self : TileProcessor,
  features : Features,
) -> FeatureRef {
  {
    features,
    index: 0,
    keys: Map([]),
    place: self.place,
    scratch: self.scratch,
    trig: self.trig,
    text_number: self.text_number,
    number_text: self.number_text,
    intl: self.intl,
  }
}

///|
impl @style.FeatureContext for FeatureRef with fn number_format(
  self,
  x,
  locale,
  currency,
  unit,
  min,
  max,
) {
  (self.intl.number_format)(x, locale, currency, unit, min, max)
}

///|
impl @style.FeatureContext for FeatureRef with fn collate(
  self,
  a,
  b,
  case,
  diacritic,
  locale,
) {
  (self.intl.collate)(a, b, case, diacritic, locale)
}

///|
impl @style.FeatureContext for FeatureRef with fn resolved_locale(self, l) {
  (self.intl.resolved_locale)(l)
}

///|
impl @style.FeatureContext for FeatureRef with fn trig(self) {
  self.trig
}

///|
impl @style.FeatureContext for FeatureRef with fn text_number(self, s) {
  (self.text_number)(s)
}

///|
impl @style.FeatureContext for FeatureRef with fn number_text(self, x) {
  (self.number_text)(x)
}

///|
impl @style.FeatureContext for FeatureRef with fn id(self) {
  self.features.id(self.index, None)
}

///|
fn style_value(v : @mvt.Value) -> @style.Value {
  match v {
    String(s) => Str(s)
    Float(f) => Num(f.to_double())
    Double(d) => Num(d)
    Int(i) | SInt(i) => Num(i.to_double())
    UInt(u) => Num(u.to_double())
    Bool(b) => Bool(b)
    Null => Null
  }
}

///|
impl @style.FeatureContext for FeatureRef with fn property(self, key) {
  let k = match self.keys.get(key) {
    Some(k) => k
    None => {
      let k = match self.features {
        Mvt(l) => l.key_index(key).unwrap_or(-1)
        Columns(c) => c.keys.search(key).unwrap_or(-1)
      }
      self.keys[key] = k
      k
    }
  }
  if k < 0 {
    return None
  }
  match self.features {
    Mvt(l) => l.property(self.index, k).map(style_value)
    Columns(c) => c.values[k][self.index]
  }
}

///|
/// Writes an expression's value as a property value (docs/FORMATS.md,
/// "Property values"); lists and colors are written as null.
fn write_value(w : @core.ByteWriter, v : @style.Value) -> Unit {
  match v {
    Bool(false) => w.u8(@core.PROP_FALSE)
    Bool(true) => w.u8(@core.PROP_TRUE)
    Num(n) => {
      w.u8(@core.PROP_NUMBER)
      w.f64(n)
    }
    Str(s) => {
      w.u8(@core.PROP_STRING)
      w.utf8(s)
    }
    _ => w.u8(@core.PROP_NULL)
  }
}

///|
impl @style.FeatureContext for FeatureRef with fn geometry_type(self) {
  match self.features.geom_type(self.index) {
    Point => "Point"
    LineString => "LineString"
    Polygon => "Polygon"
    Unknown => "Unknown"
  }
}

///|
/// Loads the feature's geometry into `place` as MapLibre's `loadGeometry` does
/// (scaled to `@style.GEOMETRY_EXTENT`, rounded, clamped to 15 bits); false if
/// it is malformed.
fn FeatureRef::load_place(self : FeatureRef) -> Bool {
  guard self.features.load(self.index, self.scratch) is None else {
    return false
  }
  let scale = @style.GEOMETRY_EXTENT.to_double() /
    self.features.extent().to_double()
  let coords = self.place.coords
  coords.clear()
  for c in self.scratch.coords {
    let v = (c.to_double() * scale + 0.5).floor()
    coords.push(
      if v < -16384.0 {
        -16384
      } else if v > 16383.0 {
        16383
      } else {
        v.to_int()
      },
    )
  }
  self.place.ring_ends.clear()
  self.place.ring_ends.append(self.scratch.ring_ends)
  true
}

///|
impl @style.FeatureContext for FeatureRef with fn within(self, polygons) {
  self.load_place() &&
  @style.geometry_within(
    polygons,
    @style.FeatureContext::geometry_type(self),
    self.place,
    self.trig,
  )
}

///|
impl @style.FeatureContext for FeatureRef with fn distance(self, shapes) {
  if self.load_place() {
    @style.geometry_distance(
      shapes,
      @style.FeatureContext::geometry_type(self),
      self.place,
      self.trig,
    )
  } else {
    Num(@double.not_a_number)
  }
}
