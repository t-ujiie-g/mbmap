# Binary formats and worker messages

Reference for the bytes and messages that cross worker boundaries. The code cites
the section names here. Every number is little-endian; "UTF-8" means a u32 byte
length followed by that many bytes.

## Property values

Property values in all formats below are a tag byte (`@core.PROP_*`), then a
payload:

| tag | value | payload |
|---|---|---|
| 0 | null | — |
| 1 | false | — |
| 2 | true | — |
| 3 | number | f64 |
| 4 | string | UTF-8 |
| 5 | absent (the feature lacks the key) | — |

## Packed tile (`worker/packed.mbt`)

What the display worker writes for a tile, read by `worker/js/worker.mjs`:

- u32 entry count, then `LAYER_ENTRY_WORDS` (23) u32s per entry, the header sized for
  the most entries the tile may have (`MAX_GROUPS` for a grouped layer). Kinds:
  `KIND_FILL` 1, `KIND_LINE` 2, `KIND_CIRCLE` 3 (also heatmaps), `KIND_SYMBOL` 4
  ("Labels"), `KIND_EXTRUSION` 6. An entry's words, by their `ENTRY_*` names
  (`worker/js/worker.mjs` `unpack` names them in this order, and
  `worker/js/mirror.test.mjs` checks it); a range left out is 0 and 0:

  | word | `ENTRY_` | value |
  |---|---|---|
  | 0 | `LAYER` | style layer index |
  | 1 | `KIND` | kind |
  | 2, 3 | `VERTEX_OFFSET`, `VERTEX_BYTES` | vertex byte offset and length (padded to 4) |
  | 4, 5 | `INDEX_OFFSET`, `INDEX_COUNT` | index byte offset and count |
  | 6 | `INDEX_BYTES` | bytes per index: 2 up to 65536 vertices, else 4 |
  | 7, 8 | `PROPS_OFFSET`, `PROPS_BYTES` | group properties' byte offset and length |
  | 9, 10 | `PAINT_OFFSET`, `PAINT_BYTES` | per-vertex paint ("Vertex paint") byte offset and length; an entry sharing another's geometry has its own |
  | 11, 12 | `OUTLINE_OFFSET`, `OUTLINE_COUNT` | fills: the outline's index byte offset and count (pairs of vertex indices, one per ring edge, in the entry's index size) |
  | 13, 14 | `DISTANCES_OFFSET`, `DISTANCES_COUNT` | dashed lines: their distances, u16 per vertex, the distance from the line's start in `@core.TILE_EXTENT` units, even (MapLibre's `linesofar`, starting again from 0 past `@tess.MAX_LINE_DISTANCE`) |
  | 15, 16 | `PROGRESS_OFFSET`, `PROGRESS_ROWS` | gradient lines (8-aligned): per vertex an f32 share of its line's length and an f32 row, then per row its line's clip start and end (f64s, MapLibre's `lineClips`; 0 and 1 without line metrics), then the longest line in tiles (f64) |
  | 17, 18 | `OFFSETS_OFFSET`, `OFFSETS_COUNT` | offset lines: their offset normals per vertex, two i8 (`@tess.EXTRUDE_SCALE` per unit, MapLibre's `a_offset_normal`) |
  | 19, 20 | `KEY_RUNS_OFFSET`, `KEY_RUNS_COUNT` | circles with a sort key (8-aligned): per run of equal keys the key (f64), first index and index count (u32s) |
  | 21, 22 | `DASHES_OFFSET`, `DASHES_COUNT` | lines dashed by feature, a data-driven `line-dasharray` (8-aligned): per pattern its number count and numbers (f64s; at most 1024 patterns of 64 numbers), then per vertex four u16s, the patterns at the tile's zoom minus one, at it and plus one (MapLibre's `dashDependencies`; 0xffff none, drawn solid) and 0. Such entries never share geometry |

- 4-byte aligned vertex and index data at those offsets. Entries may point at the
  same data (layers with the same geometry): an alias copies every word of the entry
  it shares but the paint's. Fill vertices are x, y as i16
  (`FILL_VERTEX_BYTES` 4); line and circle vertices add extrusion x, y, side and
  along as i8 (`LINE_VERTEX_BYTES` 8). Extrusion vertices
  (`EXTRUSION_VERTEX_BYTES` 24) are x, y, normal x, y, z (times 2^14; x's lowest
  bit set on the top edge), the distance along the ring's walls (0 on roofs;
  MapLibre's `edgeDistance`), and the feature's centroid x, y as i16, then its
  base and height at the tile's zoom and one deeper as u16 decimeters (0 to
  6553.5 m). Coordinates are in `@core.TILE_EXTENT` units. A symbol entry's vertex
  range holds its labels and it has no indices.
- Group properties: u32 count, then per entry a key (UTF-8) and a property value.
  The geometry type goes under `$type` (`@core.GEOMETRY_TYPE_KEY`) and the feature
  id, when paint reads `["id"]`, under `$id` (`@style.FEATURE_ID_KEY`). The glue
  decodes them into prototype-less objects.
- A tile is at most `MAX_PACKED_BYTES` (64 MiB); a bigger one is rejected.

## Vertex paint (`style/vertex_paint.mbt`, written by `worker/processor.mbt`)

The data-driven paint of fill, line, circle and heatmap layers that do not read feature
state, per vertex in the order of the layer's vertices: for each property of
`@style.StyleLayer::vertex_paint` (in the order of the `@style.SLOT_*` slots: color,
opacity, width or radius, stroke color, stroke opacity, stroke width; a fill's outline
color takes the stroke color slot, a line's gap width and offset the stroke opacity and
width slots, a heatmap's weight the opacity slot and its radius the size slot), its value at each zoom stop of its top-level zoom
curve (one value when it has none), each a u32 word: a color as RGBA bytes (red in the
lowest byte, straight alpha), a number as a 32-bit float. Both sides derive the layout
from the style, so the packed tile carries only the bytes; the renderer points each
slot's attribute at the stop below the current zoom and mixes it with the next.

## Labels (`worker/labels.mbt`, read by `worker/js/symbols.mjs`)

A symbol layer entry (`KIND_SYMBOL` 4) of the packed tile keeps its labels in its
vertex range (no indices):

- u8 text anchor (`center`, `left`, `right`, `top`, `bottom`, `top-left`,
  `top-right`, `bottom-left`, `bottom-right`), u8 allow overlap, u8 ignore
  placement, u8 vertical writing;
- f64 offset x, offset y, max width, line height (ems), padding (px);
- u8 text justify (`auto`, `left`, `center`, `right`), u8 variable anchor count, then
  per variable anchor its u8 code (as the text anchor) and f64 offset x, y (ems,
  MapLibre's `text-variable-anchor-offset` with its baseline shift);
- u8 placement (`point`, `line`, `line-center`), u8 keep upright, f64 spacing (px),
  max angle (degrees);
- u8 1 if the layer has `icon-image`, then: u8 icon anchor (as the text anchor),
  u8 allow overlap, ignore placement, optional, text optional, rotation and pitch
  alignment (1 for `map`, after `auto` is resolved), keep upright, u8 text fit
  (`none`, `width`, `height`, `both`); f64 offset x, y (px at size 1), padding top,
  right, bottom, left (px), text fit padding top, right, bottom, left (px);
- u8 font count F (at most 32), then F UTF-8 faces: a `text-font` stack's style, weight
  ("" for none named) and CSS family list on lines of their own (`@style.font_face`);
  font 0 is the map's own (`fontFamily`), font i the i-th face;
- u32 label count;
- per label: u32 index of its feature in the source layer, i16 anchor x, y
  (`TILE_EXTENT` units, inside the tile; 0 along lines), f64 text size
  (px), f64 sort key (`symbol-sort-key`, 0 without one), u8 font, u8 `text-transform` (0
  none, 1 uppercase, 2 lowercase), f64 `text-letter-spacing` (ems), f64 `text-rotate`
  (degrees), u32 part count, then each part of the text as a property value (numbers and
  booleans are written out by the glue) or, for a `format` result, tag 6, u32 section count and
  per section its UTF-8 text, f64 `font-scale` (NaN without one), u8 `vertical-align` (0
  bottom or none, 1 center, 2 top), u8 font (255 for the label's) and u8 1 and its
  `text-color` as straight RGBA bytes, or u8 0; with an icon, u32 part count and the parts
  of its image's name, f64 `icon-size` (at the tile's zoom plus one, as MapLibre lays
  icons out) and f64 `icon-rotate` (degrees). A label has text, an icon or both;
- along lines, one label per feature, then its lines: u32 line count, per line u32
  point count and i16 x, y per point (`TILE_EXTENT` units, clamped to i16). The glue
  finds the anchors (`worker/js/line-labels.mjs`).

## Symbol vertices (`worker/js/symbols.mjs`)

What the display worker sends for a symbol entry, 16 bytes per vertex, 4 per glyph
quad (corners top-left, top-right, bottom-right, bottom-left):

- i16 anchor x, y (`TILE_EXTENT` units);
- i16 corner offset x, y from the anchor in 16ths of a CSS pixel, y down (a quad covers its
  glyph's SDF bitmap and the pixel of padding `label.Atlas` leaves around it);
- u16 glyph index into the entry's `codepoints` and u16 corner (0-3), which the main
  thread turns into atlas pixel coordinates before upload;
- u16 the label's text size in 1/16 px (not scaled by a section's `font-scale`, as MapLibre's
  SDF edges are not), u16 0.

With `format` sections that have colors the entry adds `colors`, 8 bytes per vertex:
the section's straight RGBA and 1, or zeros where the label's `text-color` applies.
Glyph keys in `codepoints` are code points plus 2^21 times the font's index in the tile
message's `fonts`; text turned by `text-rotate` has its corners turned and its box is the
envelope of the padded box turned, less the padding.

`labels` holds 19 floats per label: anchor x, y, its text box (min x, min y, max x,
max y in CSS px from the anchor), its feature's index, text size (px), sort key, its
icon's collision box (CSS px at its layout size, padded and turned as MapLibre's
`CollisionFeature`), 1, the first index and index count of its icon's quad (0 without
an icon), its text's layouts V, first index and index count of each layout's quads
(0 without text). A label with variable
anchors is laid out centered; one of several lines has V = 3 layouts one after the
other, justified left, center and right, otherwise V = 1. `anchors` holds the
variable anchors as code, offset x, y.

Along lines a label is an instance per anchor, found as MapLibre does for tiles 1, 2
and 4 times as deep as the source's (it lays labels out again past a source's
maxzoom); its anchor may fall on half units, its box is its collision circle, and its
glyphs' corner offsets are from each glyph's middle. The entry also has `lineLabels`,
6 floats per label: that level (0-2), the anchor's segment, the first point and point
count of its line in `lines` (x, y pairs, `TILE_EXTENT` units), its first glyph in
`glyphOffsets` (each glyph's middle along the line from the anchor, in 24ths of an
em) and its collision circle's diameter (px); and `keepUpright`. The main thread
places each glyph for each frame the camera moved (`map/line_labels.mbt`) into a per-vertex x, y (tile
units) and angle.

A layer with `icon-image` adds `icon`: its layout (`allowOverlap`, `ignorePlacement`,
`optional`, `textOptional`, `rotateWithMap`, `pitchWithMap`, `keepUpright`,
`textFit`, `hasOffset`) and its icons, one quad per label with an icon in `vertices`
and `indices` (`count`, `indexBytes`) laid out as glyph quads but for: corner offsets
at size 1 in 32nds of a CSS px (MapLibre's `getIconQuads`: the image's box a pixel of
it wider on each side, turned by `icon-rotate`), the index of the image in `images`
(its names) in place of the glyph's, and the size times 128. `sdf` is the first
icon's (MapLibre's `sdfIcons`), `rotated` whether any icon is turned. `missing` names
the images the worker did not know (none are drawn for them). Along lines each
instance has its own icon; turned with the line (`rotateWithMap`), the main thread
places it for each frame like a single glyph at the anchor.

## Columnar tile (`tiler/encode.mbt`, read by `worker/column_tile.mbt`)

A GeoJSON source's tile, from the GeoJSON worker to a display worker:

- u32 counts: features F, rings R, points P, keys K;
- F type bytes (`@core.GEOM_POINTS` 1, `GEOM_LINES` 2, `GEOM_POLYGONS` 3, MVT's
  `GeomType` numbers), padded to 4;
- F u32 feature ring ends, R u32 ring point ends (a points feature's points are
  one ring);
- P x, y pairs as i16 (clamped), padded to 4;
- K keys (UTF-8), then per key, per feature, a property value;
- per feature, its id as a property value (absent without one).

Only keys some feature of the tile has are written; with line metrics
`@tiler.CLIP_START` and `CLIP_END` come last (absent where a feature has none). A clustered source's tile has a
feature per point or cluster; a cluster's id is its cluster id, and its properties
are those of "Cluster features".

## Table (`geom/bytes.mbt`)

A `@geom.Table` without feature ids:

- u32 counts: features F, parts P, rings R, points N, keys K;
- F kind bytes (0 none, 1 Point, 2 MultiPoint, 3 LineString, 4 MultiLineString,
  5 Polygon, 6 MultiPolygon), padded to 4;
- u32 ends: F part ends, P ring ends, R point ends;
- 2N f64 coordinates;
- K keys (UTF-8), then per key, per feature, a property value.

## Display worker messages (`worker/js/worker.mjs`)

In:

- `{type: "init", wasm, style, symbols, font}`: the wasm URL, the style ("Compiled
  style", a Uint8Array), whether it has symbol layers (the label code is then loaded
  ahead of the first tile) and the CSS font family labels are drawn in. The wasm is
  instantiated with `{host, Math}`: the host's `Math` (`worker/host_math.mbt`) and
  `hostText`'s (`wasmio/js/host.mjs`) `host.text_char`, `text_number`,
  `number_text` and `text_code` for the expressions' `Number(string)` and
  `String(number)`, a UTF-16 code unit per call, and `host.intl(op, flags, x, y, z, la,
  lb)` for `Intl` (`number-format`, collators): its strings are the text, the first two
  `la` and `lb` code units long (`worker/linear_memory.mbt` `host_intl`).
- `{type: "tile", id, url, init, source, z, x, y, dem, raster}`: fetch and process a
  tile (`source` is the index in the style's sources; `x` and `y` place features for
  `within` and `distance`; `source`, `z`, `x` and `y` must be integers). With neither
  flag a vector tile; with `dem: true` a `raster-dem` tile (PNG), whose pixels are
  decoded into slopes; with `raster: true` a raster tile, sent as an ImageBitmap
  (premultiplied). `init` is what the map's `transformRequest` gave (never for a
  `pmtiles://` URL): string `headers` and a `credentials` mode (else none are sent).
  Other URLs must be http(s). A `url` of the form `pmtiles://<archive URL>/z/x/y` is
  read from that PMTiles archive with range requests (`worker/js/pmtiles.mjs`, at most
  16 archives open).
- `{type: "tile", id, bytes, source, z, x, y}`: process a tile already loaded (a GeoJSON
  source's columnar tile, an ArrayBuffer).
- `{type: "cancel", id}`.
- `{type: "style", style, symbols}`: the compiled style tiles asked for from now on are
  made with (`Map::set_style`; requests made before it were cancelled).
- `{type: "query", id, kind, tile, source, z, x, y, request}`: a query of the
  tile sent for request `tile` (the worker keeps each vector or GeoJSON tile's
  bytes until it is dropped): `kind` "rendered" with a "Query" `request`, or
  "features" with a source layer's name (a u32 length and UTF-8) and a filter
  ("Compiled style"'s optional expression). z/x/y place the result's geometry.
- `{type: "ranges", id, tile, ids}`: where the features with these ids (strings,
  as `String(id)`) lie in the entries of the tile sent for request `tile`.
- `{type: "drop", id}`: forget the bytes of the tile sent for request `id`.
- `{type: "images", images, loading}`: the style images icons are laid out with,
  `[name, width, height, pixelRatio, sdf]` each; while `loading` (a sprite is on its
  way) tiles wait, as MapLibre's do for icons.

Out:

- `{type: "ready"}`, `{type: "error", message}` (also for a style that failed; tiles
  are then made with the previous one). Messages without an integer `id` are ignored;
  after a failed init, tiles get `tile-error` and queries and ranges empty answers.
- `{type: "tile", id, layers, glyphs, fonts}`: per entry `{entry, layer, kind, vertices,
  indices, count, indexBytes, shared, props, paint}` (`entry` its index in the packed
  tile; symbol entries with no label, icon or missing image are left out). Buffers are transferred,
  never copied; `shared` is the position in `layers` of an earlier entry whose buffers
  it reuses (or -1); `props` the group properties (or null); `paint` the entry's own
  per-vertex paint (an ArrayBuffer, also over shared geometry). Then, from "Packed
  tile" (null when absent): `outline` and `outlineCount` (the fill outline's indices),
  `distances`, `progress` (8 bytes per vertex), `clips` (Float64Array of the rows'
  clips, then the longest line) and `offsets`; `keyRuns` (Float64Array of key, first
  index, index count per run); and for lines dashed by feature `dashPatterns` (an array
  of number arrays) and `dashMarks` (four u16s per vertex). Symbol entries add
  `labels`, `codepoints` (Uint32Array), `anchors`, `justify`, `allowOverlap`,
  `ignorePlacement` and `padding`, `colors` with section colors, `lineLabels`,
  `lines`, `glyphOffsets` and `keepUpright` along lines, and with icons `icon` and
  `missing` ("Symbol vertices"). `glyphs` are the
  SDF glyphs the worker drew since its last tile, `{cp, width, height, data}` (one
  byte per pixel, TinySDF at 48 px with a 6 px buffer; `cp` a glyph key as in
  `codepoints`): each is sent once per worker, so the main thread takes them even
  from tiles it no longer wants. `fonts` are the worker's faces, "" first for the map's
  own font; the main thread numbers them for its atlas. A tile the server does not
  have (404, 204, or missing from a PMTiles archive) is `{type: "tile", id, layers: []}`.
- `{type: "tile-error", id, message}`.
- A raster tile's message has one entry `{entry: 0, layer: -1, kind: 7, image}` (kind
  `KIND_RASTER` of `core/kinds.mbt`), `image` an ImageBitmap (transferred) for every
  raster layer of the source.
- `{type: "ranges", id, entries}`: per packed entry with any of the ids,
  `{entry, ranges}`, `ranges` holding (first index, index count, outline first index,
  outline index count, position in `ids`) quintuples ("Feature ranges"); none if the
  tile is gone.
- `{type: "query", id, hits}`: the query's records ("Query result") as
  `{layer, index, distance, feature}`, `feature` a GeoJSON feature in
  longitude and latitude (@mapbox/vector-tile's `toGeoJSON`) with prototype-less
  `properties`; no hits if the tile is gone or the request is refused (an `error`
  message says why it was refused).
- A `raster-dem` tile's message has one entry `{layer: -1, kind: 5, image, edges,
  elevations, size}` (kind `KIND_HILLSHADE` of `core/kinds.mbt`): `image` holds the
  slopes (`@raster.hillshade_slopes`, two bytes per pixel of a `size` x `size` tile
  with a pixel of border, rows of `size + 2`; `size` from 2 to 1024), `edges` (Float64Array, 8 × `size`) its border
  elevations (`@raster.dem_edges`) and `elevations` (Float32Array) every pixel's
  height in meters (no data as 0), for its hillshade layers and terrain.

## Feature ranges (`worker/ranges.mbt`, read by `worker/js/ranges.mjs`)

What `feature_ranges` gives after `process_tile`, for the entries of layers whose
paint reads the feature state (kept by the worker glue, never sent whole): u32
entry count, then per entry u32 packed entry index, u32 feature count and per
feature its id as a property value (the source's `promoteId` property for the
layer, or the tile's or GeoJSON id; a boolean as 0 or 1, null without one), u32 first index and u32 index count, then the same of
its fill outline's indices (0 and 0 for other kinds).

## Compiled style (`style/compiled_writer.mbt`, read by `style/compiled_reader.mbt`)

The style as the main thread compiled it (`Style::to_compiled`), so display workers
never parse JSON or compile expressions (`Style::from_compiled`). Tags and tables are in
`style/compiled.mbt`. An enumeration is a u8, its index in its table there (`layer_kinds`,
`source_kinds`, `placements`, `z_orders`, `fits`, `joins`, `caps`, `spaces`, `ops`,
`cmp_ops`; `anchor_values` and `justify_values` in `style/anchor.mbt`), and a reader
fails on an index past it; a flag is a u8 0 or 1; an optional item is a flag, then the
item if 1; a list is a u32 count and its items; a pair or four sides are 2 or 4 f64.

- Value: a "Property values" tag and payload (0 to 4), then `VALUE_COLOR` 6 a color
  (4 f64, straight RGBA 0 to 1), `VALUE_LIST` 7 a list of values, `VALUE_FAILED` 8
  `Failed` (also written for a formatted text or a collator, which only expressions
  make).
- Expected: u8 0 any, 1 color, 2 number, 3 boolean, 4 string, 5 array: its item
  Expected and u32 length (-1 any).
- Expr: u8 tag, the `EXPR_*` constant of its variant: 0 `Lit`, 1 `Get`, 2 `Has`, 3 `Id`,
  4 `GeometryType`, 5 `Zoom`, 6 `LineProgress`, 7 `HeatmapDensity`, 8 `Elevation`,
  9 `Not`, 10 `All`, 11 `Any`, 12 `Compare`, 13 `In`, 14 `Match`, 15 `Case`,
  16 `Coalesce`, 17 `Interpolate`, 18 `Step`, 19 `FeatureState`, 20 `Assert`,
  21 `Coerce`, 22 `Call`, 23 `Collate`, 24 `Within`, 25 `Distance`, 26 `Accumulated`.
  Then its fields in order: values, UTF-8 keys, nested Exprs; an Expr array is a list,
  a stop f64 input and Expr, a `match` arm its labels (a list of values) and Expr, a
  `case` arm two Exprs. `Interpolate` is u8 0 exponential (f64 base) or 1 cubic Bézier
  (4 f64), u8 color space, input and stops (at least one); `Step` input, first output
  and stops; `Assert` and `Coerce` an Expected and an Expr array; `Compare`, `Collate`
  and `Call` lead with their operator's u8, and a `Call` must have as many arguments as
  `compile` gives its operator (`Format` five per section). Coordinates are a list of
  f64s (an even count, at least one longitude, latitude pair) and a polygon a list of
  at least one ring of them: `Within` is a list of polygons; `Distance` a list of
  geometries, each u8 0 a point (two f64), 1 a line (coordinates), 2 a polygon or 3
  another type. A whole expression may have at most `MAX_EXPR_NODES` nodes (values
  included) and 4 × `MAX_EXPR_DEPTH` levels; a reader refuses more.
- Source: UTF-8 id, u8 kind, u32 min zoom, max zoom, tile size, the DEM encoding
  (u8 0 mapbox, 1 terrarium, 2 gsi, or 3 custom with 4 f64), u32 buffer, f64
  tolerance, `promoteId` (u8 0 feature id, 1 a property's UTF-8 name, 2 u32 count of
  source layer and property UTF-8 pairs). Tile URLs, bounds and scheme stay on the
  main thread.
- Layer: UTF-8 id, u8 kind, UTF-8 source and source layer, f64 min and max zoom,
  optional filter, u32 `filter_id`; Exprs color, opacity, width, radius, stroke
  width, stroke color, stroke opacity, halo color and halo width; optional text
  layout, icon layout, icon paint (an Expr array of 5, `IconPaint::exprs`: color,
  opacity, halo color, width and blur), extrusion (Exprs height and base, flag
  vertical gradient) and heatmap paint (an Expr array of 3: weight, intensity,
  color); u8 join and cap, f64 miter and round limits, flag antialias, optional
  Exprs outline color, dash array, gradient and pattern; Exprs gap width, offset,
  blur and translate (`*-translate`, as `@style.translate_at` reads it); flags
  translate-anchor viewport, circle pitch-scale map and circle pitch-alignment map;
  optional sort key (`fill-`, `line-`, `circle-sort-key`). Hillshade, color relief
  and raster paint, terrain, sky and light are drawn on the main thread and left out.
- Text layout (`TextLayout`): Expr array field, Expr size, u8 placement, f64 spacing
  and max angle, flag keep upright, u8 anchor, pair offset, u8 justify, the variable
  anchors (a list of u8 anchor and f64 offset x, y), `variable_stops` (a list of f64
  zoom and such an anchor list), f64 max width and line height, Expr padding, flags
  allow overlap, ignore placement and vertical, optional Exprs sort key and font, an
  Expr array of 3 (letter spacing, transform, rotate), flag cooperative and u8 z order.
- Icon layout (`IconLayout`, without its `layout` JSON): Expr array image, Exprs size
  and rotate, u8 anchor, pair offset, Expr padding, flags allow overlap, ignore
  placement, optional, text optional, rotate with map, pitch with map and keep
  upright, u8 text fit, four sides text fit padding, flag cooperative.
- The style: a list of sources, a list of layers, nothing after.
- Query filters are one optional Expr (`write_expr`, `read_expr`).
- Cluster properties (`write_cluster_properties`, written by `map` for the GeoJSON
  worker, `read_cluster_properties`): a list of keys, each its UTF-8 name and its map
  and reduce Exprs, nothing after.

## Query (`map/query.mbt`, read by `worker/query.mbt`)

A rendered-features query of one tile, little-endian:

- f64 camera zoom, `TILE_EXTENT` units per CSS pixel, `max_pitch_scale_factor`,
  viewport width and height (CSS px), the center's clip w, world pixels per meter,
  the camera's bearing in radians;
- 16 f64: the tile's matrix (`TILE_EXTENT` units to clip space, column-major);
- u32 n, n f64 pairs: the query (one point, or a closed ring) in `TILE_EXTENT`
  units; u32 m, m pairs: the same grown to the point under the camera
  (MapLibre's camera query geometry, used for extrusions);
- u8 1 for every layer (else 0), u32 count and the style layer indices asked for;
- u32 count, then (u32 style layer, u32 feature index) per label the main thread
  found under the query;
- the query's filter ("Compiled style"'s optional expression).

## Query result (`worker/query.mbt`, read by `worker/js/query.mjs`)

u32 record count, then per record: u32 style layer index (-1 for a source query),
u32 feature index, f64 clip depth where an extrusion meets the query (NaN
otherwise), the feature's id as a property value (null without one), u8
geometry type (1 point, 2 line, 3 polygon), u32 extent, u32 ring count, a u32
point count per ring, the points as i32 pairs, then u32 property count and
per property a key (u32 length, UTF-8) and a property value. A key repeated in
a vector tile keeps its first place and last value, as a JS object does.

## GeoJSON worker messages (`geojson_worker/js/worker.mjs`)

In:

- `{type: "init", wasm, propsWasm}`: the module, and the one with expressions
  (`geojson_props_worker`) instantiated for the first source with cluster properties.
  Both import `Math` and `host.number` (`hostNumber`, for numbers past the reader's
  fast path); the one with expressions adds `hostText`'s, as the display worker's.
- `{type: "load", source, url, init | bytes, maxzoom, buffer, tolerance, lineMetrics, cluster, properties}`:
  `source` is an integer naming the source; `url` (http(s)) is fetched with `init`,
  what the map's `transformRequest` gave, checked as a tile's (string `headers` and a
  `credentials` mode, else none are sent), up to `MAX_INPUT_BYTES` (256 MiB);
  `bytes` is the GeoJSON as UTF-8 (an ArrayBuffer). The reader takes at most
  `@geom.MAX_TABLE_POINTS` points, `@formats.MAX_GEOJSON_KEYS` keys,
  `@geom.MAX_TABLE_CELLS` property cells (features times keys) and `MAX_GEOJSON_DEPTH`
  levels of nesting. The options are MapLibre's GeoJSON source options in pixels,
  in the style's ranges (`geojson_tiles/tiles.mbt` `load`; else the load fails):
  `maxzoom` 0 to 24 (`@tiler.MAX_ZOOM`), `buffer` 0 to 512, `tolerance` 0 or more.
  With `lineMetrics` (a boolean) each line feature of a tile has `geojsonvt_clip_start`
  and `geojsonvt_clip_end` (`@tiler.CLIP_START`, `CLIP_END`).
  `cluster` is null, or `{maxZoom, radius, minPoints}` as MapLibre's GeoJSONSource
  derives them (`npm/src/geojson.ts`; `maxZoom` and `minPoints` int32s, `maxZoom` at
  most 30, `radius` finite and not negative); its tiles then hold points and clusters.
  `properties`, with `cluster`, is its `clusterProperties` as "Compiled style"'s
  cluster properties (a Uint8Array); such a source goes to the module with expressions.
  Loading a number again replaces its data once the earlier load has finished.
- `{type: "unload", source}`: forgets the source.
- `{type: "tile", id, source, z, x, y}`: waits until the source has loaded.
- `{type: "cluster", id, source, op, cluster, limit, offset}`: `op` is `"expansion"`,
  `"children"` or `"leaves"` of cluster `cluster` (an int32); `limit` (-1 for all) and
  `offset` (int32s) only for leaves. Waits until the source has loaded.

Out:

- `{type: "loaded", source, features}`, `{type: "error", source, message}`.
- `{type: "tile", id, bytes}`: a columnar tile (transferred), or null when the source
  has nothing there, failed or was never loaded.
- `{type: "cluster", id, result}`: the expansion zoom, or the features as GeoJSON
  points (from "Cluster features"); null if the source does not cluster. Or
  `{type: "cluster", id, error}` (no such cluster, source not loaded).

The main thread's `map` asks for GeoJSON tiles through a provider (`map/dom.mbt`
`Provider`, served by `npm/src/geojson.ts`): `(source id, z, x, y) =>
Promise<ArrayBuffer | null>`.

## Cluster features (`tiler/encode.mbt`, read by `geojson_worker/js/features.mjs`)

u32 feature count, then per feature: f64 longitude and latitude, its id as a
property value (a cluster's is its cluster id), u32 property count and per
property a key (UTF-8) and a property value. A cluster's properties are its
cluster properties' (reduced values) then `cluster`, `cluster_id`, `point_count` and
`point_count_abbreviated`, which win over a cluster property of the same name.

## Analysis worker messages (`analysis_worker/js/worker.mjs`)

In:

- `{type: "init", wasm, geometry, proj}`: the analysis, geometry and
  coordinate system wasm URLs (the last two are fetched on their first use). The
  analysis module imports `Math` and `host.number` (`hostNumber`), proj.wasm only
  `Math`, the geometry module nothing.
- `{type: "call", id, op, ...}`, run one after another in arrival order. `op` and its arguments
  (no argument may be named `op`):
  - `load` with `url` (fetched without credentials), `bytes` (GeoJSON as UTF-8) or
    `table` (an ArrayBuffer of "Table" bytes, as mbmap/data reads them; `load_table`),
    and `crs` (of its coordinates; anything but 4326 is transformed to 4326 by
    the coordinate system module, which every other call then assumes). A
    `crs` is an EPSG code or a Float64Array "CRS definition";
  - `dispose`, `measure` (`kind`: 0 area, 1 length, 2 centroid, 3 bbox), `search`
    (`bbox`), `nearest` (`x`, `y`, `k`, `maxDistance`), `grid` (`bbox`, `cols`,
    `rows`), all with `dataset`;
  - `within` (`points`, `polygons`) and `collect` (`polygons`, `points`, `property`);
  - `loadDem` (`url` a `{z}/{x}/{y}` template, `z`, `bounds`, `encoding` as
    `[kind, r, g, b, base]` with kind 0 Mapbox, 1 Terrarium, 2 GSI, 3 custom),
    `gridValues` (`grid`, `kind` 0 elevations, 1 slope, 2 aspect),
    `gridHillshade` (`grid`, `azimuth`, `altitude`, `zFactor`) and `gridSample` (`grid`,
    `coords` an ArrayBuffer of f64 lng, lat pairs: the elevations there, bilinear as
    GDAL; the grid's zoom and tiles stay in the worker from `loadDem`);
  - geometry, each giving a new dataset: `buffer` (`dataset`, `meters`, `mode` 0
    geodesic or 1 planar, `join` 0 round, 1 miter, 2 square, 3 bevel, `cap` 0
    round, 1 butt, 2 square, `arcTolerance` in meters, `crs` the projected CRS
    a planar buffer is measured in), `dissolve` (`dataset`), `merge` (`dataset`) and
    `overlay` (`a`, `b`, `kind` 0 clip, 1 erase, 2 intersect, 3 split); the datasets go to
    the geometry module and back as Table bytes;
  - `relate` (`a`, `b`, `predicate` 0 intersects, 1 contains, 2 within, 3 covers, 4
    coveredBy, 5 touches, 6 crosses, 7 overlaps, 8 equals, or -1 with `pattern` a DE-9IM
    pattern packed three bits a cell, `npm/src/relate-pattern.ts`): an Int32Array of row
    pairs, both datasets sent to the relation module as Table bytes; with `pair` [i, j],
    the matrix of those rows as JTS writes it (`"FF2F11212"`);
  - `network` (`dataset`, `tolerance`): a handle of the routing module's graph of the dataset's
    lines; `route` (`network`, `from`, `to`): an f64 array, the weight in km then x, y pairs,
    empty for no path; `disposeNetwork` (`network`);
  - `viewshed` (`grid`, `observer` [lng, lat], `options` observerHeight, targetHeight,
    maxDistance, curvatureCoeff, mode 0 normal, 1 DEM, 2 ground, visible, invisible, outOfRange):
    `{width, height, bounds, values}` from the viewshed module: `viewshed_window` (the same
    arguments) answers the cells it reads as i32 x, y, width, height; `viewshed` takes those
    cells' elevations as f64s (its arguments: width, height, geotransform, observer x, y, the
    options, semi-major axis (NaN for none), mode 0 normal, 1 DEM, 2 ground, the three values,
    then the cells' x, y, width, height, width 0 for the whole grid) and answers the output's
    width, height and geotransform, then its cells;
  - `surface` (`dataset`, -1 for the grids, `fn` an export of surface_worker, `args` its numbers,
    `text` a property name, `numbers` f64s such as breaks): the module's input is the table, the
    text as UTF-8 and the f64s one after another; a new dataset, or for `dbscan` two f64s per
    feature (cluster, 0 core, 1 edge, 2 noise, 3 not a point) and for `kmeans` the row count,
    each row's cluster and the centroids;
  - `shapes` (`dataset`, `shape` one of `simplify` (tolerance, high quality 0 or 1), `convex`,
    `concave` (concavity, length threshold), `delaunay`, `voronoi` (min x, min y, max x,
    max y), `line_slice` (start x, y, stop x, y), `args` those numbers): a new dataset from
    the shape module; `nearestOnLine` (`dataset`, `x`, `y`): six f64s per feature (x, y,
    dist, location, index, multiFeatureIndex; NaN without lines);
  - `toGeoJSON` (`dataset`, `crs`): its Table bytes, transformed to `crs` when
    given, decoded into a FeatureCollection (`wasmio/js/table.mjs`);
  - `transform` (`coords` an ArrayBuffer of f64 x, y pairs, `from`, `to`): the
    pairs in `to`, NaN where a point is out of the projection's reach.

Out:

- `{type: "result", id, value}`: `{dataset, features}` for `load` and the geometry
  calls, a FeatureCollection for `toGeoJSON`, `{grid, width, height, bounds}` for
  `loadDem` (`bounds` west, south, east, north of the tiles mosaicked), null for
  `dispose`, a Uint8Array for `gridHillshade`, else a Float64Array or Int32Array
  (transferred). `collect` gives count, numeric count and sum per polygon.
- `{type: "result", id, error}`.

Datasets cross to the coordinate system module (proj_worker) as their
coordinates only: `coords_out(dataset)` writes them as f64 x, y pairs,
proj.wasm's `transform_coords(from, to)` maps them, and `with_coords(dataset)`
makes a new dataset from the result (a feature with a NaN keeps its row with no
geometry). proj.wasm names a CRS by EPSG code, or by -1 - the handle
`define_crs` returns for a definition; `crs_kind(id)` is 1 for a geographic CRS,
0 for a projected one.

## Geodesic worker messages (`geodesic_worker/js/worker.mjs`)

In: `{type: "init", wasm}` (instantiated with `{ Math }`), then `{type: "call", id, op, ...}`
with `op` and its arguments, positions as `[lng, lat]`:

- `inverse` (`from`, `to`): a Float64Array of s12, azi1, azi2, a12, S12;
- `direct` (`from`, `azimuth`, `distance`): lat2, lon2, azi2, a12;
- `circle` (`center`, `radius` meters up to 20,000 km, `steps` from 1 to 4096): a ring of
  `steps` lng, lat pairs at equal azimuths from north, then the first again;
- `measure` (`coords` an ArrayBuffer of f64 lng, lat pairs, `closed`, `step` optional):
  `{measured}`, a Float64Array of the length, the area (NaN for a line) and the distance to
  each vertex (`@geodesic.Geodesic::measure_path`), and with a `step` also `path`, the
  pairs densified along each geodesic (a ring back to its first vertex) with longitudes
  unrolled (`densify`, at most 1,000,000 points).

Out: `{type: "result", id, value}` or `{type: "result", id, error}`.

## Services worker messages (`services_worker/js/worker.mjs`)

In: `{type: "init", wasm}` (instantiated with `host.number`, `wasmio/js/host.mjs`), then
`{type: "call", id, op: "esri", bytes, format}`: `bytes` an ArrayBuffer of an ArcGIS query
result, `format` `"json"` (`f=json`, `@formats.read_esri_json`) or `"pbf"` (`f=pbf`,
FeatureCollection.proto's `FeatureResult`, `@formats.read_esri_pbf`).

Out: `{type: "result", id, value: {features, exceeded}}`, the GeoJSON features (each with its
`id` when it has one) and the result's `exceededTransferLimit`, or `{type: "result", id, error}`.

## Data worker messages (`data_worker/js/worker.mjs`)

In: `{type: "init", wasm, proj, prj, xml, geotiff}` (data.wasm instantiated with `{ host: { number,
decode, text_code, number_text } }` from `dataImports` in `data_worker/js/read.mjs`; `proj` the URL
of proj.wasm, `prj` of prjwkt.js, `xml` of xml.wasm, the KML and GPX module `xml_worker` instantiated
with `{ Math, host }` (`hostText`), and `geotiff` of geotiff.wasm, each loaded on first use), then `{type: "call", id, op: "read",
format, options, ...}` with the data as one of `url` (http(s), fetched with `init`'s string
`headers` and `credentials`, none sent otherwise), `blob` or `bytes` (an ArrayBuffer), at most
`MAX_INPUT_BYTES`, or for a shapefile `parts: {shp, dbf?, prj?, cpg?}`, each such a source, or
`{type: "call", id, op: "write", format, table, ids, options}` (below). Calls run one after another. `options` for every format: `crs` (an EPSG code or a "CRS definition", for
coordinates the data does not tag; refused for KML and GPX, which are EPSG:4326), `layer` (a
string), `encoding` (a .dbf's, a label or code page), `bbox` (FlatGeobuf only, four finite numbers):

- `format` `"csv"`, with `options` `{delimiter, header, dynamicTyping, latitude, longitude,
  geometry}` (`delimiter` a character code or -1 to guess; the column names optional). The wasm's
  `read_csv(names, delimiter, header, typing)` takes the three names, each ended by a NUL byte
  (empty: found by name), before the CSV in its input;
- `"wkt"` (`read_wkt`) or `"wkb"` (`read_wkb`: binary, or hexadecimal text when the first byte
  that is not white space is neither 0 nor 1);
- `"shapefile"`: a zip archive (by its first bytes; read by `npm/src/zip.ts`, `data-zip.js` in
  dist, its `layer` or first .shp with the .dbf, .prj and .cpg of the same name), a .shp (by a URL
  ending in `.shp`, the .dbf, .prj and .cpg beside it too, 404 meaning none) or `parts`. The wasm's
  `read_shapefile(shp, dbf)` takes the .shp's `shp` bytes and the .dbf's `dbf` (0 for none) one
  after the other, and calls `host.decode(addr, len)` for .dbf text that is not ASCII: the host
  decodes those bytes of its memory in the encoding it chose (option, .cpg, language driver byte
  29, UTF-8), removes NULs, trims, keeps the text and returns its length in UTF-16 code units,
  which `host.text_code(i)` gives one by one;
- `"topojson"`: `read_topojson(name)` takes the object's name (UTF-8, `name` bytes; -1 for the
  first) before the TopoJSON;
- `"kml"` (xml.wasm's `read_kml`; a zip archive, by its first bytes, is a KMZ whose `doc.kml`, else
  first `.kml` entry, `kmlOfKmz` in `data_worker/js/read.mjs` inflates first through
  `npm/src/zip.ts`) or `"gpx"` (`read_gpx`), the document as UTF-8 in that module's input. Nested
  property values are JSON text. xml.wasm has its own `ids_out()` (KML's Placemark ids), and its
  rows skip the CRS step below;
- `"geojson"`: `read_geojson()`, the GeoJSON source's reader (`@formats.read_geojson`), ids kept
  for `ids_out()`; refused with `crs`;
- `"flatgeobuf"`: `read_flatgeobuf(ids)` takes the file (ids -1: the whole of it, its index skipped)
  or, with `bbox`, the bytes up to the end of its header, the features `data_worker/js/fgb.mjs`
  (`data-fgb.js`) finds in its index one after another (each with its u32 size), then `ids` u32
  feature indices. With a `url`, those are read by HTTP range requests (`Range` added to `init`'s
  headers; a 200 answer is the whole file, read as bytes). Feature indices are the rows' ids; the
  header's CRS (`crs.code` of org EPSG or none, else `crs.wkt` read as a .prj) is the data's unless
  `options.crs` is given.

After a read, `srids_out()` writes each row's SRID as an i32 (0 where none was given) and returns
their count, or 0 when no row had one; `layers_out()` writes the input's layer names (TopoJSON
objects), each a u32 length and UTF-8; `ids_out()` writes a property value per row (the feature
ids, "Property values") and returns their length, or 0 without ids. Rows whose SRID (or, without
one, `crs` or the .prj) is not 4326 are taken to longitude and latitude in place through proj.wasm
(`data_worker/js/crs.mjs`, `data-crs.js` in dist): their coordinates as f64 pairs, a call to
`transform_coords` per CRS; a coordinate it cannot reach fails the read.

A write (`op: "write"`) takes `table` (an ArrayBuffer of "Table" bytes), `ids` (an ArrayBuffer of
property values, one per row, or null) and `format` `"csv"` or `"kml"`, and answers with an
ArrayBuffer of UTF-8 (GeoJSON is written by the facade, `JSON.stringify` of `toGeoJSON()`). CSV:
data.wasm's `write_csv(names, delimiter, header, mode)` takes three NUL-ended column names (WKT,
longitude, latitude) before the table, `delimiter` a character code, `mode` 0 (no geometry), 1
(WKT), 2 (longitude and latitude) or 3 (chosen by the rows); `options` `{delimiter, header,
geometryFormat, geometry, longitude, latitude}`. KML: xml.wasm's `write_kml(ids)` takes the table,
then `ids` bytes of ids. Both write numbers through `host.number_text` (`String(x)`).

A raster read (`op: "readRaster"`) takes `url` (with `init`), `blob` or `bytes` and `options`
(npm/src/data.ts `RasterOptions`) and answers with npm/src/data.ts `Raster` (bands as typed
arrays, transferred). geotiff.wasm (`geotiff_worker`, no imports): `parse()` reads the input (the
file's first bytes) and writes "GeoTIFF images", or returns -3 when it needs more (`need()` bytes
from the start); `window(image, x0, y0, x1, y1, fill)` takes u32 sample indices; `block(index,
decoded)` takes one block's bytes (`decoded` 1 when the host inflated or decoded them); `empty(index,
value)` fills a block of no bytes; `bands()` writes each band's little-endian values, padded to 8 bytes. `op: "rasterInfo"` (the same sources) answers npm/src/data.ts `RasterInfo`; `op: "rasterTile"` takes
`options` `{z, x, y, tileSize, bands, range, colors, dem, resampling}` and answers a PNG
ArrayBuffer (Terrarium elevations with `dem`), or null off the file; files in a CRS other than
EPSG:3857 or 4326 get every pixel center through proj.wasm's `transform_coords`. A map's `geotiff` sources get
their tiles this way through the engine's tile provider (map/dom.mbt `Provider`), which hands them
to a display worker as raster or DEM tile bytes. `op: "reprojectTile"` takes `spec` (`{crs, grid}` or
`{crs, image}`, npm/src/services/common.ts `ReprojectedSource`, checked by data_worker/js/reproject.mjs
`isReprojected`), `options` `{z, x, y, tileSize}` and `init` (headers and credentials for every image it
fetches), and answers a PNG ArrayBuffer or null where nothing shows; `reprojected` sources get their tiles
this way too.

Out, for a read: `{type: "result", id, value: {table, ids, layer, layers}}` with `table` an
ArrayBuffer of "Table" bytes and `ids` of the ids' property values or null (both transferred),
`layer` the layer read or null and `layers` every layer of the input; for the other ops `value` is
what is said above. A call that fails: `{type: "result", id, error}`.

## GeoTIFF images (`geotiff_worker/read.mbt` `parse`)

u32 little-endian (1 or 0), u32 image count; per image: i32 width, height, tiled (0 or 1), block
width, block height, samples, planar, compression, predictor, photometric (-1 absent), NewSubfileType,
SubfileType, EPSG code (0 for none), raster type; per sample u32 bits and u32 sample format; then f64
arrays (u32 count, values) ModelPixelScale, ModelTiepoint, ModelTransformation, block offsets, block
byte counts; u8 1, a u32 length and UTF-8 for GDAL_NODATA's text, else u8 0; i32 JPEGTables
length (-1 absent) and its bytes; padding to 4.

## CRS definition (`proj/encoding.mbt`, written by `npm/src/projstring.ts` and `npm/src/prjwkt.ts`)

A parsed PROJ string as 34 f64s; angles in radians, NaN where a parameter was
not given.

| slot | value |
|---|---|
| 0 | projection: index into longlat, merc, tmerc, utm, lcc, aea, aeqd, stere, sterea, cass, laea, eqc, eqdc, sinu, eck6, moll, robin, cea, mill, poly, omerc, somerc, krovak, ortho, gnom, eqearth, bonne |
| 1, 2 | semi-major and semi-minor axes (m) |
| 3 | `+R_A` (1 or 0) |
| 4 | how many `towgs84` values follow: 0 (no datum shift), 3 or 7 |
| 5–11 | `towgs84`: dx, dy, dz (m), rx, ry, rz (arc seconds), scale (ppm) |
| 12 | `+datum=WGS84` spelled so (proj4js's shortcut) |
| 13 | `to_meter` (NaN: meters) |
| 14 | prime meridian east of Greenwich |
| 15 | `lon_wrap` |
| 16–25 | `lat_0`, `lat_1`, `lat_2`, `lat_ts`, `lon_0`, `lon_1`, `lon_2`, `alpha`, `gamma`, `lonc` |
| 26–28 | `x_0`, `y_0`, `k_0` (or `k`) |
| 29 | `zone` |
| 30–33 | `south`, `no_uoff` (or `no_off`), `no_rot`, `czech` (1 or 0) |
