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
npm test                  # ベンチ用ツール（lib/）のテスト
npm run mvt:golden        # mvt を @mapbox/vector-tile と全 fixture で突き合わせる
npm run mvt:node          # mvt デコード速度（Node）
npm run mvt:browser       # 同（3 ブラウザの module Worker 内）
```

## backend/ — Wasm バックエンド比較（Phase 0）

`kernel/`（純 MoonBit）と `entry/`（`#export_name` で公開する export 面）を `wasm` / `wasm-gc` / `js` で
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

## mvt/ — MVT デコーダの黄金テストと速度

`entry/`（`#export_name` で公開）を js と wasm-gc でビルドして使う。

- `golden.mjs`：全 fixture を js ビルドの `tile_to_json` でデコードし、`@mapbox/vector-tile` の出力と
  レイヤー version / extent、全地物の id / type / properties / geometry まで完全比較。wasm-gc ビルドは
  点数・プロパティ数・座標総和を照合する。
- `node.mjs` / `browser.mjs`：各実装が「パース＋全地物のプロパティ＋全ジオメトリ」を行う時間を
  タイルごとに計測。wasm-gc は「JS → 線形メモリ → wasm 内で `Bytes` へコピー」まで含む。
  `parse only` / `+ properties` / `+ geometry` は wasm-gc の内訳（いずれもコピー込み）。
