///|
/// Feature `index` of a layer's features, as expressions see it. Property
/// names are resolved to key indices once per layer.
priv struct FeatureRef {
  features : Features
  mut index : Int32
  keys : Map[String, Int32]
}

///|
fn FeatureRef::new(features : Features) -> FeatureRef {
  { features, index: 0, keys: Map([]), }
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
impl @style.FeatureContext for FeatureRef with fn geometry_type(self) {
  match self.features.geom_type(self.index) {
    Point => "Point"
    LineString => "LineString"
    Polygon => "Polygon"
    Unknown => "Unknown"
  }
}
