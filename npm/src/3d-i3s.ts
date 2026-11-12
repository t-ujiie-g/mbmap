// The work of mbmap/3d's I3S layer, loaded with the first `i3sLayer`: the scene layer's nodes selected
// by I3S's level of detail on the 3D Tiles engine (3d-tiles.js), node contents from the 3D worker and
// features' attributes read on the main thread.
import type { TilesLayerOptions } from "./3d";
import type { GpuModel } from "./model/draw";
import type { Material, Primitive } from "./model/gltf";
import { TilesEngine, type GpuPart, type TileModel, type TileSource, type TilesParts } from "./3d-tiles.js";
import { nodeResources, readI3sAttribute, type I3sValues } from "./i3s/content";
import { lodStatus, nodeById, nodeTile, readLayer, resourceUrl, type I3sNode, type I3sScene } from "./i3s/scene";
import { lineageHas, Traversal, type Tile } from "./tiles/tileset";
import { IDENTITY } from "./tiles/geo";
import { cloudColors, type CloudColor, type CloudPoints } from "./model/cloud";
import { fetchCapped, fetchJsonCapped } from "./model/fetch";

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
  loadNode(args: { url?: string; geometry?: Uint8Array; buffer: number; texture?: string; textureBytes?: Uint8Array; layer: object; node: I3sNode }): Promise<NodeContent>;
  loadPoints(args: { url: string | Uint8Array; center: number[]; rgb?: string | Uint8Array; intensity?: string | Uint8Array; classification?: string | Uint8Array; classType?: string }): Promise<CloudPoints & { center: [number, number, number] }>;
}

/** A point cloud layer's attribute resources by what they hold (`attributeStorageInfo`, PCSL). */
function pointAttributes(scene: I3sScene, resource: number, mode: CloudColor | undefined) {
  const infos: any[] = (scene.json.attributeStorageInfo as any[]) ?? [];
  const path = (info: any) => info && resourceUrl(scene, `nodes/${resource}/attributes/${info.key}/0`);
  const rgb = infos.find((i) => i.encoding === "lepcc-rgb");
  const intensity = infos.find((i) => i.encoding === "lepcc-intensity");
  const classes = infos.find((i) => /^class(_?code)?$/i.test(i.name ?? "") && !i.encoding);
  return {
    rgb: (mode ?? "rgb") === "rgb" ? path(rgb) : undefined,
    intensity: mode === "intensity" ? path(intensity) : undefined,
    classification: mode === "classification" ? path(classes) : undefined,
    classType: classes?.attributeValues?.valueType,
  };
}


/** Where a layer's resources come from: over HTTP, or out of an SLPK (`json` and `bytes` take the URLs `resourceUrl` makes). */
interface Resources {
  json(url: string): Promise<any>;
  bytes(url: string): Promise<Uint8Array>;
  /** Whether the 3D worker must be given node resources as bytes (it cannot reach into an SLPK). */
  packed: boolean;
}

const HTTP: Resources = { json: fetchJsonCapped, bytes: (url) => fetchCapped(url), packed: false };

/** A value of an attribute buffer as a property: bigints as numbers when exact, else as text. */
const valueOf = (v: unknown) => (typeof v === "bigint" ? (BigInt(Number(v)) === v ? Number(v) : String(v)) : v);

/** The properties of feature index `i` of a node: its row of each attribute buffer, found by OBJECTID as loaders.gl finds it. */
function nodeProperties(scene: I3sScene, node: I3sNode, featureIds: Float64Array | string[], res: Resources): (i: number) => Promise<Record<string, unknown>> {
  let columns: Promise<[string, I3sValues][]> | null = null;
  return async (i) => {
    const out: Record<string, unknown> = Object.create(null);
    const paths = nodeResources(scene.json, node)?.attributes ?? [];
    const infos = scene.json.attributeStorageInfo ?? [];
    if (i < 0 || i >= featureIds.length || !paths.length) return out;
    columns ??= Promise.all(paths.map(async (p, k): Promise<[string, I3sValues]> => [infos[k].name, readI3sAttribute(await res.bytes(resourceUrl(scene, p)), infos[k])]));
    const read = await columns.catch(() => [] as [string, I3sValues][]);
    const ids = read.find((_, k) => infos[k]?.attributeValues?.valueType?.startsWith("Oid"))?.[1];
    const id = featureIds[i];
    const row = ids ? Array.prototype.findIndex.call(ids, (v: unknown) => String(valueOf(v)) === String(id)) : i;
    if (row < 0) return out;
    for (const [name, values] of read) out[name] = valueOf(values[row]);
    return out;
  };
}

/**
 * Reads the I3S layer at `url` (a SceneServer layer, a layer document `….json` with its resources beside
 * it, or an `.slpk` read by range requests) and returns its engine.
 */
export async function openI3s(url: string, options: TilesLayerOptions, parts: I3sParts): Promise<TilesEngine> {
  let res = HTTP;
  let scene: I3sScene;
  if (/\.slpk([?#]|$)/i.test(url)) {
    const { openSlpk, slpkResources } = await import("./i3s/slpk.js");
    const r = slpkResources(await openSlpk(url));
    res = { json: r.json, bytes: r.bytes, packed: true };
    scene = readLayer(await r.json("layer"), r.url);
  } else {
    const docUrl = /\.json([?#]|$)/i.test(url) || /[?&]f=/.test(url) ? url : url + (url.includes("?") ? "&" : "?") + "f=json";
    scene = readLayer(await fetchJsonCapped(docUrl), url);
  }
  const pending = new Set<Tile>();
  const failures = new Map<Tile, number>();
  const layer = { spatialReference: scene.json.spatialReference, store: scene.json.store, geometryDefinitions: scene.json.geometryDefinitions, materialDefinitions: scene.json.materialDefinitions, textureSetDefinitions: scene.json.textureSetDefinitions };
  const source: TileSource = {
    root: nodeTile(scene, await nodeById(scene, 0, res.json), null, 0),
    traversal: new Traversal(8, (tile, frame) => lodStatus(tile, frame) === "DIG"),
    expand(tiles, repaint) {
      for (const tile of tiles.values()) {
        if (pending.has(tile)) continue;
        pending.add(tile);
        Promise.all((tile.header.children as number[]).map((id) => nodeById(scene, id, res.json)))
          .then((nodes) => {
            const ids: number[] = tile.header.children;
            // A node listing one of its ancestors as a child would nest forever.
            if (tile.children.length === 0) nodes.forEach((node, i) => lineageHas(tile, (t) => t.path === String(ids[i])) || nodeTile(scene, node, tile, ids[i]));
          })
          .then(repaint, () => {
            // Children whose pages failed are asked for again a second later, three times at most.
            const n = (failures.get(tile) ?? 0) + 1;
            failures.set(tile, n);
            if (n < 3) setTimeout(() => (pending.delete(tile), repaint()), 1000);
          });
      }
    },
    async load(tile, gl): Promise<TileModel> {
      const node: I3sNode = tile.header.node;
      if (scene.points) {
        const center = node.obb.center;
        const mode = (options as { color?: CloudColor }).color;
        const attrs = pointAttributes(scene, node.resourceId!, mode);
        const read = async (u: string | undefined) => (u && res.packed ? res.bytes(u) : u);
        const [url, rgb, intensity, classification] = await Promise.all([read(tile.contentUrl!), read(attrs.rgb), read(attrs.intensity), read(attrs.classification)]);
        const points = await parts.loadPoints({ url: url!, center, rgb, intensity, classification, classType: attrs.classType });
        const root = this.root.header.node.obb;
        const range: [number, number] = [root.center[2] - root.halfSize[2] - center[2], root.center[2] + root.halfSize[2] - center[2]];
        const color = { data: cloudColors(points, mode, mode === "height" ? range : undefined), size: 3, type: gl.UNSIGNED_BYTE, normalized: true };
        const position = { data: points.positions, size: 3, type: gl.FLOAT, normalized: false };
        const material: Material = { color: [1, 1, 1, 1], alphaMode: "OPAQUE", alphaCutoff: 0.5, doubleSided: true, unlit: true };
        const primitive: Primitive = { attributes: { POSITION: position, COLOR_0: color }, mode: gl.POINTS, material: 0, matrix: IDENTITY };
        const gpu = parts.upload(gl, { primitives: [primitive], materials: [material], images: [] }, IDENTITY);
        return { parts: [{ gpu, places: [IDENTITY], batchIds: null, properties: async () => Object.create(null) }], lng: center[0], lat: center[1], height: center[2] };
      }
      const paths = nodeResources(scene.json, node)!;
      const texture = paths.texture && resourceUrl(scene, paths.texture);
      const where = res.packed
        ? { geometry: await res.bytes(tile.contentUrl!), textureBytes: texture ? await res.bytes(texture).catch(() => undefined) : undefined }
        : { url: tile.contentUrl!, texture };
      const content = await parts.loadNode({ ...where, buffer: paths.buffer!, layer, node });
      const gpu: GpuModel = parts.upload(gl, content, IDENTITY);
      const part: GpuPart = { gpu, places: [IDENTITY], batchIds: null, properties: nodeProperties(scene, node, content.featureIds, res) };
      return { parts: [part], lng: content.center[0], lat: content.center[1], height: content.center[2] };
    },
  };
  return new TilesEngine(source, options, parts);
}

