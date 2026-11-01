# MoonBit製 地図描画エンジン Vision
## 1. ゴール

MoonBit で、**軽量かつ既存ライブラリを上回る性能**の Web 向けベクトルタイル地図描画エンジンを作る。そのうえで、**サーバーに頼らない WebGIS の実行基盤**（フロントエンドで完結する GIS ライブラリ）に育てる。表示・データ加工・解析・3D がブラウザ内で完結し、しかも**使う分しか読み込まない**ことを目指す。

| 柱 | 中身 | 位置づけ |
|---|---|---|
| 表示 | 2D ベクトルタイル、ラベル、GeoJSON、3D（地形、建物の押し出し、3D Tiles） | 入口。軽さと速さで選ばれる部分。3D は表示モードの1つとして扱う |
| データ | 読み込みと変換（GeoJSON、FlatGeobuf、PMTiles、CSV、GeoParquet）、座標系変換（平面直角座標系など） | 解析と表示をつなぐ土台 |
| 解析 | 空間インデックス、計測、空間クエリ、集計、ジオメトリ演算（buffer、交差、結合）、ラスタ解析（傾斜、陰影、可視域） | 差別化。Worker 上の Wasm で動かし、メインスレッドを塞がない |
| コンポーネント | Web Components 製の計測、凡例、レイヤー一覧、属性テーブル、作図・編集 | 組み立て済みの UI。`<mb-map>` が土台 |

ArcGIS Maps SDK for JavaScript のような機能群を視野に入れるが、網羅は目指さない。各柱で、ブラウザ内で完結させる価値が大きいものから順に作る。

- 比較対象：MapLibre GL JS、MachGL（Geolonia、gzip 約98KB・WebGL2・Web Worker 構成）
- **特定の UI フレームワークに依存しない**。地図は「canvas を受け取って描く命令的なエンジン」とし、UI フレームワークとの統合は外側の薄い層で行う
- 利用形態の優先順位：
  1. **TS/JS から**（最優先）：npm パッケージ、型定義（`.d.ts`）付き、ESM
  2. **MoonBit から**：mooncakes パッケージとして import できる素の API（FFI を経由せず直接呼べる）
  3. **Web Component**（`<mb-map>`）：React / Vue / Svelte / Luna / rabbita など、どのフレームワークからも使える共通の受け口
  4. 各 UI ライブラリ向けアダプタ（rabbita、Luna など）：需要が見えてから。コアの設計をこれらに合わせて曲げない
- 計算コアは純 MoonBit で書き、どのバックエンド（wasm / wasm-gc / js / native）でもテストが通ること

## 2. 性能目標（ベンチマークで常に計測する）

| 指標 | 目標（Phase 0 の MapLibre 6.16.0 実測値で更新。測定条件は PROGRESS.md） |
|---|---|
| メインスレッド側バンドル | gzip 50KB 以下 |
| Worker（Wasm 含む） | gzip 100KB 以下（ラベルを入れた Phase 9.1 で 80KB から引き上げ） |
| 1タイルのデコード＋テッセレーション（z14 都市部） | MapLibre の 1/2 以下の時間：bench fixtures の中央タイル 4.6ms 以下、35 タイル中央値 11.7ms 以下（同ハーネス・同スタイル） |
| フレーム時間 | 中級 Android 端末で 60fps、パン・ズーム中の GC 停止なし（実機計測は当面行わない）。代理指標：1 フレームの描画 CPU 時間 p95 が 1.44ms 以下、20ms 超のフレーム 0 |
| 初回描画まで | MapLibre より短いこと：同条件で 215ms 未満 |

上の2つのサイズ目標は、**表示の入口**（`mbmap` と表示用 Worker）の予算である。データ・解析・3D などの入口は、それぞれ別の予算を持ち、入口を作るときに計測してから決める。どの入口のサイズも CI で予算と比べ、超えたら失敗させる。**表示しか使わない利用者のバンドルは、ほかの入口を足しても1バイトも増えない**こと。

数値はすべて `bench/` の再現可能なスクリプトで出すこと。体感や推測で「速い」と書かない。

## 3. アーキテクチャ

```
┌──────────────── Main thread ────────────────┐   ┌──────── Worker(s) ────────┐
│ npm (TS facade)  element (<mb-map>)  adapters│   │ worker (Wasm build)       │
│          └──────┬──────────┴──────────┘      │   │  ├ mvt   : PBF/MVT decode  │
│          map (camera, input, tile scheduler)  │◀─▶│  ├ style : filter/式評価   │
│          render-webgl2 (MoonBit js + FFI)     │   │  ├ tess  : earcut, line    │
└──────────────────────────────────────────────┘   │  └ 出力  : 型付きバッファ   │
                                                    └───────────────────────────┘
                core（純MoonBit・全ターゲット共通）: tile math, geometry, buffers
```

### パッケージ構成（MoonBit モジュール内）

- `core/` … タイル座標・Web Mercator・バウンディングボックス・行列演算。依存なし
- `pbf/` … Protocol Buffers の最小デコーダ（ゼロコピー、遅延パース）
- `mvt/` … Mapbox Vector Tile 2.1 デコーダ。地物は必要になるまでジオメトリを展開しない
- `tess/` … ポリゴン三角形分割（earcut 移植）、線の太さ展開（join/cap、ミター制限）、点・円
- `style/` … MapLibre Style Spec の**サブセット**（後述）の評価
- `geom/` … 列指向の地物の表（GeoArrow のマルチポリゴンと同じオフセット、属性はキーごとの列）
- `formats/` … 外部形式の読み込み（今は GeoJSON）。`geom/` の表にする
- `tiler/` … `geom/` の表からベクトルタイルを切り出す（geojson-vt 6.3.0 の移植）
- `worker/` … 表示用 Worker のエントリ。メッセージプロトコルと Transferable なバッファ出力
- `geojson_worker/` … GeoJSON ソース用 Worker のエントリ（`formats` と `tiler`）。`mbmap/geojson` の入口から遅延ロードする
- `analysis/` … 空間索引（flatbush の移植）、計測・点の内外判定（Turf.js と同じ値）、空間クエリ、集計
- `analysis_worker/` … `mbmap/analysis` の Worker のエントリ（`formats` と `analysis`）。データセットをハンドルで保持する
- `wasmio/` … wasm-gc 専用。`geojson_worker` と `analysis_worker` が JS とやりとりする線形メモリの入出力
- `raster/` … 標高タイルの読み込みと、hillshade レイヤー用の勾配（地形解析は `analysis/` の `Grid`）。3D 地形の描画（タイルごとにテクスチャへ描いて起伏に貼る）は `map/` と `render_webgl2/`
- `label/` … ラベルの配置。グリフのアトラスの詰め込み、重なりを判定する画面のグリッド
- `render_webgl2/` … js ターゲット。WebGL2 への FFI、シェーダ、描画パス
- `map/` … カメラ、入力（パン/ピンチ/ホイール）、タイル選択とキャッシュ、フレームループ。**公開 MoonBit API の本体**
- `npm/` … TS ファサード、`.d.ts`、ビルド・パッケージング
- `element/` … Web Component `<mb-map>`（属性・プロパティ・CustomEvent で操作）
- `adapters/` … 後回し。rabbita、Luna 等の薄いラッパーを置く場所として予約だけしておく
- `bench/`、`examples/`

依存の向きは `core ← pbf ← mvt ← tess/style ← worker`、`core ← geom ← formats/tiler ← geojson_worker`、`geom ← analysis ← analysis_worker`、`core ← render_webgl2 ← map ← (npm, element) ← adapters` のみ。逆方向の依存を作らない。**`map/` 以下のパッケージはいかなる UI フレームワークにも依存しない**。

### 入口の分割と遅延ロード

- npm パッケージは1つ（`mbmap`）のまま、**subpath exports で入口を分ける**：`mbmap`（表示）、`mbmap/geojson`、`mbmap/analysis`、`mbmap/3d`、`mbmap/components` など。`import` しない入口はバンドルに入らない。
- データ処理と解析の Wasm は、表示用 Worker とは**別のモジュール**にする。初めて使うときに `import()` で読み込み、専用の Worker で実行する。API は Promise を返す。
- **分割の粒度（Phase 6.5 で計測して決定）**：入口ごとに Wasm モジュールを1つにすることを基本とする（例：`mbmap/analysis` → `analysis.wasm`）。ある機能群の固有のコードが gzip で約 20KB（モジュールごとに重複する core の約3倍）を超えたら、その機能群を別モジュールに切り出す（Clipper2 の移植や座標系変換が候補）。表示用 Worker に解析を入れる一体型にはしない。
  - 根拠：wasm-gc のモジュールを増やす固定費はほぼ 0（空のモジュールで 0.18KB）。一方で、表示用 Worker と共通の core のコード（三角関数、整数の文字列化など）が、モジュールごとに約 6KB 重複する。読み込みは 1〜2.5ms で、一体型と比べても実行速度は変わらない（PROGRESS.md の Phase 6.5）。
- **実行場所**：解析は、表示用とは別の専用の Worker で、初めて使うときに読み込む（Worker の起動は 2〜6ms）。長い解析がタイルの処理を待たせない。データは列指向の ArrayBuffer として transfer する。
- 入口ごとのサイズ予算と、入口の間の参照の制限は `npm/scripts/size.mjs` が CI で確かめる。

### データの共通形式：列指向

- 内部でデータを受け渡す形式は、**GeoArrow 互換の列指向レイアウト**を ArrayBuffer として持つ（座標・オフセット・属性を列ごとの型付き配列にする）。mvt のデコーダが列指向で、Worker の出力を ArrayBuffer で transfer している今の設計の延長にある。
- 読み込み → 解析 → 表示が、コピーなしに Worker の中で閉じるようにする。解析結果は、そのまま描画レイヤーのソースになる。
- GeoArrow に寄せることで、GeoParquet、DuckDB-wasm、deck.gl などと変換なしでつながる。確定したレイアウトは `geom/table.mbt` と [FORMATS.md](FORMATS.md)（Worker の間でやりとりするバイナリとメッセージ）にある。

### 予定しているパッケージ（作るときに構成を確定する）

- `geom/` の拡張 … 空間インデックス（R-tree）、計測
- `formats/` の拡張 … FlatGeobuf、CSV など
- `analysis/` の拡張 … ジオメトリ演算（Clipper2 などの移植を前提に、黄金テストで検証）
- `proj/` … 座標系変換（まず平面直角座標系と JGD2011）
- `raster/` の拡張 … 3D 地形、可視域などのラスタ解析
- 3D … カメラは `core` の `Transform` を一般化する。地形メッシュ、建物の押し出し、glTF / 3D Tiles の展開（Draco、meshopt）は `mbmap/3d` の入口に分ける

`map/` は解析系のパッケージに依存しない。解析系は表示に依存せず、表示とは列指向のバッファだけでつながる。

## 4. 高性能化の設計原則

1. **ホットパスでアロケーションしない**。頂点・インデックスは事前確保した `FixedArray`/`Bytes` に書き込む。Struct-of-Arrays を基本とする
2. **頂点は量子化**：タイル内座標を `TILE_EXTENT`（4096）に換算して Int16 で持ち、GPU 転送量を半減。属性もできるだけ UInt8/Int16 正規化
3. **ゼロコピー転送**：Worker の出力はそのまま `ArrayBuffer` として transfer し、メインスレッドでは `bufferData` するだけ。メインスレッドでジオメトリを触らない
   - ここは Wasm バックエンドの選択に直結する。**Phase 0 で `wasm`（線形メモリ）、`wasm-gc`、`js` の3つを実測**し、JS 側へのバッファ受け渡しコストとデコード速度で決めること
4. **描画コール削減**：タイル×レイヤー単位でバッファを結合、VAO を使い回し、可能なら複数タイルを1ドローにまとめる。点や線端はインスタンシング
5. **フレームループは差分駆動**：カメラ・データが変わらないフレームは描画しない
6. **遅延と予測**：表示範囲外の地物はデコードしない。ズーム遷移中は親/子タイルで穴埋め（overzoom/underzoom）
7. **Worker プール**：`navigator.hardwareConcurrency` に応じて 1〜4。リクエストの優先度付けとキャンセル（見えなくなったタイルは破棄）
8. **使う分しか読み込まない**：機能は入口ごとに分け、Wasm も入口ごとに遅延ロードする。入口ごとのサイズ予算を CI で守る
9. **データは列指向のまま流す**：読み込み・解析・描画の間で、地物単位のオブジェクトを作らない。重い処理は Worker 上の Wasm で行う
10. **3D を見越したカメラと座標**：カメラは bearing・pitch・高さを持つ 4×4 行列で表し、描画はタイルや中心からの相対座標で行う（float32 の精度不足を避ける）

## 5. スコープ

### やる（MVP）
- ベクトルタイル（MVT、`{z}/{x}/{y}.pbf` と PMTiles）
- レイヤー種別：`background` `fill` `line` `circle`、後で `fill-extrusion` `symbol`
- Style Spec サブセット：`filter`（主要な式：`==` `!=` `in` `all` `any` `get` `has` `match`）、`interpolate`/`step` によるズーム依存値、`minzoom`/`maxzoom`
- 操作：パン、ズーム、回転、傾け（ピッチ）
- GeoJSON ソース（Worker 側でタイル分割、geojson-vt 相当）

### 次にやる（MVP の後、§8 の順）
- `symbol`（ラベル）。日本語ラベルを想定し、**グリフ PBF ではなくローカルフォント＋Canvas2D で SDF を生成**する方式（MapLibre の `localIdeographFontFamily` 相当）を基本にする。衝突判定はグリッドインデックス
- データ：FlatGeobuf・CSV の読み込み、座標系変換（列指向の表と GeoJSON は Phase 7 で済み）
- 解析：空間インデックス、計測、空間クエリ、集計、ジオメトリ演算、ラスタ解析
- 3D：地形（DEM）、`fill-extrusion`、3D Tiles / PLATEAU
- コンポーネント：計測、凡例、レイヤー一覧、属性テーブル、作図・編集

### 後回し
- GeoParquet（依存が重いので、入口を分けたうえで検討）、ルート探索、WebGPU バックエンド、MapLibre Tile (MLT)

### やらない（当面）
- Style Spec の完全互換、プラグイン機構、IE/古い Safari 対応
- サーバー側の機能（タイル配信、データベース、認証、編集結果の保存先）。ライブラリはブラウザ内で完結させ、保存や共有は利用者のアプリに任せる
- ArcGIS SDK の機能の網羅

## 6. API 方針

### TS
```ts
import { Map } from "mbmap";
const map = new Map({ container: "map", style: styleJson, center: [139.76, 35.68], zoom: 12 });
map.on("move", (e) => {});
map.setStyle(next);
map.addSource("pts", { type: "geojson", data });
```
MapLibre の API に**名前と形を寄せる**（移行コストを下げるため）が、完全互換は目指さない。

データ処理と解析は別の入口から使う。初回の呼び出しで Wasm を読み込み、Worker で実行して Promise を返す（イメージ。名前は作るときに決める）。
```ts
import { readGeoJSON } from "mbmap/geojson";
import { buffer, area } from "mbmap/analysis";
const table = await readGeoJSON(file);          // 列指向のジオメトリ表
const zones = await buffer(table, { meters: 500 });
map.addSource("zones", { type: "table", data: zones }); // コピーなしで描画に渡す
```

### MoonBit
- `map/` が素の API を提供する：`Map::new(canvas, options)`、`set_camera`、`on_move` など
- 状態の持ち方は「エンジン内部に持つ」が基本。ただし外部の状態管理と同期しやすいよう、以下を守る
  - カメラ状態（中心・ズーム・回転・ピッチ）を値として取得・設定できる（`camera() -> Camera`、`set_camera(Camera)`）
  - イベントはコールバック登録で受け取り、解除できる（購読解除用の値を返す）
  - 外部から `set_camera` されたときに、同じ値の move イベントを再発火してループさせない

### Web Component
- `<mb-map style-url="..." center="139.76,35.68" zoom="12">` のように属性で初期化でき、プロパティで `map` インスタンスに触れる
- `mb-move` `mb-load` などを `CustomEvent` で発火する
- Shadow DOM 内に canvas を持つので、仮想 DOM 系フレームワーク（rabbita、React 等）から見ると「中身を触らない1要素」として扱える。これが UI フレームワーク非依存の要

### UI ライブラリ向けアダプタ（後回し）
- rabbita（TEA 型）や Luna（Signal 型）は設計思想が異なり、どちらが主流になるかまだ読めない。**コア側で特定の流儀に寄せない**
- 着手する場合は、Web Component をラップする数百行程度の薄い層に留める。着手前に対象ライブラリの現行ソースで、外部 DOM／カスタム要素の扱い方を確認すること

## 7. 作業ルール

- **MoonBit の構文・ツールチェーンは変化が速い**。着手時に `moon version` を記録し、公式ドキュメント（docs.moonbitlang.com）と使用ライブラリのソースを確認してから書く。記憶で API を推測しない。不明点はドキュメントや `moon info` で生成される `.mbti` で確認する
- 各パッケージで `moon check`、`moon test`（可能な全ターゲット）、`moon fmt`、`moon info` を通してからコミット
- テストは**黄金データ**で：既存の実装（@mapbox/vector-tile、earcut の JS 版など）の出力と突き合わせるスクリプトを `bench/` か `test/fixtures/` に置く。テッセレーションは三角形の総面積が元ポリゴンと一致することも検証
- テストデータ：国土地理院ベクトルタイル（`experimental_bvmap`）や OpenStreetMap 由来のタイルを少数、出典表記とともに fixtures 化
- 各 Phase の終わりに `PROGRESS.md` を更新：できたこと、ベンチ結果、既知の問題、次にやること
- 大きな設計変更（Wasm バックエンドの選択、パッケージ分割の変更、描画方式の変更）は、計測結果と選択肢を示して**ユーザーに確認してから**進める
- ライセンス：Apache-2.0。他実装を移植する場合は元ライセンスと出典をファイル先頭とNOTICEに記載

## 8. フェーズ計画

| Phase | 内容 | 完了条件 |
|---|---|---|
| 0 | 環境確認、リポジトリ雛形、ベンチ基盤、**Wasm バックエンド比較** | MapLibre の基準値と、wasm/wasm-gc/js の比較表が PROGRESS.md にある |
| 1 | `core`, `pbf`, `mvt` | 実タイルを JS 実装と同一結果でデコード。デコード速度を計測 |
| 2 | `tess`（earcut 移植、線展開） | 面積一致テスト、JS 版 earcut との速度比較 |
| 3 | `worker` + `render_webgl2` + `map` 最小版 | fill/line/background が表示され、パン・ズームできる example |
| 4 | `style` サブセット | 国土地理院の簡易スタイル程度が描ける |
| 5 | npm パッケージ（TS ファサード、`.d.ts`、ESM、サイズ計測を CI に） | `npm pack` した成果物で example が動く |
| 6 | Web Component `<mb-map>` | 素の HTML と、主要な JS フレームワーク1つ（例：React）の example で動く |
| 6.5 | 試作：入口の分割と Wasm の遅延ロード | 2つ目の wasm-gc モジュールのサイズ増と読み込み時間が PROGRESS.md にあり、分割の粒度を決めた。入口ごとのサイズ予算を CI で確かめる仕組みがある |
| 7 | 3D を見越したカメラ（回転・ピッチ）、circle、列指向データの基盤、GeoJSON ソース | 回転・ピッチできる example。列指向の形式を確定し、GeoJSON の読み込みとタイル分割を JS 実装（geojson-vt など）と黄金テスト・速度で比べた |
| 8 | `mbmap/analysis` 第1弾：空間インデックス、計測、空間クエリ、集計 | JS 実装（flatbush、Turf.js など）との黄金テストと速度比較。表示だけの利用ではバンドルが増えないことを CI で確かめる |
| 9 | symbol（日本語ラベル） | — |
| 10 | 地形（DEM）、`fill-extrusion`、ラスタ解析（傾斜、陰影） | 国土地理院の DEM で地形を表示する example。解析結果を既存実装と比べた |
| 11 | ジオメトリ演算（buffer、交差、結合）、座標系変換 | Clipper2・proj4js などとの黄金テスト |
| 12〜 | 3D Tiles / PLATEAU、データ形式の拡充、UI コンポーネント群、作図・編集 | 各段階で完了条件を決める |
| 以降 | UI ライブラリ向けアダプタ（rabbita、Luna 等）、WebGPU | 需要を見て判断 |

## 9. 最初の指示（Phase 0）

1. `moon version`、Node、ブラウザ環境を確認して記録
2. 上記パッケージ構成で雛形を作成（中身は空でよい）、`moon test` が通る状態にする
3. `bench/` に以下を用意
   - MapLibre GL JS で同じタイル・同じスタイルを描画し、初回描画時間・フレーム時間・バンドルサイズを計測するページ
   - MoonBit の簡単なベンチ（例：pbf の varint デコードを大量に回す）を wasm / wasm-gc / js でビルドし、実行時間と「結果バッファを JS の `Float32Array` として受け取るまでのコスト」を比較
4. 結果と、どのバックエンドを Worker に採用すべきかの提案を PROGRESS.md にまとめ、**私に確認を求めて止まる**
