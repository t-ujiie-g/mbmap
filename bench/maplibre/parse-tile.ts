// MapLibre worker baseline: WorkerTile.parse on the bench fixtures and style, the way
// maplibre-gl-js test/bench/lib/parse_tile.ts does it. Bundled and run by parse-tile.mjs.
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {PbfReader} from 'pbf';
import {VectorTile} from '@mapbox/vector-tile';
import {createParser} from './parse-core.ts';

const root = process.argv[2];
const manifest = JSON.parse(readFileSync(`${root}/bench/fixtures/gsi-bvmap.manifest.json`, 'utf8'));
const style = JSON.parse(readFileSync(`${root}/bench/maplibre/style.json`, 'utf8'));
const parseTile = createParser(style);

const tiles = Object.keys(manifest.tiles).map((key) => ({key, buffer: readFileSync(`${root}/bench/fixtures/gsi-bvmap/${key}.pbf`)}));

function decodeOnly(tile: typeof tiles[number]) {
    // Full geometry decode of every feature, no styling or tessellation.
    const vt = new VectorTile(new PbfReader(tile.buffer));
    let n = 0;
    for (const name in vt.layers) {
        const layer = vt.layers[name];
        for (let i = 0; i < layer.length; i++) {
            const f = layer.feature(i);
            f.properties;
            for (const ring of f.loadGeometry()) n += ring.length;
        }
    }
    return n;
}

function median(xs: number[]) { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; }

const WARMUP = 5, ITER = 15;
const rows = [];
for (const tile of tiles) {
    for (let i = 0; i < WARMUP; i++) { await parseTile(tile.key, tile.buffer); decodeOnly(tile); }
    const parseMs = [], decodeMs = [];
    let vertices = 0, buckets = 0;
    for (let i = 0; i < ITER; i++) {
        let t0 = performance.now();
        buckets = await parseTile(tile.key, tile.buffer);
        parseMs.push(performance.now() - t0);
        t0 = performance.now();
        vertices = decodeOnly(tile);
        decodeMs.push(performance.now() - t0);
    }
    rows.push({tile: tile.key, bytes: tile.buffer.length, granularity: 'noSubdivision', geometryPoints: vertices, buckets, decodeMs: median(decodeMs), parseMs: median(parseMs)});
}
const sum = (k: string) => rows.reduce((a, r: any) => a + r[k], 0);
const center = rows.find(r => r.tile === '14/14552/6451');
const out = {
    env: {runtime: `node ${process.version}`, v8: process.versions.v8, maplibre: JSON.parse(readFileSync(`${root}/bench/node_modules/maplibre-gl/package.json`, 'utf8')).version},
    params: {warmup: WARMUP, iterations: ITER, tiles: rows.length, statistic: 'median per tile'},
    summary: {
        center,
        medianTileParseMs: median(rows.map(r => r.parseMs)),
        medianTileDecodeMs: median(rows.map(r => r.decodeMs)),
        totalParseMs: sum('parseMs'), totalDecodeMs: sum('decodeMs'), totalBytes: sum('bytes'),
    },
    rows,
};
mkdirSync(`${root}/bench/results`, {recursive: true});
writeFileSync(`${root}/bench/results/maplibre-parse-node.json`, JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(out.summary, null, 2));
