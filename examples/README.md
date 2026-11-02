# examples/

同じ地図アプリ（ショーケース）を、3 通りの書き方で作っています。機能は 3 つとも同じです。

| 例 | 書き方 |
|---|---|
| [html/](html/) | `import { Map } from "mbmap"` と DOM |
| [element/](element/) | `<mb-map>` の属性・プロパティ・イベント |
| [react/](react/) | React 19 から `<mb-map>` を JSX で（esbuild でバンドル） |

## 入っている機能

- 2D と 3D の切り替え：3D では、国土地理院の標高タイルで地形に貼り、建物を押し出し、空を描き、傾ける。今は切り替えるたびに地図を作り直す（`setStyle` は Phase 12.2 で作る）。
- 地点への移動（`flyTo`）：東京駅、富士山、大阪駅、京都、札幌駅。
- カメラの状態（経度・緯度・ズーム・方位・傾き）と、最寄りの原点の平面直角座標系での座標（`mbmap/analysis` の `transform`）。
- 画面の中心から 5 km 以内の地点：中心の点を測地線で 5 km 広げ（`buffer`）、その中にある GeoJSON の地点を数える（`pointsWithin`）。移動が終わるたびに計算する。
- GeoJSON ソースの点とラベル、陰影起伏（hillshade）、国土地理院のベクトルタイルの面・線・記号・ラベル（横書き・縦書き）。
- Phase が進むたびに機能を足す（各 Phase の完了条件に含める）。

共通のスタイル・データ・解析は [shared/](shared/) にあり、3 つの例が同じものを使う。

## 動かし方

```sh
npm --prefix bench ci                     # 初回だけ（bench の依存）
npm --prefix npm ci                       # 初回だけ（パッケージのビルドに使う esbuild と TypeScript）
npm --prefix bench run examples           # パッケージをビルド・npm pack して各例に入れ、:8080 で配信
```

http://127.0.0.1:8080/examples/ を開く。地図は国土地理院の配信タイル（ベクトルタイル z4〜16、標高タイル z1〜14）を直接読む。
ネットワークなしで試すときや自動テストでは、`?local=1` でベンチ用のタイル（東京駅周辺の z14、`npm --prefix bench run fixtures` で取得）を読む。

開発用の、MoonBit のビルドを直接読むページは `bench/pages/`（basic、terrain）に、パッケージの試験に使うページは `bench/npm/pages/` にある。
