// The work of mbmap/3d's I3S layer, loaded with the first `i3sLayer`: the scene layer's nodes selected
// by I3S's level of detail on the 3D Tiles engine (3d-tiles.js), node contents from the 3D worker and
// features' attributes read on the main thread.
import type { TilesLayerOptions } from "./3d";
import type { GpuModel } from "./model/draw";
import type { Material, Primitive } from "./model/gltf";
import { TilesEngine, type GpuPart, type TileModel, type TileSource, type TilesParts } from "./3d-tiles.js";
import { nodeResources, readI3sAttribute, type I3sValues } from "./i3s/content";
import { lodStatus, nodeById, nodeTile, readLayer, resourceUrl, type I3sNode, type I3sScene } from "./i3s/scene";
import { Traversal, type Tile } from "./tiles/tileset";

/** A node's content as the 3D worker's `i3s` op gives it: meters east, north, up of `center`. */
export interface NodeContent {
  center: [number, number, number];
  primitives: Primitive[];
  materials: Material[];
  images: ImageBitmap[];
  featureIds: Float64Array | string[];
}

/** What the layer lends the engine for I3S: the tiles parts, and the 3D worker's `i3s` call. */
export interface I3sParts extends TilesParts {
  loadNode(args: { url: string; buffer: number; texture?: string; layer: object; node: I3sNode }): Promise<NodeContent>;
}

const IDENTITY = new Float64Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

async function fetchJson(url: string): Promise<any> {
  const res = await fetch(url, { credentials: "omit" });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

async function fetchBytes(url: string): Promise<Uint8Array> {
  const res = await fetch(url, { credentials: "omit" });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

/** A value of an attribute buffer as a property: bigints as numbers when exact, else as text. */
const valueOf = (v: unknown) => (typeof v === "bigint" ? (BigInt(Number(v)) === v ? Number(v) : String(v)) : v);

/** The properties of feature index `i` of a node: its row of each attribute buffer, found by OBJECTID as loaders.gl finds it. */
function nodeProperties(scene: I3sScene, node: I3sNode, featureIds: Float64Array | string[]): (i: number) => Promise<Record<string, unknown>> {
  let columns: Promise<[string, I3sValues][]> | null = null;
  return async (i) => {
    const out: Record<string, unknown> = Object.create(null);
    const paths = nodeResources(scene.json, node)?.attributes ?? [];
    const infos = scene.json.attributeStorageInfo ?? [];
    if (i < 0 || i >= featureIds.length || !paths.length) return out;
    columns ??= Promise.all(paths.map(async (p, k): Promise<[string, I3sValues]> => [infos[k].name, readI3sAttribute(await fetchBytes(resourceUrl(scene, p)), infos[k])]));
    const read = await columns.catch(() => [] as [string, I3sValues][]);
    const ids = read.find(([, v], k) => infos[k]?.attributeValues?.valueType?.startsWith("Oid"))?.[1];
    const id = featureIds[i];
    const row = ids ? Array.prototype.findIndex.call(ids, (v: unknown) => String(valueOf(v)) === String(id)) : i;
    if (row < 0) return out;
    for (const [name, values] of read) out[name] = valueOf(values[row]);
    return out;
  };
}

/** Reads the I3S layer at `url` (a SceneServer layer, or a layer document `….json` with its resources beside it) and returns its engine. */
export async function openI3s(url: string, options: TilesLayerOptions, parts: I3sParts): Promise<TilesEngine> {
  const docUrl = /\.json([?#]|$)/i.test(url) || /[?&]f=/.test(url) ? url : url + (url.includes("?") ? "&" : "?") + "f=json";
  const scene = readLayer(await fetchJson(docUrl), url);
  const pending = new Set<Tile>();
  const layer = { spatialReference: scene.json.spatialReference, store: scene.json.store, geometryDefinitions: scene.json.geometryDefinitions, materialDefinitions: scene.json.materialDefinitions, textureSetDefinitions: scene.json.textureSetDefinitions };
  const source: TileSource = {
    root: nodeTile(scene, await nodeById(scene, 0, fetchJson), null),
    traversal: new Traversal(8, (tile, frame) => lodStatus(tile, frame) === "DIG"),
    expand(tiles, repaint) {
      for (const tile of tiles.values()) {
        if (pending.has(tile)) continue;
        pending.add(tile);
        Promise.all((tile.header.children as number[]).map((id) => nodeById(scene, id, fetchJson)))
          .then((nodes) => {
            if (tile.children.length === 0) for (const node of nodes) nodeTile(scene, node, tile);
          })
          .catch(() => {})
          .finally(repaint);
      }
    },
    async load(tile, gl): Promise<TileModel> {
      const node: I3sNode = tile.header.node;
      const res = nodeResources(scene.json, node)!;
      const content = await parts.loadNode({ url: tile.contentUrl!, buffer: res.buffer!, texture: res.texture && resourceUrl(scene, res.texture), layer, node });
      const gpu: GpuModel = parts.upload(gl, content, IDENTITY);
      const part: GpuPart = { gpu, places: [IDENTITY], batchIds: null, properties: nodeProperties(scene, node, content.featureIds) };
      return { parts: [part], lng: content.center[0], lat: content.center[1], height: content.center[2] };
    },
  };
  return new TilesEngine(source, options, parts);
}

