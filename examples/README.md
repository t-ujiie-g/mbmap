# examples/

| 例 | 内容 |
|---|---|
| [basic/](basic/) | 国土地理院ベクトルタイル（`bench/fixtures`）を background / fill / line で描き、ドラッグ・ホイール・ピンチで操作する |

## 動かし方

```sh
moon build bundle/main --target js --release
moon build worker --target wasm-gc --release
npm --prefix bench run fixtures           # タイルを取得
node bench/lib/serve.mjs                  # リポジトリのルートを配信（URL を表示）
```

表示された URL の `/examples/basic/` を開く。
