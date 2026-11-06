///|
/// `PackedTile` layer kinds, as the renderer reads them.
pub const KIND_FILL : Int32 = 1

///|
pub const KIND_LINE : Int32 = 2

///|
/// Circles share the line vertex layout: a quad per point whose extrusion
/// is ±`@tess.EXTRUDE_SCALE` (see `@tess.add_points`).
pub const KIND_CIRCLE : Int32 = 3

///|
/// Labels of a symbol layer: the entry's vertex range holds them (docs/FORMATS.md,
/// "Labels"); the worker glue lays them out into glyph quads.
pub const KIND_SYMBOL : Int32 = 4

///|
/// A `raster-dem` tile's slopes for its source's hillshade layers (the worker's
/// entry has layer -1: it serves every hillshade layer of the source).
pub const KIND_HILLSHADE : Int32 = 5

///|
/// Extruded polygons (`@tess.ExtrusionBuffers`), `@worker.EXTRUSION_VERTEX_BYTES` per vertex.
pub const KIND_EXTRUSION : Int32 = 6

///|
/// A raster tile's image: like a DEM tile's entry, layer -1 serves every
/// raster layer of the source.
pub const KIND_RASTER : Int32 = 7
