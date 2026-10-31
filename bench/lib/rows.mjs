// Per-tile timing of bench rows. A row is { name, run(tile), expect?(tile) }:
// `run` does the work and returns a value (or a promise of one, which is
// awaited inside the timing) that must equal `expect(tile)` when the row has
// one; a negative value always counts as a failure.
import { CENTER_TILE } from "./fixtures.mjs";

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };

export async function runRows(tiles, rows, { warmup = 5, iterations = 15 } = {}) {
  const out = [];
  for (const row of rows) {
    const perTile = [];
    let correct = true;
    for (const tile of tiles) {
      const expected = row.expect?.(tile);
      for (let i = 0; i < warmup; i++) {
        const r = row.run(tile);
        if (r instanceof Promise) await r;
      }
      const xs = [];
      for (let i = 0; i < iterations; i++) {
        const t0 = performance.now();
        let got = row.run(tile);
        if (got instanceof Promise) got = await got;
        xs.push(performance.now() - t0);
        if (got < 0 || (expected !== undefined && got !== expected)) correct = false;
      }
      perTile.push({ key: tile.key, ms: median(xs) });
    }
    out.push({
      name: row.name, correct,
      centerMs: perTile.find((t) => t.key === CENTER_TILE)?.ms,
      medianTileMs: median(perTile.map((t) => t.ms)),
      totalMs: perTile.reduce((a, t) => a + t.ms, 0),
      perTile,
    });
  }
  return { params: { tiles: tiles.length, warmup, iterations, statistic: "median per tile" }, rows: out };
}

export function printRows(result) {
  console.table(result.rows.map((r) => ({ name: r.name, ok: r.correct, center: r.centerMs.toFixed(2), medianTile: r.medianTileMs.toFixed(2), total: r.totalMs.toFixed(1) })));
}
