///|
/// Field tags of the MVT 2.1 schema (vector_tile.proto), as `read_tag` returns them.
const TILE_LAYER : Int32 = (3 << 3) | @pbf.WIRE_LEN

///|
const LAYER_VERSION : Int32 = (15 << 3) | @pbf.WIRE_VARINT

///|
const LAYER_NAME : Int32 = (1 << 3) | @pbf.WIRE_LEN

///|
const LAYER_FEATURE : Int32 = (2 << 3) | @pbf.WIRE_LEN

///|
const LAYER_KEY : Int32 = (3 << 3) | @pbf.WIRE_LEN

///|
const LAYER_VALUE : Int32 = (4 << 3) | @pbf.WIRE_LEN

///|
const LAYER_EXTENT : Int32 = (5 << 3) | @pbf.WIRE_VARINT

///|
const FEATURE_ID : Int32 = (1 << 3) | @pbf.WIRE_VARINT

///|
const FEATURE_TAGS : Int32 = (2 << 3) | @pbf.WIRE_LEN

///|
const FEATURE_TYPE : Int32 = (3 << 3) | @pbf.WIRE_VARINT

///|
const FEATURE_GEOMETRY : Int32 = (4 << 3) | @pbf.WIRE_LEN

///|
const VALUE_STRING : Int32 = (1 << 3) | @pbf.WIRE_LEN

///|
const VALUE_FLOAT : Int32 = (2 << 3) | @pbf.WIRE_FIXED32

///|
const VALUE_DOUBLE : Int32 = (3 << 3) | @pbf.WIRE_FIXED64

///|
const VALUE_INT : Int32 = (4 << 3) | @pbf.WIRE_VARINT

///|
const VALUE_UINT : Int32 = (5 << 3) | @pbf.WIRE_VARINT

///|
const VALUE_SINT : Int32 = (6 << 3) | @pbf.WIRE_VARINT

///|
const VALUE_BOOL : Int32 = (7 << 3) | @pbf.WIRE_VARINT

///|
/// `Feature.type` values; `types[i]` stores one in its low bits next to `HAS_ID`.
const GEOM_POINT : Int32 = 1

///|
const GEOM_LINESTRING : Int32 = 2

///|
const GEOM_POLYGON : Int32 = 3

///|
const GEOM_MASK : Int32 = 7

///|
const HAS_ID : Int32 = 8

///|
/// Geometry command integers: `id | count << 3` (MVT 2.1 §4.3.1).
const CMD_MOVE_TO : Int32 = 1

///|
const CMD_LINE_TO : Int32 = 2

///|
const CMD_CLOSE_PATH : Int32 = 7

///|
const CMD_ID_MASK : Int32 = 7

///|
const CMD_COUNT_SHIFT : Int32 = 3
