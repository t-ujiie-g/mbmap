# examples/

| 例 | 内容 |
|---|---|
| [basic/](basic/) | MoonBit のビルド（`_build/`）を直接読む最小の例。国土地理院ベクトルタイルを background / fill / line で描き、ドラッグ・ホイール・ピンチで操作する |
| [npm/](npm/) | npm パッケージを `import { Map } from "mbmap"` で使う例。スタイルは URL で渡す |
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

- `npm run examples` は、`npm pack` した tarball を `npm/`・`element/`・`react/` の `node_modules/mbmap` に展開し（アプリがインストールするのと同じ形）、React の例を esbuild でバンドルしてから配信する。basic だけでよければ `npm --prefix bench run example` で足りる。
- 同じ準備をしたうえで、各例の動作を Chromium で自動的に確かめるのが `npm --prefix bench run npm:pack`（CI でも実行する）。
- 既定では、ベンチ用の fixture（東京駅周辺の z14、7×5 タイル）を読む。z14 未満にズームアウトしたり範囲外へパンしたりすると何も描かれないのは、データがないため。
- basic に `?remote=1` を付けると、国土地理院の配信サーバー（`experimental_bvmap`、z4〜16）から直接読むので、全国・全ズームで動く。`&zoom=10` のように初期ズームも指定できる。低ズームのタイル（z5 で確認）には、このスタイルが使う面のレイヤー（waterarea など）がないので、道路・鉄道・河川だけが描かれる。また配信のない範囲（一部の海域など）は 404 になり、ブラウザのコンソールにその記録が出る（地図は空として扱う）。
