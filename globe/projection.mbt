///|
/// The style's `projection` type: `Globe` is MapLibre's `"globe"`, vertical
/// perspective up to zoom 11 and mercator from 12 with a blend between.
#derive(Eq)
pub(all) enum Projection {
  Mercator
  Globe
  VerticalPerspective
}

///|
/// How far toward the globe the map is at `zoom`, from 0 (mercator) to 1
/// (MapLibre's `transitionState`).
pub fn Projection::transition(self : Projection, zoom : Double) -> Double {
  match self {
    Mercator => 0.0
    VerticalPerspective => 1.0
    Globe =>
      if zoom <= GLOBE_START {
        1.0
      } else if zoom >= GLOBE_END {
        0.0
      } else {
        1.0 - (zoom - GLOBE_START) / (GLOBE_END - GLOBE_START)
      }
  }
}

///|
/// The zooms between which `"globe"` turns from vertical perspective into
/// mercator (`projection_factory.ts`).
const GLOBE_START : Double = 11.0

///|
const GLOBE_END : Double = 12.0
