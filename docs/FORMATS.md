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

- u32 entry count, then `LAYER_ENTRY_WORDS` u32s per entry: style layer index, kind
  (`KIND_FILL` 1, `KIND_LINE` 2, `KIND_CIRCLE` 3 also for heatmaps, `KIND_EXTRUSION` 6),
  vertex byte offset and length,
  index byte offset, index count, bytes per index (2 up to 65536 vertices, else 4),
  group properties byte offset and length (0 if none), per-vertex paint byte offset
  and length (0 if none; an entry sharing another's geometry has its own), and for
  fills the outline's index byte offset and count (pairs of vertex indices, one per
  ring edge, in the entry's index size), and for dashed lines the byte offset and
  count of their distances (u16 per vertex: the distance from the line's start in
  `@core.TILE_EXTENT` units, MapLibre's `linesofar` halved, starting again from 0
  past `@tess.MAX_LINE_DISTANCE`; shared with the geometry), and for gradient lines
  the byte offset (8-aligned) and row count of their progress: per vertex an f32
  share of its line's length and an f32 row, then per row its line's clip start and
  end (f64s, MapLibre's `lineClips`; 0 and 1 without line metrics), then the
  longest line in tiles (f64), and for offset lines the byte offset and vertex count
  of their offset normals (two i8 per vertex, `@tess.EXTRUDE_SCALE` per unit:
  MapLibre's `a_offset_normal`; shared with the geometry), and for circle layers with
  a sort key the byte offset (8-aligned) and count of their runs of equal keys: per
  run the key (f64), first index and index count (u32s), and for lines dashed by
  feature (a data-driven `line-dasharray`) the byte offset (8-aligned) and count of
  their patterns: per pattern its number count and numbers (f64s; at most 1024
  patterns of 64 numbers), then per vertex four u16s, the patterns at the tile's
  zoom minus one, at it and plus one (MapLibre's `dashDependencies`; 0xffff none,
  drawn solid) and 0. Such entries never share geometry.
- 4-byte aligned vertex and index data at those offsets. Entries may point at the
  same data (layers with the same geometry). Fill vertices are x, y as i16
  (`FILL_VERTEX_BYTES` 4); line and circle vertices add extrusion x, y, side and
  along as i8 (`LINE_VERTEX_BYTES` 8). Extrusion vertices
  (`EXTRUSION_VERTEX_BYTES` 24) are x, y, normal x, y, z (times 2^14; x's lowest
  bit set on the top edge), the distance along the ring's walls (0 on roofs;
  MapLibre's `edgeDistance` halved), and the feature's centroid x, y as i16, then its
  base and height at the tile's zoom and one deeper as u16 decimeters (0 to
  6553.5 m). Coordinates are in `@core.TILE_EXTENT` units.
- Group properties: u32 count, then per entry a key (UTF-8) and a property value.
  The geometry type goes under `$type` (`@core.GEOMETRY_TYPE_KEY`) and the feature
  id, when paint reads `["id"]`, under `$id` (`@style.FEATURE_ID_KEY`). The glue
  decodes them into prototype-less objects.

## Vertex paint (`style/vertex_paint.mbt`, written by `worker/processor.mbt`)

The data-driven paint of fill, line, circle and heatmap layers that do not read feature
state, per vertex in the order of the layer's vertices: for each property of
`@style.StyleLayer::vertex_paint` (slot order: color, opacity, width or radius, stroke
color, stroke opacity, stroke width; a heatmap's weight takes the opacity slot), its value at each zoom stop of its top-level zoom
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
- F type bytes (1 points, 2 lines, 3 polygons), padded to 4;
- F u32 feature ring ends, R u32 ring point ends (a points feature's points are
  one ring);
- P x, y pairs as i16 (clamped), padded to 4;
- K keys (UTF-8), then per key, per feature, a property value;
- per feature, its id as a property value (absent without one).

Only keys some feature of the tile has are written. A clustered source's tile has a
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
  ahead of the first tile) and the CSS font family labels are drawn in. The wasm imports
  `hostText`'s (`wasmio/js/host.mjs`) `host.text_char`, `text_number`,
  `number_text` and `text_code` for the expressions' `Number(string)` and
  `String(number)`, a UTF-16 code unit per call, and `host.intl(op, flags, x, y, z, la,
  lb)` for `Intl` (`number-format`, collators): its strings are the text, the first two
  `la` and `lb` code units long (`worker/linear_memory.mbt` `host_intl`).
- `{type: "tile", id, url, source, z, x, y}`: fetch and process a vector tile (`source`
  is the index in the style's sources; `x` and `y` place features for `within` and
  `distance`, and every tile message carries them).
- `{type: "tile", id, url, source, z, dem: true}`: fetch a `raster-dem` tile (PNG),
  decode its pixels and send its slopes.
- `{type: "tile", id, url, source, z, raster: true}`: fetch a raster tile and send
  it as an ImageBitmap (premultiplied).
- Any fetched tile may carry `init`, what the map's `transformRequest` gave: string
  `headers` and a `credentials` mode (else none are sent). A `url` of the form
  `pmtiles://<archive URL>/z/x/y` is read from that PMTiles archive with range
  requests (`worker/js/pmtiles.mjs`).
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
  indices, count, indexBytes, shared, props}` (`entry` its index in the packed tile;
  symbol entries without labels are left out). Buffers are transferred, never copied;
  `shared` is the position in `layers` of an earlier entry whose buffers it reuses (or -1); `props`
  the group properties (or null). Line entries add `distances`, `progress`, `clips`
  and `offsets`, circle entries `keyRuns` (Float64Array of key, first index, index
  count per run) ("Packed tile"; null when absent). Symbol entries add `labels`, `codepoints`
  (Uint32Array), `allowOverlap`, `ignorePlacement` and `padding`, and with icons
  `icon` and `missing` ("Symbol vertices"). `glyphs` are the
  SDF glyphs the worker drew since its last tile, `{cp, width, height, data}` (one
  byte per pixel, TinySDF at 48 px with a 6 px buffer; `cp` a glyph key as in
  `codepoints`): each is sent once per worker, so the main thread takes them even
  from tiles it no longer wants. `fonts` are the worker's faces, "" first for the map's
  own font; the main thread numbers them for its atlas.
- `{type: "tile-error", id, message}`.
- A raster tile's message has one entry `{entry: 0, layer: -1, kind: 7, image}`,
  `image` an ImageBitmap (transferred) for every raster layer of the source.
- `{type: "ranges", id, entries}`: per packed entry with any of the ids,
  `{entry, ranges}`, `ranges` holding (first index, index count, position in
  `ids`) triples; none if the tile is gone.
- `{type: "query", id, hits}`: the query's records ("Query result") as
  `{layer, index, distance, feature}`, `feature` a GeoJSON feature in
  longitude and latitude (@mapbox/vector-tile's `toGeoJSON`) with prototype-less
  `properties`; no hits if the tile is gone or the request is refused.
- A `raster-dem` tile's message has one entry `{layer: -1, kind: 5, image, edges,
  elevations, size}`: `image` holds the slopes (`@raster.hillshade_slopes`, two
  bytes per pixel of a `size` x `size` tile with a pixel of border, rows of
  `size + 2`), `edges` (Float64Array) its border
  elevations (`@raster.dem_edges`) and `elevations` (Float32Array) every pixel's
  height in meters (no data as 0), for its hillshade layers and terrain.

## Feature ranges (`worker/processor.mbt`, read by `worker/js/ranges.mjs`)

What `feature_ranges` gives after `process_tile`, for the entries of layers whose
paint reads the feature state (kept by the worker glue, never sent whole): u32
entry count, then per entry u32 packed entry index, u32 feature count and per
feature its id as a property value (the source's `promoteId` property, or the
tile's id; null without one), u32 first index and u32 index count, then the same of
its fill outline's indices (0 and 0 for other kinds).

## Compiled style (`style/compiled.mbt`, written by `map`, read by `worker`)

The style as the main thread compiled it (`Style::to_compiled`), so display workers
never parse JSON or compile expressions. Enumerations are a u8, their variants'
index in declaration order (`LayerKind`, `SourceKind`, `TextAnchor`, ...); a flag
is a u8 0 or 1; an optional item is a flag, then the item if 1.

- Value: a "Property values" tag and payload (0 to 4), 6 a color (4 f64, straight
  RGBA 0 to 1), 7 a list (u32 count, values), 8 `Failed` (also written for a formatted
  text or a collator, which only expressions make).
- Expected: u8 0 any, 1 color, 2 number, 3 boolean, 4 string, 5 array: its item
  Expected and u32 length (-1 any).
- Expr: u8 tag, `Expr`'s variant index (24 `Within`, 25 `Distance` and 26
  `Accumulated` come after `Collate`, 23), then its fields in order: values, UTF-8
  keys, nested Exprs; `Within` is u32 polygon count, per polygon u32 ring count, per
  ring u32 count and f64 longitude, latitude pairs (at least one); `Distance` u32 count
  and per geometry u8 0 a point (two f64), 1 a line (as a ring), 2 a polygon (as
  `Within`'s) or 3 another type; an array is u32 count and items, a stop f64 input and Expr,
  a `match` arm its labels (values) and Expr, a `case` arm two Exprs;
  `Interpolate` is u8 0 exponential (f64 base) or 1 cubic Bézier (4 f64), u8
  color space, input and stops; `Compare`, `Collate` and `Call` lead with their operator's
  u8, and a `Call` must have as many arguments as `compile` gives its operator (`Format`
  five per section). An expression may have at most `MAX_EXPR_NODES` nodes (values
  included) and 4 × `MAX_EXPR_DEPTH` levels; a reader refuses more.
- Source: UTF-8 id, u8 kind, u32 min zoom, max zoom, tile size, the DEM encoding
  (u8 mapbox, terrarium, gsi, or 3 custom with 4 f64), u32 buffer, f64 tolerance,
  `promoteId` (u8 0 feature id, 1 a property's UTF-8 name, 2 u32 count of source
  layer and property UTF-8 pairs). Tile URLs, bounds and scheme stay on the main
  thread.
- Layer: UTF-8 id, u8 kind, UTF-8 source and source layer, f64 min and max zoom,
  optional filter, u32 `filter_id`; Exprs color, opacity, width, radius, stroke
  width, color and opacity, halo color and width; optional text layout, icon
  layout, icon paint (u32 5 and `IconPaint::exprs`), extrusion (height, base,
  vertical-gradient flag) and heatmap paint (u32 3: weight, intensity, color);
  u8 join and cap, f64 miter and round limits, antialias flag, optional outline
  color, dash array, gradient and pattern; Exprs gap width, offset and blur, f64 x and
  y translate (CSS px), flags translate-anchor viewport, circle pitch-scale map and
  circle pitch-alignment map, optional sort key (`fill-`, `line-`, `circle-sort-key`). A text layout is `TextLayout`'s fields
  in order (Expr arrays and pairs as above, the variable anchors as u32 count and
  (u8 anchor, f64, f64)); an icon layout `IconLayout`'s without `layout`.
  Hillshade, color relief and raster paint, terrain, sky and light are drawn on
  the main thread and left out.
- The style: u32 count and sources, u32 count and layers, nothing after.
- Cluster properties (`write_cluster_properties`, written by `map` for the GeoJSON
  worker): u32 count, then per key its UTF-8 name and its map and reduce Exprs.

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
  (`geojson_props_worker`) instantiated for the first source with cluster properties
  (its imports add `hostText`'s, as the display worker's).
- `{type: "load", source, url | bytes, maxzoom, buffer, tolerance, lineMetrics, cluster, properties}`: `source` is a
  number naming the source; `url` is fetched without credentials, `bytes` is the
  GeoJSON as UTF-8; the options are MapLibre's GeoJSON source options in pixels.
  With `lineMetrics` (a boolean) each line feature of a tile has `geojsonvt_clip_start`
  and `geojsonvt_clip_end` (`@tiler.CLIP_START`, `CLIP_END`).
  `cluster` is null, or `{maxZoom, radius, minPoints}` as MapLibre's GeoJSONSource
  derives them (`npm/src/geojson.ts`); its tiles then hold points and clusters.
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

## Cluster features (`tiler/encode.mbt`, read by `geojson_worker/js/features.mjs`)

u32 feature count, then per feature: f64 longitude and latitude, its id as a
property value (a cluster's is its cluster id), u32 property count and per
property a key (UTF-8) and a property value. A cluster's properties are its
cluster properties' (reduced values) then `cluster`, `cluster_id`, `point_count` and
`point_count_abbreviated`, which win over a cluster property of the same name.

## Analysis worker messages (`analysis_worker/js/worker.mjs`)

In:

- `{type: "init", wasm, geometry, proj}`: the analysis, geometry and
  coordinate system wasm URLs (the last two are fetched on their first use;
  proj.wasm is instantiated with `{ Math }`).
- `{type: "call", id, op, ...}`, run one after another in arrival order. `op` and its arguments
  (no argument may be named `op`):
  - `load` with `url` (fetched without credentials) or `bytes` (GeoJSON as UTF-8),
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
  - `toGeoJSON` (`dataset`, `crs`): its Table bytes, transformed to `crs` when
    given, decoded into a FeatureCollection (`analysis_worker/js/table.mjs`);
  - `transform` (`coords` an ArrayBuffer of f64 x, y pairs, `from`, `to`): the
    pairs in `to`, NaN where a point is out of the projection's reach.

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

## CRS definition (`proj/encoding.mbt`, written by `npm/src/projstring.ts`)

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

Out:

- `{type: "result", id, value}`: `{dataset, features}` for `load` and the geometry
  calls, a FeatureCollection for `toGeoJSON`, `{grid, width,
  height, bounds}` for `loadDem`, null for
  `dispose`, else a Float64Array or Int32Array (transferred). `collect` gives
  count, numeric count and sum per polygon.
- `{type: "result", id, error}`.

The main thread's `map` asks for GeoJSON tiles through a provider (`map/dom.mbt`
`Provider`): `(source id, z, x, y) => Promise<ArrayBuffer | null>`.
