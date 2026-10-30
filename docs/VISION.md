# MoonBit製 地図描画エンジン Vision
## 1. ゴール

MoonBit で、**軽量かつ既存ライブラリを上回る性能**の Web 向けベクトルタイル地図描画エンジンを作る。

- 比較対象：MapLibre GL JS、MachGL（Geolonia、gzip 約98KB・WebGL2・Web Worker 構成）
- **特定の UI フレームワークに依存しない**。地図は「canvas を受け取って描く命令的なエンジン」とし、UI フレームワークとの統合は外側の薄い層で行う
- 利用形態の優先順位：
  1. **TS/JS から**（最優先）：npm パッケージ、型定義（`.d.ts`）付き、ESM
  2. **MoonBit から**：mooncakes パッケージとして import できる素の API（FFI を経由せず直接呼べる）
  3. **Web Component**（`<mb-map>`）：React / Vue / Svelte / Luna / rabbita など、どのフレームワークからも使える共通の受け口
  4. 各 UI ライブラリ向けアダプタ（rabbita、Luna など）：需要が見えてから。コアの設計をこれらに合わせて曲げない
- 計算コアは純 MoonBit で書き、どのバックエンド（wasm / wasm-gc / js / native）でもテストが通ること

## 2. 性能目標（ベンチマークで常に計測する）

| 指標 | 目標（初期値。Phase 0 で MapLibre を計測して見直す） |
|---|---|
| メインスレッド側バンドル | gzip 50KB 以下 |
| Worker（Wasm 含む） | gzip 80KB 以下 |
| 1タイルのデコード＋テッセレーション（z14 都市部） | MapLibre の 1/2 以下の時間 |
| フレーム時間 | 中級 Android 端末で 60fps、パン・ズーム中の GC 停止なし |
| 初回描画まで | MapLibre より短いこと |

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
- `worker/` … Worker エントリ。メッセージプロトコルと Transferable なバッファ出力
- `render_webgl2/` … js ターゲット。WebGL2 への FFI、シェーダ、描画パス
- `map/` … カメラ、入力（パン/ピンチ/ホイール）、タイル選択とキャッシュ、フレームループ。**公開 MoonBit API の本体**
- `npm/` … TS ファサード、`.d.ts`、ビルド・パッケージング
- `element/` … Web Component `<mb-map>`（属性・プロパティ・CustomEvent で操作）
- `adapters/` … 後回し。rabbita、Luna 等の薄いラッパーを置く場所として予約だけしておく
- `bench/`、`examples/`

依存の向きは `core ← pbf ← mvt ← tess/style ← worker`、`core ← render_webgl2 ← map ← (npm, element) ← adapters` のみ。逆方向の依存を作らない。**`map/` 以下のパッケージはいかなる UI フレームワークにも依存しない**。

## 4. 高性能化の設計原則

1. **ホットパスでアロケーションしない**。頂点・インデックスは事前確保した `FixedArray`/`Bytes` に書き込む。Struct-of-Arrays を基本とする
2. **頂点は量子化**：タイル内座標（extent 4096 → 8192 にスケール）を Int16 で持ち、GPU 転送量を半減。属性もできるだけ UInt8/Int16 正規化
3. **ゼロコピー転送**：Worker の出力はそのまま `ArrayBuffer` として transfer し、メインスレッドでは `bufferData` するだけ。メインスレッドでジオメトリを触らない
   - ここは Wasm バックエンドの選択に直結する。**Phase 0 で `wasm`（線形メモリ）、`wasm-gc`、`js` の3つを実測**し、JS 側へのバッファ受け渡しコストとデコード速度で決めること
4. **描画コール削減**：タイル×レイヤー単位でバッファを結合、VAO を使い回し、可能なら複数タイルを1ドローにまとめる。点や線端はインスタンシング
5. **フレームループは差分駆動**：カメラ・データが変わらないフレームは描画しない
6. **遅延と予測**：表示範囲外の地物はデコードしない。ズーム遷移中は親/子タイルで穴埋め（overzoom/underzoom）
7. **Worker プール**：`navigator.hardwareConcurrency` に応じて 1〜4。リクエストの優先度付けとキャンセル（見えなくなったタイルは破棄）

## 5. スコープ

### やる（MVP）
- ベクトルタイル（MVT、`{z}/{x}/{y}.pbf` と PMTiles）
- レイヤー種別：`background` `fill` `line` `circle`、後で `fill-extrusion` `symbol`
- Style Spec サブセット：`filter`（主要な式：`==` `!=` `in` `all` `any` `get` `has` `match`）、`interpolate`/`step` によるズーム依存値、`minzoom`/`maxzoom`
- 操作：パン、ズーム、回転、傾け（ピッチ）
- GeoJSON ソース（Worker 側でタイル分割、geojson-vt 相当）

### 後回し
- `symbol`（ラベル）。日本語ラベルを想定し、**グリフ PBF ではなくローカルフォント＋Canvas2D で SDF を生成**する方式（MapLibre の `localIdeographFontFamily` 相当）を基本にする。衝突判定はグリッドインデックス
- 地形（DEM）、3D 建物、PLATEAU、WebGPU バックエンド、MapLibre Tile (MLT)

### やらない（当面）
- Style Spec の完全互換、プラグイン機構、IE/古い Safari 対応

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
| 7 | 回転・ピッチ、circle、GeoJSON ソース | — |
| 8 | symbol（日本語ラベル） | — |
| 以降 | UI ライブラリ向けアダプタ（rabbita、Luna 等） | 需要を見て判断 |

## 9. 最初の指示（Phase 0）

1. `moon version`、Node、ブラウザ環境を確認して記録
2. 上記パッケージ構成で雛形を作成（中身は空でよい）、`moon test` が通る状態にする
3. `bench/` に以下を用意
   - MapLibre GL JS で同じタイル・同じスタイルを描画し、初回描画時間・フレーム時間・バンドルサイズを計測するページ
   - MoonBit の簡単なベンチ（例：pbf の varint デコードを大量に回す）を wasm / wasm-gc / js でビルドし、実行時間と「結果バッファを JS の `Float32Array` として受け取るまでのコスト」を比較
4. 結果と、どのバックエンドを Worker に採用すべきかの提案を PROGRESS.md にまとめ、**私に確認を求めて止まる**
