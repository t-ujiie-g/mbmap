// MapLibre's worker-side tile processing, WorkerTile.parse (MVT decode, style
// evaluation, bucket building, tessellation), set up the way maplibre-gl-js
// test/bench/lib/parse_tile.ts does it. Shared by the Node and Worker benches.
import {PbfReader} from 'pbf';
import {VectorTile} from '@mapbox/vector-tile';
import {derefLayers} from '@maplibre/maplibre-gl-style-spec';
import {WorkerTile} from 'maplibre-src/source/worker_tile.ts';
import {StyleLayerIndex} from 'maplibre-src/style/style_layer_index.ts';
import {OverscaledTileID} from 'maplibre-src/tile/tile_id.ts';
import {SubdivisionGranularitySetting} from 'maplibre-src/render/subdivision_granularity_settings.ts';
import type {IActor} from 'maplibre-src/util/actor.ts';

const actor = {sendAsync: () => Promise.resolve({})} as unknown as IActor;

/** Returns parse(key, bytes) resolving to the number of buckets built. */
export function createParser(style: {layers: unknown[]}) {
    const layerIndex = new StyleLayerIndex(derefLayers(style.layers as any));
    const granularity = SubdivisionGranularitySetting.noSubdivision;
    return async (key: string, buffer: Uint8Array): Promise<number> => {
        const [z, x, y] = key.split('/').map(Number);
        const tileID = new OverscaledTileID(z, 0, z, x, y);
        const workerTile = new WorkerTile({
            type: 'benchmark', tileID, zoom: tileID.overscaledZ, tileSize: 512,
            showCollisionBoxes: false, source: 'gsi', uid: '0', maxZoom: 22, pixelRatio: 1,
            request: {url: ''}, returnDependencies: false, promoteId: undefined,
            subdivisionGranularity: granularity,
        } as any);
        const result = await workerTile.parse(new VectorTile(new PbfReader(buffer)), layerIndex, [], actor, granularity);
        return result.buckets.length;
    };
}
