export interface TableFeatureCollection {
  type: "FeatureCollection";
  features: { type: "Feature"; geometry: { type: string; coordinates: unknown } | null; properties: Record<string, unknown> }[];
}
export function tableToGeoJSON(buffer: ArrayBuffer | ArrayBufferView): TableFeatureCollection;
export function tableInfo(buffer: ArrayBuffer | ArrayBufferView): { length: number; columns: string[] };
