# examples/

同じ地図アプリ（ショーケース）を、3 通りの書き方で作っています。機能も見た目も 3 つとも同じです。

画面は地図を中心に、左のパネル（検索と「探す」「レイヤー」「作図」「計測」「データ」のタブ）、右上の 2D・3D と保存とコントロール、下のステータスバー（ポインタの座標、縮尺、出典）でできています。幅の狭い画面では、パネルは下のシートになります。駅の密度、散歩道、駅の略図は最初は切ってあり、「レイヤー」のタブで出します。

| 例 | 書き方 |
|---|---|
| [html/](html/) | `import { Map } from "mbmap"` と DOM |
| [element/](element/) | `<mb-map>` の属性・プロパティ・イベント |
| [react/](react/) | React 19 から `<mb-map>` を JSX で（esbuild でバンドル） |

## 入っている機能

地図とスタイル：

- 2D と 3D の切り替え（`setStyle`。地図は作り直さず、変わらないソースのタイルは残す）：3D では、国土地理院の標高タイルで地形に貼り、建物を押し出し、空を描き、傾ける。
- 国土地理院のベクトルタイルの面・線・記号・ラベル（横書き・縦書き）、等高線に沿った高さのラベル、構造物の斜線（スプライトの `fill-pattern`）、陰影起伏（hillshade）、標高点の大きさを標高で変える式。
- 背景地図の切り替え（`mbmap/ui` の `createBasemaps`）：地図と、国土地理院のシームレス空中写真（ラスタ）。地点や駅などの重ねるレイヤーは、切り替えても残る。
- レイヤーの一覧（`createLayerList`。グループごとに `visibility` を切り替える）と凡例（`createLegend`。属性で色が変わるレイヤーは区分ごと）。
- 地点（GeoJSON ソース）：中心に印を置く（`setData`）、上に乗ると強調する（`setFeatureState` の `hover` を paint の `feature-state` で読む。id は `promoteId` で地点名）、カーソルを変える（レイヤーの `mousemove`・`mouseleave`）、名前を空いている側に置く（`text-variable-anchor`）。
- 山手線の駅：クラスタ（`cluster: true`。まとまりの円の大きさは駅の数で変わり、数をラベルにする。クリックすると、それが分かれるズーム（`getClusterExpansionZoom`）へ移る）、駅のアイコン（スプライトの `icon-image`）、駅の密度（heatmap）。
- 東京駅のまわりの散歩道（`lineMetrics` と `line-gradient` で、始めから終わりへ色が変わる線）、駅の略図（image ソースで四隅を指定して重ねる）、解析の半径の輪（カスタムレイヤーが自前の WebGL で描く）。

操作と表示：

- 地点への移動（`flyTo`）：東京駅、富士山、大阪駅、京都、札幌駅。移動先には、地図の上を追いかける DOM のピン（`map.track`。地形に隠れると薄くなる）。
- 地図の上のコントロール（`mbmap/ui`）：ズーム、方位、ホーム、現在地（`createGeolocation`）、全画面、縮尺、出典の表示。
- カメラの状態（経度・緯度・ズーム・方位・傾き）と、最寄りの原点の平面直角座標系での座標（`mbmap/analysis` の `transform`）。マウスの位置の座標を、度・度分秒・平面直角座標系・UTM で表示する（`createCoordinates`）。
- クリックした地物の表示（`createIdentify`。`queryRenderedFeatures` で、いちばん上の地物のレイヤーと名前など。選んだ地点は `selected` の状態で強調する）。
- 地点の属性テーブル（`createAttributeTable`）：見出しのクリックで並べ替え（名前・種別）、入力で絞り込み（全角半角・カタカナとひらがなを区別しない）、ページ送り。行のクリックで、その地点を `selected` の状態で強調して地図を合わせる（Shift で選択に足す）。印を置くと行が増える（`sourcedata`）。
- 検索（`mbmap/search`）：座標（度、度分秒、平面直角座標系、UTM）と地点の名前。`?gsi-search=1` で国土地理院の地名検索を外部のプロバイダとして足す（利用条件は [npm/README.md](../npm/README.md) の検索の節）。
- 作図（`mbmap/draw`）：点、線、多角形、矩形、円（`mbmap/geodesic` で楕円体の上の円）、フリーハンド、選択と編集、スナップ、分割と結合（`mbmap/analysis` の `splitFeatures`・`mergeFeatures`）、名前とメモの属性、取り消しとやり直し。
- データの読み込み（`mbmap/data`）：ファイルの選択かドロップ、または「サンプルを読む」（東京の公園の CSV）。CSV、Shapefile（zip）、KML/KMZ、GPX、TopoJSON、FlatGeobuf、GeoJSON を GeoJSON ソースとして重ね、範囲に移動する。読んだデータは GeoJSON、CSV、KML に書き出せる。スタイルを切り替えても残る。
- 計測（`createMeasurement` と `mbmap/geodesic` の `measure`）：距離と面積。距離を測り終えると、その線の断面図（`createProfile`。標高は `mbmap/analysis` の `sampleDem` で国土地理院の標高タイルから。グラフの上のポインタの位置は地図にも点で出る）。
- 画像の保存（`toBlob`。画面の 2 倍の解像度の PNG）。
- 画面の中心から 5 km 以内の地点：中心の点を測地線で 5 km 広げ（`buffer`）、その中にある地点を数える（`pointsWithin`）。移動が終わるたびに計算する。

共通のスタイル・データ・解析・コントロールと見た目（`app.css`）は [shared/](shared/) にあり、3 つの例が同じものを使う。HTML と Web Component の例は `shell.js`（画面の枠）と `app.js`（動き）を使い、地図の作り方とイベントの受け方だけが違う。React の例は同じコントローラと同じ構造を JSX で描く。新しい機能は 3 つの例すべてに足す。

## 動かし方

```sh
npm --prefix bench ci                     # 初回だけ（bench の依存）
npm --prefix npm ci                       # 初回だけ（パッケージのビルドに使う esbuild と TypeScript）
npm --prefix bench run examples           # パッケージをビルド・npm pack して各例に入れ、:8080 で配信
```

`examples` は `bench/npm/prepare.mjs` を走らせる。npm パッケージをビルドして `npm pack` し、できた tarball を `html/` と `element/` の `node_modules/mbmap` に展開する。React の例では `examples/react` で `npm ci`（React と esbuild）をしてから tarball を入れ、`npm run build`（`build.mjs`）で `react/dist/` にバンドルし、Worker と wasm をその隣にコピーする。

http://127.0.0.1:8080/examples/ を開く。地図は国土地理院の配信タイル（ベクトルタイル z4〜16、標高タイル z1〜14、シームレス空中写真）を直接読む。
ネットワークなしで試すときや自動テストでは、`?local=1` でベンチ用のタイル（東京駅周辺の z14、`npm --prefix bench run fixtures` で取得）を読む。

どの例も静的なファイルだけで動く（URL は相対）。開発用の、MoonBit のビルドを直接読むページは `bench/pages/`（basic、terrain）に、パッケージの試験に使うページは `bench/npm/pages/` にある。
