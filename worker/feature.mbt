///|
/// Feature `index` of an mvt layer, as expressions see it. Property names are
/// resolved to the layer's key indices once per layer.
priv struct FeatureRef {
  layer : @mvt.Layer
  mut index : Int32
  keys : Map[String, Int32]
}

///|
fn FeatureRef::new(layer : @mvt.Layer) -> FeatureRef {
  { layer, index: 0, keys: Map([]), }
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
      let k = self.layer.key_index(key).unwrap_or(-1)
      self.keys[key] = k
      k
    }
  }
  if k < 0 {
    return None
  }
  self.layer.property(self.index, k).map(style_value)
}

///|
impl @style.FeatureContext for FeatureRef with fn geometry_type(self) {
  match self.layer.geom_type(self.index) {
    Point => "Point"
    LineString => "LineString"
    Polygon => "Polygon"
    Unknown => "Unknown"
  }
}
