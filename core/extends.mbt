///|
pub extend LngLat with @debug.Debug::{to_repr}

///|
pub extend LngLat with Eq::{not_equal, equal}

///|
pub extend MercatorCoord with @debug.Debug::{to_repr}

///|
pub extend MercatorCoord with Eq::{not_equal, equal}

///|
pub extend BBox with @debug.Debug::{to_repr}

///|
pub extend BBox with Eq::{not_equal, equal}

///|
pub extend TileId with @debug.Debug::{to_repr}

///|
pub extend TileId with Eq::{not_equal, equal}

///|
pub extend TileId with Hash::{hash, hash_combine}
