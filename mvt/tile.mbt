///|
/// Extent used when a layer does not declare one.
const DEFAULT_EXTENT : Int32 = 4096

///|
/// A feature's geometry type, as the MVT spec numbers them from 0 (§4.3.4).
pub(all) enum GeomType {
  Unknown
  Point
  LineString
  Polygon
} derive(Debug, Eq)

///|
/// A decoded tile. Layer tables, feature headers and tags are decoded and
/// validated by `Tile::parse`; feature geometry stays encoded until requested.
pub struct Tile {
  layers : Array[Layer]
}

///|
/// A tile layer; `keys` and `values` are the tables feature tags index into.
/// Features are addressed by index in `0..<length()` (others panic) and stored
/// column-wise, so no per-feature object is allocated.
pub struct Layer {
  name : String
  version : Int32
  extent : Int32
  keys : Array[String]
  values : Array[Value]
  priv ids : Array[UInt64]
  priv types : Array[Int32]
  priv geoms : Array[Int32]
  priv tags : Array[Int32]
  priv tag_offsets : Array[Int32]
  priv cursor : @pbf.Reader
}

///|
/// Largest key/value indices seen while decoding a layer's tags, checked
/// against the tables once the whole layer (which may list them last) is read.
priv struct TagCheck {
  mut max_key : Int32
  mut max_key_pos : Int32
  mut max_value : Int32
  mut max_value_pos : Int32
  mut odd_pos : Int32
}

///|
fn TagCheck::new() -> TagCheck {
  { max_key: -1, max_key_pos: 0, max_value: -1, max_value_pos: 0, odd_pos: -1, }
}

///|
fn TagCheck::record(
  self : TagCheck,
  k : Int32,
  kpos : Int32,
  v : Int32,
  vpos : Int32,
) -> Unit {
  if k > self.max_key {
    self.max_key = k
    self.max_key_pos = kpos
  }
  if v > self.max_value {
    self.max_value = v
    self.max_value_pos = vpos
  }
}

///|
fn TagCheck::verify(self : TagCheck, layer : Layer) -> Unit raise MvtError {
  if self.odd_pos >= 0 {
    raise OddTagCount(pos=self.odd_pos)
  }
  if self.max_key >= layer.keys.length() {
    raise IndexOutOfRange(pos=self.max_key_pos, self.max_key)
  }
  if self.max_value >= layer.values.length() {
    raise IndexOutOfRange(pos=self.max_value_pos, self.max_value)
  }
}

///|
pub fn Tile::parse(bytes : BytesView) -> Tile raise MvtError {
  let r = @pbf.Reader::new(bytes)
  let layers = []
  while !r.at_end() {
    let t = r.read_tag()
    if t == TILE_LAYER {
      let check = TagCheck::new()
      let layer = parse_layer(r, @pbf.Reader::new(bytes), check)
      if r.failed() {
        break
      }
      check.verify(layer)
      layers.push(layer)
    } else {
      r.skip(t)
    }
  }
  if r.error() is Some(e) {
    raise Malformed(e)
  }
  { layers, }
}

///|
fn parse_layer(
  r : @pbf.Reader,
  cursor : @pbf.Reader,
  check : TagCheck,
) -> Layer {
  let token = r.enter()
  let mut name = ""
  let mut version = 1
  let mut extent = DEFAULT_EXTENT
  let keys = []
  let values = []
  let ids = []
  let types = []
  let geoms = []
  let tags = []
  let tag_offsets = [0]
  while !r.at_end() {
    let t = r.read_tag()
    match t {
      LAYER_VERSION => version = r.read_varint32()
      LAYER_NAME => name = r.read_string()
      LAYER_FEATURE =>
        parse_feature_header(r, ids, types, geoms, tags, tag_offsets, check)
      LAYER_KEY => keys.push(r.read_string())
      LAYER_VALUE => values.push(parse_value(r))
      // Everything downstream divides by it.
      LAYER_EXTENT =>
        extent = match r.read_varint32() {
          e if e > 0 => e
          _ => DEFAULT_EXTENT
        }
      _ => r.skip(t)
    }
  }
  r.exit(token)
  {
    name,
    version,
    extent,
    keys,
    values,
    ids,
    types,
    geoms,
    tags,
    tag_offsets,
    cursor,
  }
}

///|
fn parse_feature_header(
  r : @pbf.Reader,
  ids : Array[UInt64],
  types : Array[Int32],
  geoms : Array[Int32],
  tags : Array[Int32],
  tag_offsets : Array[Int32],
  check : TagCheck,
) -> Unit {
  let token = r.enter()
  let mut id = 0UL
  let mut flags = 0
  let mut geom_start = 0
  let mut geom_end = 0
  while !r.at_end() {
    let t = r.read_tag()
    match t {
      FEATURE_ID => {
        id = r.read_varint64()
        flags = flags | HAS_ID
      }
      FEATURE_TAGS => decode_tags(r, tags, check)
      FEATURE_TYPE => {
        let ty = r.read_varint32()
        let known = ty == GEOM_POINT ||
          ty == GEOM_LINESTRING ||
          ty == GEOM_POLYGON
        flags = (flags & HAS_ID) | (if known { ty } else { 0 })
      }
      FEATURE_GEOMETRY => {
        geom_start = r.read_len_start()
        geom_end = r.pos()
      }
      _ => r.skip(t)
    }
  }
  r.exit(token)
  ids.push(id)
  types.push(flags)
  geoms.push(geom_start)
  geoms.push(geom_end)
  tag_offsets.push(tags.length())
}

///|
/// Appends a packed tag field's (key, value) index pairs to `tags`.
fn decode_tags(r : @pbf.Reader, tags : Array[Int32], check : TagCheck) -> Unit {
  let token = r.enter()
  while !r.at_end() {
    let kpos = r.pos()
    let k = r.read_varint32()
    if r.at_end() {
      if !r.failed() && check.odd_pos < 0 {
        check.odd_pos = kpos
      }
      break
    }
    let vpos = r.pos()
    let v = r.read_varint32()
    // Indices are uint32; anything that reads back negative is out of range.
    let k = if k < 0 { @int.MAX_VALUE } else { k }
    let v = if v < 0 { @int.MAX_VALUE } else { v }
    check.record(k, kpos, v, vpos)
    tags.push(k)
    tags.push(v)
  }
  r.exit(token)
}

///|
/// The last layer called `name`, as other decoders resolve duplicates.
pub fn Tile::layer(self : Tile, name : String) -> Layer? {
  for i = self.layers.length() - 1; i >= 0; i = i - 1 {
    if self.layers[i].name == name {
      return Some(self.layers[i])
    }
  }
  None
}

///|
pub fn Layer::length(self : Layer) -> Int32 {
  self.types.length()
}

///|
pub fn Layer::geom_type(self : Layer, i : Int32) -> GeomType {
  match self.types[i] & GEOM_MASK {
    GEOM_POINT => Point
    GEOM_LINESTRING => LineString
    GEOM_POLYGON => Polygon
    _ => Unknown
  }
}

///|
pub fn Layer::id(self : Layer, i : Int32) -> UInt64? {
  if (self.types[i] & HAS_ID) != 0 {
    Some(self.ids[i])
  } else {
    None
  }
}

///|
/// Index of `key` in `keys`, for `property`; resolve it once per layer.
pub fn Layer::key_index(self : Layer, key : String) -> Int32? {
  for i, k in self.keys {
    if k == key {
      return Some(i)
    }
  }
  None
}

///|
/// Feature `i`'s value for the key at `key_index`, without allocating.
/// A repeated key yields its last value.
pub fn Layer::property(self : Layer, i : Int32, key_index : Int32) -> Value? {
  let mut found = -1
  for t = self.tag_offsets[i]; t < self.tag_offsets[i + 1]; t = t + 2 {
    if self.tags[t] == key_index {
      found = self.tags[t + 1]
    }
  }
  if found < 0 {
    None
  } else {
    Some(self.values[found])
  }
}

///|
/// How many tags (key and value pairs) feature `i` has.
pub fn Layer::tag_count(self : Layer, i : Int32) -> Int32 {
  (self.tag_offsets[i + 1] - self.tag_offsets[i]) / 2
}

///|
/// Feature `i`'s tag `k` (0 <= `k` < `tag_count(i)`) as key and value, in
/// the order the tile lists them.
pub fn Layer::tag(self : Layer, i : Int32, k : Int32) -> (String, Value) {
  let t = self.tag_offsets[i] + k * 2
  (self.keys[self.tags[t]], self.values[self.tags[t + 1]])
}

///|
/// Feature `i`'s tags as a key → value map; a repeated key keeps its last value.
pub fn Layer::properties(self : Layer, i : Int32) -> Map[String, Value] {
  let start = self.tag_offsets[i]
  let end = self.tag_offsets[i + 1]
  let props = Map([], capacity=(end - start) / 2)
  for t = start; t < end; t = t + 2 {
    props[self.keys[self.tags[t]]] = self.values[self.tags[t + 1]]
  }
  props
}
