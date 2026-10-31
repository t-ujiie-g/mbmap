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
| `core/` | タイル座標・Web Mercator・BBox・行列 | 全 |
| `pbf/` | Protocol Buffers 最小デコーダ | 全 |
| `mvt/` | MVT 2.1 デコーダ | 全 |
| `tess/` | earcut 移植、線の展開 | 全 |
| `style/` | Style Spec サブセット評価 | 全 |
| `geom/` | 列指向の地物の表（GeoArrow と同じオフセット、属性はキーごとの列） | 全 |
| `formats/` | GeoJSON などの読み込み（`geom` の表へ） | 全 |
| `tiler/` | 地物の表からベクトルタイルを切り出す（geojson-vt の移植） | 全 |
| `worker/` | Worker エントリ、メッセージプロトコル | 全（配布は Wasm） |
| `render_webgl2/` | WebGL2 FFI、シェーダ、描画パス | js |
| `map/` | カメラ、入力、タイル選択、フレームループ（公開 MoonBit API） | js |

`npm/`、`element/`、`adapters/`、`examples/` は MoonBit パッケージではない（TS / HTML 側）。

## 例を動かす

```sh
npm --prefix bench ci && npm --prefix npm ci   # 初回だけ
npm --prefix bench run fixtures                # 東京駅周辺のタイルを取得
npm --prefix bench run examples                # ビルドして 127.0.0.1:8080 で配信
```

http://127.0.0.1:8080/examples/ を開く（basic、npm パッケージ、`<mb-map>`、React の例）。詳しくは [examples/README.md](examples/README.md)。

## npm パッケージ

`npm/` が npm パッケージ `mbmap`（TS ファサード、`.d.ts`、ESM）。使い方は [npm/README.md](npm/README.md)。

```sh
cd npm && npm ci && npm run build && npm run size   # dist/ を作り、gzip サイズを予算と比べる
npm --prefix bench run npm:pack                     # npm pack した成果物で examples/npm を動かして確かめる
```

## ライセンス

Apache-2.0。[LICENSE](LICENSE) と [NOTICE](NOTICE) を参照。
