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
  (`KIND_FILL` 1, `KIND_LINE` 2, `KIND_CIRCLE` 3), vertex byte offset and length,
  index byte offset, index count, bytes per index (2 up to 65536 vertices, else 4),
  group properties byte offset and length (0 if none).
- 4-byte aligned vertex and index data at those offsets. Entries may point at the
  same data (layers with the same geometry). Fill vertices are x, y as i16
  (`FILL_VERTEX_BYTES` 4); line and circle vertices add extrusion x, y, side and
  along as i8 (`LINE_VERTEX_BYTES` 8). Coordinates are in `@core.TILE_EXTENT`
  units.
- Group properties: u32 count, then per entry a key (UTF-8) and a property value.
  The glue decodes them into prototype-less objects.

## Labels (`worker/labels.mbt`, read by `worker/js/symbols.mjs`)

A symbol layer entry (`KIND_SYMBOL` 4) of the packed tile keeps its labels in its
vertex range (no indices):

- u8 text anchor (`center`, `left`, `right`, `top`, `bottom`, `top-left`,
  `top-right`, `bottom-left`, `bottom-right`), u8 allow overlap, u8 ignore
  placement, u8 vertical writing;
- f64 offset x, offset y, max width, line height (ems), padding (px); u32 label count;
- per label: i16 anchor x, y (`TILE_EXTENT` units, inside the tile), f64 text size
  (px), f64 sort key (`symbol-sort-key`, 0 without one), u32 part count, then each part of the text as a property value (numbers and
  booleans are written out by the glue).

## Symbol vertices (`worker/js/symbols.mjs`)

What the display worker sends for a symbol entry, 16 bytes per vertex, 4 per glyph
quad (corners top-left, top-right, bottom-right, bottom-left):

- i16 anchor x, y (`TILE_EXTENT` units);
- i16 corner offset x, y from the anchor in quarter CSS pixels, y down;
- u16 glyph index into the entry's `codepoints` and u16 corner (0-3), which the main
  thread turns into atlas pixel coordinates before upload;
- u16 text size in 1/16 px, u16 0.

`labels` holds 8 floats per label: anchor x, y, its text box (min x, min y, max x,
max y in CSS px from the anchor), first index and index count of its quads.

## Columnar tile (`tiler/encode.mbt`, read by `worker/column_tile.mbt`)

A GeoJSON source's tile, from the GeoJSON worker to a display worker:

- u32 counts: features F, rings R, points P, keys K;
- F type bytes (1 points, 2 lines, 3 polygons), padded to 4;
- F u32 feature ring ends, R u32 ring point ends (a points feature's points are
  one ring);
- P x, y pairs as i16 (clamped), padded to 4;
- K keys (UTF-8), then per key, per feature, a property value.

Only keys some feature of the tile has are written.

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

- `{type: "init", wasm, style, font}`: the wasm URL, the style JSON text and the
  CSS font family labels are drawn in.
- `{type: "tile", id, url, source, z}`: fetch and process a vector tile (`source` is
  the index in the style's sources).
- `{type: "tile", id, bytes, source, z}`: process a tile already loaded (a GeoJSON
  source's columnar tile, an ArrayBuffer).
- `{type: "cancel", id}`.

Out:

- `{type: "ready"}`, `{type: "error", message}`.
- `{type: "tile", id, layers, glyphs}`: per entry `{layer, kind, vertices, indices,
  count, indexBytes, shared, props}`. Buffers are transferred, never copied;
  `shared` is the index of an earlier entry whose buffers it reuses (or -1); `props`
  the group properties (or null). Symbol entries add `labels`, `codepoints`
  (Uint32Array), `allowOverlap`, `ignorePlacement` and `padding`. `glyphs` are the
  SDF glyphs the worker drew since its last tile, `{cp, width, height, data}` (one
  byte per pixel, TinySDF at 48 px with a 6 px buffer): each is sent once per
  worker, so the main thread takes them even from tiles it no longer wants.
- `{type: "tile-error", id, message}`.

## GeoJSON worker messages (`geojson_worker/js/worker.mjs`)

In:

- `{type: "init", wasm}`.
- `{type: "load", source, url | bytes, maxzoom, buffer, tolerance}`: `source` is a
  number naming the source; `url` is fetched without credentials, `bytes` is the
  GeoJSON as UTF-8; the options are MapLibre's GeoJSON source options in pixels.
- `{type: "tile", id, source, z, x, y}`: waits until the source has loaded.

Out:

- `{type: "loaded", source, features}`, `{type: "error", source, message}`.
- `{type: "tile", id, bytes}`: a columnar tile (transferred), or null when the source
  has nothing there, failed or was never loaded.

## Analysis worker messages (`analysis_worker/js/worker.mjs`)

In:

- `{type: "init", wasm}`.
- `{type: "call", id, op, ...}`, run one after another in arrival order. `op` and its arguments:
  - `load` with `url` (fetched without credentials) or `bytes` (GeoJSON as UTF-8);
  - `dispose`, `measure` (`kind`: 0 area, 1 length, 2 centroid, 3 bbox), `search`
    (`bbox`), `nearest` (`x`, `y`, `k`, `maxDistance`), `grid` (`bbox`, `cols`,
    `rows`), all with `dataset`;
  - `within` (`points`, `polygons`) and `collect` (`polygons`, `points`, `property`).

Out:

- `{type: "result", id, value}`: `{dataset, features}` for `load`, null for
  `dispose`, else a Float64Array or Int32Array (transferred). `collect` gives
  count, numeric count and sum per polygon.
- `{type: "result", id, error}`.

The main thread's `map` asks for GeoJSON tiles through a provider (`map/dom.mbt`
`Provider`): `(source id, z, x, y) => Promise<ArrayBuffer | null>`.
