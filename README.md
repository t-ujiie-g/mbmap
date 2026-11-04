# mbmap

MoonBit 製の軽量・高性能な Web 向けベクトルタイル地図描画エンジン（開発中）。

- ビジョンと設計方針: [docs/VISION.md](docs/VISION.md)
- 進捗・ベンチ結果: [PROGRESS.md](PROGRESS.md)
- ベンチマーク: [bench/README.md](bench/README.md)
- 開発の決まり（人と AI エージェント向け）: [AGENTS.md](AGENTS.md)、Claude Code on the web での開発: [docs/CLOUD.md](docs/CLOUD.md)

## 開発

新しい Linux の環境（Claude Code on the web、CI）は `scripts/setup.sh` でツールチェーンと依存を入れる。

```sh
moon check --target all
moon test --target all
moon fmt && moon info
```

## パッケージ

依存の向き（逆にしない。詳しくは [AGENTS.md](AGENTS.md) §4）：`core ← pbf ← mvt ← tess/style ← worker`、`core ← geom ← formats/tiler ← geojson_tiles ← geojson_worker`、`style/tiler ← cluster_props ← geojson_props_worker`、`geom ← analysis ← analysis_worker`、`geom/clipper ← overlay ← geometry_worker`、`proj ← proj_worker`、`core ← geodesic ← geodesic_worker`、`core ← render_webgl2 ← map ← bundle/main`。

表示（地図を描くもの）：

| パッケージ | 役割 | ターゲット |
|---|---|---|
| `core/` | タイル座標・Web Mercator・BBox・行列、カメラ（ピッチ 85° まで、地平線、地形の高さと遮蔽）、カメラの移動と制約、タイルの選択、当たり判定、Worker と受け渡すバイト列の読み書き | 全 |
| `pbf/` | Protocol Buffers 最小デコーダ | 全 |
| `mvt/` | MVT 2.1 デコーダ | 全 |
| `tess/` | earcut 移植、線の展開、円の四角形、fill-extrusion の壁と屋根 | 全 |
| `style/` | Style Spec の読み込みと式（コンパイル、評価、Worker 向けのコンパイル済みの形） | 全 |
| `raster/` | 標高タイルの読み込み（RGB から標高）、hillshade 用の勾配 | 全 |
| `label/` | ラベルの配置（グリフのアトラス、重なりを判定する画面のグリッド） | 全 |
| `worker/` | タイル Worker の wasm（デコード、テッセレーション、GPU 用バッファへの書き込み、地物の問い合わせ） | 全（配布は wasm-gc） |
| `render_webgl2/` | WebGL2 FFI、シェーダ、描画パス | js |
| `map/` | カメラ、入力、タイル選択、フレームループ、地形・空・ラベルの配置（公開 MoonBit API） | js |
| `bundle/main/` | `map` を JS に公開する入口（npm パッケージのファサードが読む） | js |

GeoJSON ソース：

| パッケージ | 役割 | ターゲット |
|---|---|---|
| `geom/` | 列指向の地物の表（GeoArrow と同じオフセット、属性はキーごとの列） | 全 |
| `formats/` | GeoJSON などの読み込み（`geom` の表へ） | 全 |
| `tiler/` | 地物の表からベクトルタイルを切り出す（geojson-vt の移植、クラスタを含む） | 全 |
| `cluster_props/` | クラスタの `clusterProperties` を式で集計する | 全 |
| `geojson_tiles/` | GeoJSON ソースの読み込み、索引、タイルの切り出し（2 つの GeoJSON の wasm が共有する） | wasm-gc |
| `geojson_worker/` | GeoJSON ソースの wasm（`geojson.wasm`） | wasm-gc |
| `geojson_props_worker/` | 式を持つ GeoJSON の wasm（`geojson-properties.wasm`。`clusterProperties` のあるソース用） | wasm-gc |

解析・ジオメトリ・座標系・測地線（それぞれ別の Worker と wasm）：

| パッケージ | 役割 | ターゲット |
|---|---|---|
| `analysis/` | 空間索引（flatbush の移植）、計測と点の内外判定（Turf.js と同じ値）、集計、標高の格子（gdaldem と同じ勾配・斜面方位・陰影） | 全 |
| `analysis_worker/` | 解析の wasm（データセットをハンドルで保持） | wasm-gc |
| `clipper/` | Clipper2 2.0.1 の移植（ブール演算、オフセット。C++ 版と同じ結果） | 全 |
| `overlay/` | 地物の表に対する buffer（測地線・平面）、dissolve、clip、erase、intersect、split、merge | 全 |
| `geometry_worker/` | ジオメトリ演算の wasm（解析の Worker が初回に読み込む） | wasm-gc |
| `proj/` | 座標系の変換（proj4js の移植：27 の投影、3・7 パラメータの測地系変換、EPSG コードと PROJ 文字列） | 全 |
| `proj_worker/` | 座標系の wasm（解析の Worker が初回に読み込む） | wasm-gc |
| `geodesic/` | 楕円体の上の測地線（geographiclib-geodesic の移植：順・逆問題、多角形の面積、線に沿った点） | 全 |
| `geodesic_worker/` | 測地線の wasm（`mbmap/geodesic`） | wasm-gc |

共通：

| パッケージ | 役割 | ターゲット |
|---|---|---|
| `wasmio/` | wasm-gc のモジュールが JS とやりとりする線形メモリの入出力と、ホストの `Math`・`Number`・`Intl` | wasm-gc |

`bench/` の下にもベンチ専用の MoonBit パッケージがある（[bench/README.md](bench/README.md)）。`npm/`、`element/`、`adapters/`、`examples/` は MoonBit パッケージではない（TS / HTML 側）。

## 例を動かす

```sh
npm --prefix bench ci && npm --prefix npm ci   # 初回だけ
npm --prefix bench run fixtures                # 東京駅周辺のタイルを取得（?local=1 で読むとき）
npm --prefix bench run examples                # ビルドして 127.0.0.1:8080 で配信
```

http://127.0.0.1:8080/examples/ を開く。同じ地図アプリ（2D/3D の切り替え、背景地図とレイヤーの切り替え、凡例、検索、作図、計測と断面図、解析など）を、素の HTML・`<mb-map>`・React の 3 通りで書いている。詳しくは [examples/README.md](examples/README.md)。

## npm パッケージ

`npm/` が npm パッケージ `mbmap`（TS ファサード、`.d.ts`、ESM）。使い方は [npm/README.md](npm/README.md)。

```sh
cd npm && npm ci && npm run build && npm run size   # dist/ を作り、gzip サイズを予算と比べる
npm --prefix bench run npm:pack                     # npm pack した成果物で examples と試験用のページを動かして確かめる
```

## ライセンス

Apache-2.0。[LICENSE](LICENSE) と [NOTICE](NOTICE) を参照。
