///|
pub extend Color with @debug.Debug::{to_repr}

///|
pub extend Color with Eq::{not_equal, equal}

///|
pub extend StyleError with @debug.Debug::{to_repr}

///|
pub extend StyleError with Eq::{not_equal, equal}

///|
pub extend LayerKind with @debug.Debug::{to_repr}

///|
pub extend LayerKind with Eq::{not_equal, equal}

///|
pub extend Join with @debug.Debug::{to_repr}

///|
pub extend Join with Eq::{not_equal, equal}

///|
pub extend Cap with @debug.Debug::{to_repr}

///|
pub extend Cap with Eq::{not_equal, equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend Value with Eq::{not_equal, equal}

///|
pub extend CmpOp with @debug.Debug::{to_repr}

///|
pub extend CmpOp with Eq::{not_equal, equal}

///|
pub extend Interpolation with @debug.Debug::{to_repr}

///|
pub extend Interpolation with Eq::{not_equal, equal}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend Expr with Eq::{not_equal, equal}

///|
pub extend Expected with @debug.Debug::{to_repr}

///|
pub extend Expected with Eq::{not_equal, equal}

///|
pub extend NoFeature with FeatureContext::{geometry_type, property, state}

///|
pub extend SourceKind with @debug.Debug::{to_repr}

///|
pub extend SourceKind with Eq::{not_equal, equal}

///|
pub extend TextAnchor with @debug.Debug::{to_repr}

///|
pub extend TextAnchor with Eq::{not_equal, equal}

///|
pub extend DemEncoding with @debug.Debug::{to_repr}

///|
pub extend DemEncoding with Eq::{not_equal, equal}

///|
pub extend TextLayout with Eq::{not_equal, equal}

///|
pub extend ExtrusionPaint with Eq::{not_equal, equal}

///|
pub extend PromoteId with @debug.Debug::{to_repr}

///|
pub extend PromoteId with Eq::{not_equal, equal}

///|
pub extend RasterPaint with Eq::{not_equal, equal}
