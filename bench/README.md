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
npm run examples          # npm パッケージを pack して examples/{npm,element,react} に入れてから配信（一覧は /examples/）
npm run split             # 2つ目の wasm-gc モジュールのサイズと読み込み時間（入口の分割の判断用）
npm run geojson:golden    # tiler と @maplibre/geojson-vt の黄金テスト（範囲内の全タイル）
npm run geojson:node      # GeoJSON の読み込み・索引・タイル切り出しを geojson-vt と比べる（geojson:browser は3ブラウザ）
npm run npm:pack          # npm/ をビルドして npm pack し、examples/{npm,element,react} に入れて Chromium で確かめる
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

- `style.json`：background / fill / line のみ（MVP と同じ範囲の Style Spec）。filter、`match`、`interpolate`、
  `step` を含む。`render/` と `worker/` も、このファイルをそのまま使う。
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

`maplibre/style.json` をそのまま両エンジンに渡し、同じタイル・同じカメラ操作で計測する（Chromium + Metal GPU、
1280×800、DPR 2、11 回の中央値。最初の数回はブラウザが温まっておらず遅いため、5 回では中央値がぶれた）。

- 初回描画：ナビゲーション開始から最初の `idle`（見えているタイルが揃って描かれた）まで。import 完了・
  地図生成の時刻も記録する。mbmap は `bundle/main` を esbuild で minify したもの（アプリが配信する形）を読む。
- フレーム：毎フレーム rAF でカメラを設定し（mbmap は `map_set_camera`、MapLibre は `jumpTo`）、
  パン・ズームの各 3 秒間の rAF 間隔と、フレームごとの rAF コールバック CPU 時間の合計を測る（両エンジンとも
  描画は rAF 内）。`--uncapped`（vsync なし）では rAF に GPU 同期待ちが入るので CPU 時間は比較に使わない。
- サイズ：mbmap は minify 後の main bundle と、Worker（グルー JS＋wasm-gc）の gzip -9。

## worker/ — Worker のタイル処理

`worker` パッケージの wasm-gc ビルドが `maplibre/style.json` で全 fixture を処理する時間（デコード、
テッセレーション、GPU 用バッファへの書き込みまで）。`cold` は新しいインスタンスが各タイルを 1 回ずつ順に
処理したもの（ページの最初のタイルに相当）、行の値は温まった後のタイルごとの中央値。出力バイト数も記録する。

## npm/ — npm パッケージの確認

`pack-test.mjs` は `npm/` をビルドして `npm pack` し、できた tarball を各 example の `node_modules/mbmap` に展開する（アプリが
インストールするのと同じ形）。そのうえで Chromium で次を確かめる。

- `examples/npm`（ファサード）：`load`、`jumpTo` で `move` が1回だけ出ること、帰属表示、スタイル URL の取得失敗が `error`
  イベントになること、描けないスタイルが例外になること。
- `examples/element`（素の HTML の `<mb-map>`）：属性で `mb-move` が1回だけ出ること、不正な属性が `mb-error` になり値が変わらない
  こと、移動では地図を保ち、外すと解放し、戻すと同じカメラで作り直すこと、帰属表示が右下の1行であること。
- `examples/react`（React 19 から `<mb-map>`）：ボタンで props を変えると地図が動くこと、ホイールでのズームが `onmb-move`
  経由で React の表示に反映されること。esbuild でバンドルし、`worker.js` と `mbmap.wasm` をバンドルの隣にコピーする。
fixture がなくてもタイルが 404 になるだけで地図は読み込まれるので、CI でも動く。

## split/ — 入口の分割のコスト（Phase 6.5）

2つ目の wasm-gc モジュールで何が増えるかを測る（`npm run split`、`bench/results/split.json`）。

- `split/analysis`：解析の代わりに置くパッケージ（列指向のポリゴンの球面面積、bbox、グリッド集計、面積順の上位）。本物の解析と同じく `Map`、ソート、`@math` を使う。
- `split/analysis_entry`：それを単独の wasm-gc モジュールにしたもの。`split/combined_entry`：表示用 Worker に同じコードを入れた一体型。`split/empty_entry`：空のモジュール（ランタイムの下限）。
- サイズ（gzip）に加えて、3ブラウザで、モジュール Worker の起動時間と、各モジュールの読み込み（fetch・コンパイル・インスタンス化）、解析の初回と温まった後の時間を測る。1万ポリゴン、15回の中央値。ローカルの配信なので、ネットワークの時間は含まない（サイズから見積もる）。

## geojson/ — GeoJSON の読み込みとタイル分割

`fixtures.mjs` が `bench/dist/geojson/` にデータを作る（毎回同じ内容）。国土地理院の bench タイルの各レイヤーを経緯度の GeoJSON に
したもの（points・roads と、密な buildings・mixed は東京駅周辺の 3×3 タイル）、roads を小数 6 桁に丸めた roads6、乱数で作った
世界中のデータ（日付変更線をまたぐもの、高緯度のもの）。

- `golden.mjs`：geojson-vt の既定値、MapLibre の GeoJSON ソースの設定（4096 単位に換算）、ラップなしの3つで、データの範囲の全タイルを
  geojson-vt と比べる（地物の順・型・行・整数座標）。js ビルドは中身をそのまま、wasm-gc ビルドはタイルごとのハッシュで比べる。メモリを
  多く使うので `--max-old-space-size=8192` で動かす。
- `node.mjs` / `browser.mjs`：geojson-vt（デコード＋`JSON.parse`、索引、タイル切り出し）と mbmap の wasm-gc ビルド（線形メモリへの
  コピー＋読み込み、索引、タイル切り出し）を比べる。MapLibre の GeoJSON ソースの設定で、z6〜16 のデータ上の全タイルを、毎回新しい
  索引から切り出す（キャッシュではなく実際に切る）。5回の中央値。
