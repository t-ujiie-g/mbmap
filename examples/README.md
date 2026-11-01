# examples/

| 例 | 内容 |
|---|---|
| [basic/](basic/) | MoonBit のビルド（`_build/`）を直接読む最小の例。国土地理院ベクトルタイルを background / fill / line で描き、ドラッグ・ホイール・ピンチで操作する |
| [npm/](npm/) | npm パッケージを `import { Map } from "mbmap"` で使う例。スタイルは URL で渡す |
| [geojson/](geojson/) | スタイルに GeoJSON ソースを書く例（URL の `places.geojson` と、スタイルに直接書いたデータ）。GeoJSON 用の Worker と wasm は、この例のように GeoJSON ソースがあるときだけ読み込まれる |
| [analysis/](analysis/) | `mbmap/analysis` で点をブロックごとに数え（面積・件数・平均）、その結果でブロックを塗り分けて地図に出す例。解析は専用の Worker で動く |
| [terrain/](terrain/) | 富士山の陰影起伏（hillshade レイヤー、国土地理院の標高タイル）を、スタイルの `terrain` で立体の地形に貼って描く。`?remote=1` で配信中の標高タイル（z1〜14）を読む |
| [element/](element/) | 素の HTML に `<mb-map>` を置く例（import map で `mbmap/element` を読む） |
| [react/](react/) | React 19 から `<mb-map>` を使う例。左上のボタンで props を変えて地図を動かし、ホイールで動かすと `onmb-move` で表示が追従する |

## 動かし方

```sh
npm --prefix bench ci                     # 初回だけ（bench の依存）
npm --prefix npm ci                       # 初回だけ（パッケージのビルドに使う esbuild と TypeScript）
npm --prefix bench run fixtures           # タイルを取得（basic を ?remote=1 で開くだけなら不要）
npm --prefix bench run examples           # パッケージをビルド・npm pack して各例に入れ、:8080 で配信
```

http://127.0.0.1:8080/examples/ を開くと、すべての例へのリンクがある。

- `npm run examples` は、`npm pack` した tarball を `npm/`・`geojson/`・`analysis/`・`element/`・`react/` の `node_modules/mbmap` に展開し（アプリがインストールするのと同じ形）、React の例を esbuild でバンドルしてから配信する。basic だけでよければ `npm --prefix bench run example` で足りる。
- 同じ準備をしたうえで、各例の動作を Chromium で自動的に確かめるのが `npm --prefix bench run npm:pack`（CI でも実行する）。
- 既定では、ベンチ用の fixture（東京駅周辺の z14、7×5 タイル）を読む。z14 未満にズームアウトしたり範囲外へパンしたりすると何も描かれないのは、データがないため。
- basic は `?zoom=15&bearing=30&pitch=50` のように初期のカメラを指定できる。`?terrain=1`（と `&exaggeration=4`）で標高タイルの地形に貼って描く（`?remote=1` がなければ fixtures の z14 の標高タイル）。どの例でも、右ドラッグ（または Ctrl＋ドラッグ）で回転・傾き、2本指をひねると回転する。
- basic に `?remote=1` を付けると、国土地理院の配信サーバー（`experimental_bvmap`、z4〜16）から直接読むので、全国・全ズームで動く。`&zoom=10` のように初期ズームも指定できる。低ズームのタイル（z5 で確認）には、このスタイルが使う面のレイヤー（waterarea など）がないので、道路・鉄道・河川だけが描かれる。また配信のない範囲（一部の海域など）は 404 になり、ブラウザのコンソールにその記録が出る（地図は空として扱う）。
