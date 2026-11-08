// A 3D tile's content for mbmap/3d: Batched 3D Model (b3dm: feature table with BATCH_LENGTH and
// RTC_CENTER, batch table JSON, then a glb) or a glTF itself (3D Tiles 1.1). Import-free.
import { readGltf, type MeshoptDecode, type Model } from "../model/gltf.ts";

const B3DM = 0x6d643362;
const HEADER_BYTES = 28;

/** A tile's model with what 3D Tiles adds: `rtc` (RTC_CENTER or CESIUM_RTC), the features in its batch and their properties. */
export interface TileContent {
  model: Model;
  rtc: [number, number, number] | null;
  batchLength: number;
  batchTable: Record<string, unknown> | null;
}

const json = (bytes: Uint8Array): Record<string, any> => (bytes.length ? JSON.parse(new TextDecoder().decode(bytes)) : {});

/** A b3dm's tables and its glb, or null when `bytes` is not a b3dm. */
export function splitB3dm(bytes: Uint8Array): { rtc: TileContent["rtc"]; batchLength: number; batchTable: Record<string, unknown> | null; glb: Uint8Array } | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 4 || view.getUint32(0, true) !== B3DM) return null;
  if (bytes.length < HEADER_BYTES) throw new Error("the b3dm header is cut short");
  if (view.getUint32(4, true) !== 1) throw new Error("only b3dm version 1 is read");
  const length = Math.min(view.getUint32(8, true), bytes.length);
  const [ftJson, ftBin, btJson, btBin] = [12, 16, 20, 24].map((at) => view.getUint32(at, true));
  // Older b3dm (a batch length where the feature table length is now) would read as huge lengths.
  const glbAt = HEADER_BYTES + ftJson + ftBin + btJson + btBin;
  if (glbAt > length) throw new Error("the b3dm's tables run past the file");
  const featureTable = json(bytes.subarray(HEADER_BYTES, HEADER_BYTES + ftJson));
  const featureBinary = bytes.subarray(HEADER_BYTES + ftJson, HEADER_BYTES + ftJson + ftBin);
  const batchTable = btJson ? json(bytes.subarray(HEADER_BYTES + ftJson + ftBin, HEADER_BYTES + ftJson + ftBin + btJson)) : null;
  let rtc: TileContent["rtc"] = null;
  const center = featureTable.RTC_CENTER;
  if (Array.isArray(center) && center.length === 3 && center.every(Number.isFinite)) rtc = [center[0], center[1], center[2]];
  else if (center && Number.isInteger(center.byteOffset) && center.byteOffset + 12 <= featureBinary.length) {
    const v = new DataView(featureBinary.buffer, featureBinary.byteOffset + center.byteOffset, 12);
    rtc = [v.getFloat32(0, true), v.getFloat32(4, true), v.getFloat32(8, true)];
  }
  const batchLength = Number.isInteger(featureTable.BATCH_LENGTH) ? featureTable.BATCH_LENGTH : 0;
  return { rtc, batchLength, batchTable, glb: bytes.subarray(glbAt, length) };
}

/** Reads the b3dm, glb or glTF in `bytes`. */
export async function readTileContent(bytes: Uint8Array, load: (uri: string) => Promise<Uint8Array>, meshopt?: MeshoptDecode): Promise<TileContent> {
  const b3dm = splitB3dm(bytes);
  const model = await readGltf(b3dm ? b3dm.glb : bytes, load, meshopt);
  return { model, rtc: b3dm?.rtc ?? model.rtc ?? null, batchLength: b3dm?.batchLength ?? 0, batchTable: b3dm?.batchTable ?? null };
}
