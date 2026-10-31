///|
fn value_json(v : @mvt.Value) -> Json {
  match v {
    String(s) => Json::string(s)
    Float(f) => Json::number(f.to_double())
    Double(d) => Json::number(d)
    Int(i) | SInt(i) => Json::number(i.to_double())
    UInt(u) => Json::number(u.to_double())
    Bool(b) => Json::boolean(b)
    Null => Json::null()
  }
}

///|
fn feature_json(layer : @mvt.Layer, i : Int32) -> Json raise {
  let props : Map[String, Json] = Map([])
  for k, v in layer.properties(i) {
    props[k] = value_json(v)
  }
  let rings = layer
    .load_geometry(i)
    .map(ring => {
      Json::array(
        ring.map(p => {
          Json::array([
            Json::number(p.0.to_double()),
            Json::number(p.1.to_double()),
          ])
        }),
      )
    })
  let geom_type = match layer.geom_type(i) {
    Unknown => 0
    Point => 1
    LineString => 2
    Polygon => 3
  }
  Json::object({
    "id": match layer.id(i) {
      Some(id) => Json::number(id.to_double())
      None => Json::null()
    },
    "type": Json::number(geom_type.to_double()),
    "properties": Json::object(props),
    "geometry": Json::array(rings),
  })
}

///|
/// The whole tile as JSON, keyed by layer name (last duplicate wins), in the
/// shape bench/mvt/golden.mjs builds from `@mapbox/vector-tile`.
#export_name("tile_to_json")
pub fn tile_to_json(bytes : Bytes) -> String {
  let layers : Map[String, Json] = Map([])
  let tile = @mvt.Tile::parse(bytes[:]) catch {
    e => return "error: \{Repr(e)}"
  }
  // Assigning in order keeps each name's first position and last layer, like a JS object.
  for layer in tile.layers {
    let features = []
    for i in 0..<layer.length() {
      features.push(
        feature_json(layer, i) catch {
          e => return "error: \{Repr(e)}"
        },
      )
    }
    layers[layer.name] = Json::object({
      "version": Json::number(layer.version.to_double()),
      "extent": Json::number(layer.extent.to_double()),
      "features": Json::array(features),
    })
  }
  Json::object(layers).stringify()
}
