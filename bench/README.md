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
npm run tess:golden       # 面の三角形分割を MapLibre（classifyRings + earcut）と全 fixture で突き合わせる
npm run tess:node         # デコード＋テッセレーション速度と MapLibre WorkerTile.parse（Node）
npm run tess:browser      # 同（3 ブラウザの module Worker 内）
npm run worker:browser    # Worker の process_tile（冷えた状態・温まった状態）を 3 ブラウザで
npm run render            # mbmap と MapLibre の初回描画・フレーム時間・バンドルサイズ（同じスタイル）
npm run example           # examples/ を http://127.0.0.1:8080/examples/basic/ で配信
```

## entry/ と lib/

- `entry/`：mvt / tess ベンチと黄金テストが呼ぶ MoonBit の公開面（`#export_name`）。js と wasm-gc でビルドし、
  `lib/entry.mjs` で読み込む。wasm-gc ではタイルを線形メモリに置き、wasm 内で `Bytes` へコピーしてから処理する。
- `lib/`：静的サーバー、fixture の読み込み（`fixtures.mjs`、Node 用は `node-io.mjs`）、行ごとの計測（`rows.mjs`）、
  Worker ベンチの実行（`worker-bench.mjs`）、esbuild 設定（`bundle.mjs`。`maplibre-src` で MapLibre の TS ソースを参照）。

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

- `golden.mjs`：全 fixture を js ビルドの `tile_to_json` でデコードし、`@mapbox/vector-tile` の出力と
  レイヤー version / extent、全地物の id / type / properties / geometry まで完全比較。wasm-gc ビルドは
  点数・プロパティ数・座標総和を照合する。
- `node.mjs` / `browser.mjs`：各実装が「パース＋全地物のプロパティ＋全ジオメトリ」を行う時間を
  タイルごとに計測。wasm-gc は「JS → 線形メモリ → wasm 内で `Bytes` へコピー」まで含む。
  `parse only` / `+ properties` / `+ geometry` は wasm-gc の内訳（いずれもコピー込み）。

## tess/ — テッセレーションの黄金テストと速度

- `golden.mjs`：全 fixture の全ポリゴン地物について、MapLibre の塗りの処理（`classifyRings(geometry, 500)` →
  ポリゴンごとに earcut 3.2.4）と、mbmap の `FillTessellator` の頂点・インデックスを地物ごとの FNV ハッシュで
  比較する（js ビルドは地物ごと、wasm-gc ビルドはタイル全体）。同じ三角形分割に対し earcut の `deviation`
  （面積の相対誤差）も報告する。
- `node.mjs` / `browser.mjs`：`maplibre/style.json` が描く内容（面レイヤーのポリゴン、線レイヤーの線をスタイルの
  filter / join / cap どおりに）を mbmap でデコード＋テッセレーションする時間と、同じスタイルでの MapLibre
  `WorkerTile.parse` を同じ Worker で計測する。MapLibre 側はスタイル式の評価・paint 属性・FeatureIndex・GPU 用
  バッファ詰めまで含むので、mbmap に有利な比較である。JS の `classifyRings + earcut` 行と `decode only` 行の差で
  earcut 単体を比べる。

## render/ — 描画（mbmap と MapLibre）

`examples/basic/style.json`（Phase 3 で読める範囲：定数の paint と geometry-type filter）と同じタイル・
同じカメラ操作で両エンジンを計測する（Chromium + Metal GPU、1280×800、DPR 2、5 回の中央値）。

- 初回描画：ナビゲーション開始から最初の `idle`（見えているタイルが揃って描かれた）まで。import 完了・
  地図生成の時刻も記録する。mbmap は `bundle/main` を esbuild で minify したもの（アプリが配信する形）を読む。
- フレーム：毎フレーム rAF でカメラを設定し（mbmap は `map_set_camera`、MapLibre は `jumpTo`）、
  パン・ズームの各 3 秒間の rAF 間隔と、フレームごとの rAF コールバック CPU 時間の合計を測る（両エンジンとも
  描画は rAF 内）。`--uncapped`（vsync なし）では rAF に GPU 同期待ちが入るので CPU 時間は比較に使わない。
- サイズ：mbmap は minify 後の main bundle と、Worker（グルー JS＋wasm-gc）の gzip -9。

## worker/ — Worker のタイル処理

`worker` パッケージの wasm-gc ビルドが `examples/basic/style.json` で全 fixture を処理する時間（デコード、
テッセレーション、GPU 用バッファへの書き込みまで）。`cold` は新しいインスタンスが各タイルを 1 回ずつ順に
処理したもの（ページの最初のタイルに相当）、行の値は温まった後のタイルごとの中央値。出力バイト数も記録する。
