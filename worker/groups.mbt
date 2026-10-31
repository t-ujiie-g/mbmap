///|
/// Most groups per layer and tile; features beyond are drawn with the last
/// group's paint.
pub const MAX_GROUPS : Int32 = 64

///|
/// Feature inputs of a layer's paint: property names, and whether it reads
/// the geometry type.
fn paint_inputs(sl : @style.StyleLayer) -> (Array[String], Bool) {
  let keys = []
  let mut geometry = false
  let exprs = match sl.kind {
    Line => [sl.color, sl.opacity, sl.width]
    Circle =>
      [
        sl.color,
        sl.opacity,
        sl.radius,
        sl.stroke_width,
        sl.stroke_color,
        sl.stroke_opacity,
      ]
    Symbol => [sl.color, sl.opacity, sl.halo_color, sl.halo_width]
    _ => [sl.color, sl.opacity]
  }
  for e in exprs {
    let (ks, g) = e.feature_inputs()
    for k in ks {
      if !keys.contains(k) {
        keys.push(k)
      }
    }
    geometry = geometry || g
  }
  (keys, geometry)
}

///|
/// A layer's split of features by the values its paint reads; `active` is
/// false when the paint reads none, so every feature goes to group 0.
priv struct Groups {
  keys : Array[String]
  geometry : Bool
  active : Bool
  values : Array[Array[@style.Value?]]
  scratch : Array[@style.Value?]
}

///|
fn Groups::new(inputs : (Array[String], Bool)) -> Groups {
  {
    keys: inputs.0,
    geometry: inputs.1,
    active: grouped(inputs),
    values: [],
    scratch: [],
  }
}

///|
fn grouped(inputs : (Array[String], Bool)) -> Bool {
  inputs.0.length() > 0 || inputs.1
}

///|
/// The group of `feature` (at its current index), creating it if new.
fn Groups::of(self : Groups, feature : FeatureRef) -> Int32 {
  if !self.active {
    return 0
  }
  let s = self.scratch
  s.clear()
  for k in self.keys {
    s.push(@style.FeatureContext::property(feature, k))
  }
  if self.geometry {
    s.push(Some(Str(@style.FeatureContext::geometry_type(feature))))
  }
  for g, v in self.values {
    if v == s {
      return g
    }
  }
  if self.values.length() >= MAX_GROUPS {
    return MAX_GROUPS - 1
  }
  self.values.push(s.copy())
  self.values.length() - 1
}

///|
/// Group `g`'s shared inputs (docs/FORMATS.md, "Packed tile"): properties by name (absent
/// ones omitted, so `has` stays correct) and the geometry type under
/// `@core.GEOMETRY_TYPE_KEY`.
fn Groups::props(self : Groups, g : Int32) -> Bytes {
  let w = @core.ByteWriter::new()
  let v = self.values[g]
  let entries : Array[(String, @style.Value)] = []
  for i, k in self.keys {
    if v[i] is Some(x) {
      entries.push((k, x))
    }
  }
  if self.geometry && v[self.keys.length()] is Some(t) {
    entries.push((@core.GEOMETRY_TYPE_KEY, t))
  }
  w.u32(entries.length())
  for e in entries {
    w.utf8(e.0)
    match e.1 {
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
  w.to_bytes()
}

///|
/// The number of groups to emit: at least one, even for an ungrouped layer.
fn Groups::count(self : Groups) -> Int32 {
  @cmp.maximum(1, self.values.length())
}
