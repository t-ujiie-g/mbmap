// Checks of `setFeatureState` and its kin, with MapLibre's messages. Import-free, so that
// `npm test` can load it.
import type { FeatureIdentifier } from "./types";

/** The feature's source layer as states are kept ("" outside vector sources), or why `feature` is refused: `source` is its source's spec. */
export function stateLayer(source: { type?: unknown } | undefined, feature: FeatureIdentifier): string | Error {
  if (!source) return new Error(`mbmap: the source '${feature.source}' does not exist in the map's style`);
  if (source.type !== "vector") return "";
  if (!feature.sourceLayer) return new Error("mbmap: the sourceLayer parameter must be provided for vector source types");
  return feature.sourceLayer;
}

/** Why a state cannot be set on `feature`: it has no id. */
export function stateIdError(feature: FeatureIdentifier): Error | null {
  return feature.id === undefined || feature.id === null || feature.id === ""
    ? new Error("mbmap: the feature id parameter must be provided and non-empty")
    : null;
}

/** Why `key` cannot be removed from `feature`'s state: only a whole state goes without an id. */
export function removeStateError(feature: FeatureIdentifier, key: string | undefined): Error | null {
  return feature.id === undefined && key !== undefined
    ? new Error("mbmap: a feature id is required to remove its specific state property")
    : null;
}
