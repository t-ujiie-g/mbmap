// GeoTIFF sources (`{ type: "geotiff", url, ... }`): their bounds and zooms read from the file, and their
// tiles, and those of `reprojected` sources, drawn by mbmap/data's worker. Loaded by the map with the first one.
import { rasterInfo, rasterTile, type RasterInfo, reprojectTile } from "./data";
import type { ReprojectedSource } from "./services/common";
import type { TransformedRequest } from "./urls";

type Transform = (url: string) => TransformedRequest | undefined;

/** The keys a GeoTIFF source's document gives the engine's style (the source's own win), and what its tiles need. */
export async function geotiffDocument(url: string, transformRequest?: Transform): Promise<RasterInfo & { minzoom: number }> {
  return { ...(await rasterInfo(url, { transformRequest })), minzoom: 0 };
}

/** Tile `z`/`x`/`y` of GeoTIFF source `spec` (its `range` by default band 0's, from `info`). */
export function geotiffTile(url: string, spec: Record<string, unknown>, info: RasterInfo, z: number, x: number, y: number, transformRequest?: Transform): Promise<ArrayBuffer | null> {
  const { tileSize, bands, range, colors, dem, resampling } = spec as Parameters<typeof rasterTile>[4] & Record<string, never>;
  return rasterTile(url, z, x, y, { tileSize, bands, range: range ?? info.range ?? undefined, colors, dem, resampling, transformRequest });
}

/** Tile `z`/`x`/`y` of `reprojected` source `spec`. */
export function reprojectedTile(spec: Record<string, unknown>, z: number, x: number, y: number, transformRequest?: Transform): Promise<ArrayBuffer | null> {
  const size = spec.tileSize === 512 ? 512 : 256;
  return reprojectTile(spec as unknown as ReprojectedSource, z, x, y, { tileSize: size, transformRequest });
}
