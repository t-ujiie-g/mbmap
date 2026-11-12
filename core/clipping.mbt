///|
/// Most planes a clipping (`Map::set_clipping`, mbmap/3d's layers) cuts with: the
/// shaders' uniform arrays are this long.
pub const MAX_CLIP_PLANES : Int32 = 16

///|
/// Most rings a clipping cuts out.
pub const MAX_CLIP_RINGS : Int32 = 8

///|
/// Most vertices of all a clipping's rings together.
pub const MAX_CLIP_POINTS : Int32 = 64
