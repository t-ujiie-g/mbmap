# bench/

すべての性能値はここのスクリプトで再現できること（docs/VISION.md §2）。結果は `results/*.json` に保存し、
PROGRESS.md の表はそこから転記する。

コマンドの一覧（黄金テスト、速度の計測、例の配信、パッケージの確認）は [AGENTS.md](../AGENTS.md) §1 にある。どれも `bench/` で
`npm run <名前>` として走らせる（`package.json` の `scripts`）。初回は次を行う。

```sh
cd bench
npm ci
npx playwright install chromium firefox webkit
npm run fixtures          # タイルなどを取得し、fixtures/*.manifest.json の sha256 と照合する
```

- fixture は `fixtures/`（コミットしない。マニフェストだけを置く）。中身と出典は [fixtures/README.md](fixtures/README.md)。上流が変わって
  照合に失敗したときは止まる。意図して更新するときは `node maplibre/fetch-tiles.mjs --update`。
- MoonBit をビルドするスクリプトは `npm run build:moon`（ベンチの入口、配布する wasm-gc、`bundle/main`）を先に走らせる。npm パッケージを
  使うもの（`*:golden` の多く）は `npm --prefix ../npm run build` を先に走らせる。
- TypeScript や MapLibre のソースを import する Node の入口は `node lib/run-bundled.mjs bench/<dir>/<entry>.mjs` で動かす（esbuild で
  `bench/dist/` にバンドルしてから実行する）。
- GPU を使う計測は、ヘッドレス Chromium に `--use-angle=metal --enable-gpu --ignore-gpu-blocklist` を付ける（既定は SwiftShader）。
  性能の計測は同時に走らせない。
- `bench/dist/` は生成物（バンドル、PMTiles、GeoJSON のデータなど）の置き場で、コミットしない。

## ベンチ専用の MoonBit パッケージ

| パッケージ | 役割 |
|---|---|
| `backend/kernel`, `backend/entry` | Wasm バックエンドの比較（下の backend/）。デコードの繰り返しは比較のためにわざと重複させている |
| `entry` | mvt / tess / GeoJSON / 座標系などのベンチと黄金テストが呼ぶ公開面（`#export_name`）。js と wasm-gc でビルドする |
| `expr` | `expression:golden` と `color:golden` が呼ぶ、式のコンパイルと評価（js） |
| `worker/compile_entry` | メインスレッドのスタイルのコンパイルを wasm-gc にしたもの（`worker:browser` が Worker に渡すコンパイル済みのスタイルを作る） |
| `split/*` | 2 つ目の wasm-gc モジュールのコスト（下の split/） |

## entry/ と lib/

- `entry/`：`lib/entry.mjs` で読み込む。wasm-gc ではタイルを線形メモリに置き、wasm 内で `Bytes` へコピーしてから処理する。
- `lib/`：コマンドライン引数（`args.mjs`）、静的サーバー（`serve.mjs`。127.0.0.1 だけで待ち、ポートを指定しなければ空いているものを選ぶ）、fixture の読み込み（`fixtures.mjs`、Node 用は
  `node-io.mjs`）、行ごとの計測（`rows.mjs`）、Worker ベンチの実行（`worker-bench.mjs`、`worker-page.*`）、esbuild 設定（`bundle.mjs`。
  `maplibre-src` で MapLibre の TS ソースを参照）と `run-bundled.mjs`、試験用の PNG（`png.mjs`）と PMTiles（`pmtiles-writer.mjs`）の
  読み書き、富士山の DEM を Terrarium にしたもの（`fuji-terrain.mjs`）、偽の Geolocation（`fake-geolocation.mjs`）、長いコメントの一覧
  （`long-comments.mjs`、AGENTS.md §7.7）。

## backend/ — Wasm バックエンド比較

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

- `style.json`：background / fill / line / circle のレイヤー。filter、`match`、`interpolate`、
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
`--labels`・`--line-labels` はラベルのレイヤー（等高線に沿ったラベル）を、`--terrain`・`--extrusion`・`--pitch=N` は地形・押し出し・傾きを足す
（結果のファイル名に付く）。

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
スタイルは `worker/compile_entry` でコンパイルして渡す（本番ではメインスレッドが行う）。

## npm/ — npm パッケージの確認

`pack-test.mjs` は `npm/` をビルドして `npm pack` し、できた tarball を examples と試験用のページ（`bench/npm/pages/`）の
`node_modules/mbmap` に展開する（アプリがインストールするのと同じ形。`npm/prepare.mjs`）。そのうえで Chromium で次を確かめる。

- `examples/{html,element,react}`（ショーケース。`?local=1` で fixture を読む）：3 つとも同じく、解析（5 km 以内の地点、平面直角座標系の
  座標）、3D の切り替え、地点への移動、コントロール（`checks/controls.mjs`）、クラスタ（`clusters.mjs`）、検索（`search.mjs`）、
  計測・作図・編集・分割（`geo-tools.mjs`）。
- `bench/pages/{basic,terrain}`（エンジンを直接呼ぶ開発用のページ）：地図ができて描画まで進むこと。
- `bench/npm/pages/npm`（ファサード）：イベント、出典の表示、エラーの経路と、`checks/` のカメラ（`camera.mjs`）、スタイルの変更
  （`style.mjs`）、画像（`images.mjs`）、地物の状態（`state.mjs`）、問い合わせとマウスのイベント（`query.mjs`）、ラスタ・TileJSON・
  PMTiles のソース（`tile-sources.mjs`）、追跡と画像の書き出し（`track-export.mjs`）。
- `bench/npm/pages/element`（素の HTML の `<mb-map>`）：属性で `mb-move` が1回だけ出ること、不正な属性が `mb-error` になり値が変わらない
  こと、移動では地図を保ち、外すと解放し、戻すと同じカメラで作り直すこと、帰属表示が右下の1行であること。
- `bench/npm/pages/{geojson,analysis}`：GeoJSON ソースと `mbmap/analysis` の遅延読み込み、結果、エラーの経路。
- `bench/npm/pages/media`（image・video・canvas のソース、`media.mjs`）、`bench/npm/pages/custom`（カスタムレイヤー、`custom.mjs`）。

fixture がなくてもタイルが 404 になるだけで地図は読み込まれるので、CI でも動く（`--screenshots=dir` で画面を保存する）。

## split/ — 2 つ目の wasm-gc モジュールのコスト

2つ目の wasm-gc モジュールで何が増えるかを測る（`npm run split`、`bench/results/split.json`）。入口を分ける粒度（入口ごとに 1 つの wasm を、
それぞれの Worker で遅延して読む。AGENTS.md §4）を決めたときの計測で、粒度を見直すときに走らせ直す。CI では走らせない。

- `split/analysis`：解析の代わりに置くパッケージ（列指向のポリゴンの球面面積、bbox、グリッド集計、面積順の上位）。本物の解析と同じく `Map`、ソート、`@math` を使う。
- `split/analysis_entry`：それを単独の wasm-gc モジュールにしたもの。`split/combined_entry`：表示用 Worker に同じコードを入れた一体型。`split/empty_entry`：空のモジュール（ランタイムの下限）。
- サイズ（gzip）に加えて、3ブラウザで、モジュール Worker の起動時間と、各モジュールの読み込み（fetch・コンパイル・インスタンス化）、解析の初回と温まった後の時間を測る。1万ポリゴン、15回の中央値。ローカルの配信なので、ネットワークの時間は含まない（サイズから見積もる）。

## analysis/ — 解析（`mbmap/analysis`）

配布する解析の wasm（`analysis_worker`）を、Worker のグルーを通さずに直接呼ぶ（`load.mjs`）。比べる相手は Turf.js 7.4.0 と flatbush 4.6.2
（`reference.mjs`）。データは geojson/ の fixture。

- `golden.mjs`：buildings・mixed・world・roads・points の全地物の面積・長さ・重心・bbox、各 200 個の矩形検索、各 400 個の近傍検索（k=10 と 1）、
  点の内外判定・集計・グリッド集計を比べる。値はビット単位で一致しなければならない。
- `node.mjs` / `browser.mjs`：同じ処理の速度。JS は `JSON.parse` 済みの GeoJSON に対して、mbmap は読み込んだデータセットに対して測る
  （Worker とのメッセージは含まない）。5回の中央値。

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
- 読み込み方の比較：A は MoonBit で GeoJSON のテキストを読む（本番の方式）。B は JS の `JSON.parse` と JS のループで `geom` の表のバイト列
  （`columnarize.mjs`）を作り、wasm で表と索引を作る。B の結果が A と同じタイルになることは、ハッシュで確かめた。

## そのほかの黄金テストと計測

ほかのディレクトリは、それぞれ AGENTS.md §1 の `npm run` の名前に対応する（比べる相手と合格の条件もそこにある）：
`raster/`、`pmtiles/`、`query/`、`track/`、`export/`、`ui/`、`labels/`、`style/`（`style:golden`・`style:public`・`style:compat`・
`expression:golden`・`color:golden`。場面は `style/scenes.mjs`、公開のスタイルは `style/public-styles.mjs`）、`camera/`、`terrain/`、
`proj/`、`clipper/`（`clipper:golden`・`buffer:check`・`geometry:node`）、`geodesic/`、`draw/`（`draw:golden`・`draw:many`・
`draw:setdata`）、`data/`（`data:golden`、`fgb:golden`、`xml:golden`、`write:golden`、`geotiff:golden`：`mbmap/data` の読み書きを
papaparse、betterknown、wkx、shpjs、topojson-client、flatgeobuf、togeojson、tokml、geotiff と比べる。すべて 0 differ のまま。共通の部品は `data/common.mjs`）、
`geotiff/`（`geotiff:tiles`：`geotiff` ソースのタイルを元の画素と比べる。すべて ok のまま）。開発用のページは `pages/`（basic、terrain）にあり、`npm run example` で配信する。
