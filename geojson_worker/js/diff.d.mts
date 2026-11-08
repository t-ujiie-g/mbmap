/** The `load` input: `promoteId` (a string, else none) and then the GeoJSON as UTF-8. */
export function loadInput(promoteId: unknown, data: Uint8Array): Uint8Array[];
/** MapLibre's GeoJSONSourceDiff as the `update` input (docs/FORMATS.md "GeoJSON diff"). */
export function encodeDiff(diff: object): Uint8Array;
