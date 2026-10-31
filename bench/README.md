# bench/

すべての性能値はここのスクリプトで再現できること（docs/VISION.md §2）。結果は `results/*.json` に保存し、
PROGRESS.md の表はそこから転記する。

```sh
cd bench
npm ci
npx playwright install chromium firefox webkit
npm run fixtures          # 国土地理院タイルを取得し sha256 を照合
npm run backend:node      # Wasm バックエンド比較（Node）
npm run backend:browser   # 同（Chromium / Firefox / WebKit の module Worker 内）
npm run maplibre:parse    # MapLibre WorkerTile.parse の基準値（Node）
npm run maplibre          # MapLibre の初回描画・フレーム時間・バンドルサイズ（Chromium + Metal GPU）
```

## backend/ — Wasm バックエンド比較（Phase 0）

`kernel/`（純 MoonBit）と `entry/`（バックエンドごとの export 面）を `wasm` / `wasm-gc` / `js` で
`--release` ビルドし、さらに `wasm-opt -O3` 版を作って比較する。

- **decode**：zigzag varint 対（MVT ジオメトリのデルタ相当）100 万値・約 1.35MB をデコードし、
  累積座標を Float で書き出す。各反復を `in`（タイルバイト列を読める場所へ）/ `decode` / `out`
  （**transfer 可能な** `Float32Array` を得るまで）に分けて計測。全バリアントの出力は JS 参照実装と
  チェックサム照合する。
- **alloc**：特徴量ごとに boxed な点の `Array` を作る（10 万 × 32 点）。アロケータ／GC のスループット。

| バリアント | 中身 |
|---|---|
| `js-baseline` | 手書き JS（pbf 風）。参照実装 |
| `mbt-js` | js バックエンド。`FixedArray[Byte]` = `Uint8Array`、`FixedArray[Float]` = JS `Array` → `new Float32Array(arr)` |
| `mbt-js-ffi` | js バックエンド。`extern "js"` で `Float32Array` に直接書く |
| `mbt-wasm` | wasm（線形メモリ）。MoonBit の `FixedArray` のポインタ = データ先頭なので JS から view で読み書き |
| `mbt-wasm-raw` | wasm。インライン wasm の `i32.load8_u` / `f32.store` で生アドレスを読む |
| `mbt-wasm-gc` | wasm-gc。GC 配列を要素ごとの export 関数で読み書き（素朴な方法） |
| `mbt-wasm-gc-mem` | wasm-gc のコードから、インライン wasm で線形メモリを直接読み書き |
| `mbt-wasm-gc-copy` | wasm-gc。線形メモリ⇔GC 配列のコピーを wasm 内で行い、デコードは安全な純 MoonBit |
| `+opt` | 上記を `wasm-opt -O3` で後処理 |

## maplibre/ — MapLibre 基準値

- `style.json`：background / fill / line のみ（MVP と同じ範囲の Style Spec）。両エンジンで共通に使う。
- `parse-tile.ts`：MapLibre の `src/` を esbuild でバンドルし `WorkerTile.parse` を直接呼ぶ
  （maplibre-gl-js の `test/bench/lib/parse_tile.ts` と同じ方法）。
- `index.html` + `page.mjs` + `run.mjs`：1280×800、DPR 2、ローカル配信のタイルで
  `load` / 初回 `idle` までの時間、パン・ズーム中の rAF 間隔と `Map#_render` の CPU 時間を計測。
  ヘッドレス Chromium は既定で SwiftShader になるため `--use-angle=metal --enable-gpu` を付ける。
