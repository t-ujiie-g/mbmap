# mbmap

MoonBit 製の軽量・高性能な Web 向けベクトルタイル地図描画エンジン（開発中）。

- ビジョンと設計方針: [docs/VISION.md](docs/VISION.md)
- 進捗・ベンチ結果: [PROGRESS.md](PROGRESS.md)
- ベンチマーク: [bench/README.md](bench/README.md)

## 開発

```sh
moon check --target all
moon test --target all
moon fmt && moon info
```

## パッケージ

| パッケージ | 役割 | ターゲット |
|---|---|---|
| `core/` | タイル座標・Web Mercator・BBox・行列、カメラ（ピッチ 85° まで、地平線、地形の高さ） | 全 |
| `pbf/` | Protocol Buffers 最小デコーダ | 全 |
| `mvt/` | MVT 2.1 デコーダ | 全 |
| `tess/` | earcut 移植、線の展開、fill-extrusion の壁と屋根 | 全 |
| `style/` | Style Spec サブセット評価 | 全 |
| `geom/` | 列指向の地物の表（GeoArrow と同じオフセット、属性はキーごとの列） | 全 |
| `formats/` | GeoJSON などの読み込み（`geom` の表へ） | 全 |
| `tiler/` | 地物の表からベクトルタイルを切り出す（geojson-vt の移植） | 全 |
| `worker/` | Worker エントリ、メッセージプロトコル | 全（配布は Wasm） |
| `analysis/` | 空間索引（flatbush の移植）、計測と点の内外判定（Turf.js と同じ値）、集計 | 全 |
| `geojson_worker/` | GeoJSON ソースの Worker（読み込みとタイル分割） | wasm-gc |
| `analysis_worker/` | 解析の Worker（データセットをハンドルで保持） | wasm-gc |
| `clipper/` | Clipper2 2.0.1 の移植（ブール演算、オフセット。C++ 版と同じ結果） | 全 |
| `overlay/` | 地物の表に対する buffer（測地線・平面）、dissolve、clip、erase、intersect | 全 |
| `geometry_worker/` | ジオメトリ演算の wasm（解析の Worker が初回に読み込む） | wasm-gc |
| `wasmio/` | wasm-gc の Worker が JS とやりとりする線形メモリの入出力 | wasm-gc |
| `raster/` | 標高タイルの読み込み（RGB から標高）、hillshade 用の勾配 | 全 |
| `label/` | ラベルの配置（グリフのアトラス、重なりを判定する画面のグリッド） | 全 |
| `render_webgl2/` | WebGL2 FFI、シェーダ、描画パス | js |
| `map/` | カメラ、入力、タイル選択、フレームループ、地形・空・ラベルの配置（公開 MoonBit API） | js |

`npm/`、`element/`、`adapters/`、`examples/` は MoonBit パッケージではない（TS / HTML 側）。

## 例を動かす

```sh
npm --prefix bench ci && npm --prefix npm ci   # 初回だけ
npm --prefix bench run fixtures                # 東京駅周辺のタイルを取得
npm --prefix bench run examples                # ビルドして 127.0.0.1:8080 で配信
```

http://127.0.0.1:8080/examples/ を開く（basic、npm パッケージ、GeoJSON、解析、`<mb-map>`、React の例）。詳しくは [examples/README.md](examples/README.md)。

## npm パッケージ

`npm/` が npm パッケージ `mbmap`（TS ファサード、`.d.ts`、ESM）。使い方は [npm/README.md](npm/README.md)。

```sh
cd npm && npm ci && npm run build && npm run size   # dist/ を作り、gzip サイズを予算と比べる
npm --prefix bench run npm:pack                     # npm pack した成果物で examples/npm を動かして確かめる
```

## ライセンス

Apache-2.0。[LICENSE](LICENSE) と [NOTICE](NOTICE) を参照。
