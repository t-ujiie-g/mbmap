# bench/fixtures

## gsi-bvmap/

国土地理院ベクトルタイル提供実験（`experimental_bvmap`）の z14、東京駅周辺 7×5 = 35 タイル
（x 14549–14555, y 6449–6453、合計約 13MB）。

- 出典：国土地理院ベクトルタイル提供実験 <https://maps.gsi.go.jp/development/vt.html>
- 利用規約：国土地理院コンテンツ利用規約
- サイズが大きいのでリポジトリにはコミットしない。`npm --prefix bench run fixtures` で取得し、
  `gsi-bvmap.manifest.json` の sha256 と照合する。上流が更新されて不一致になった場合は警告して
  非ゼロ終了する（ベンチ結果が比較不能になるため）。意図的に更新するときは
  `node bench/maplibre/fetch-tiles.mjs --update`。

## gsi-dem/、gsi-dem-fuji/

国土地理院の標高タイル（`dem_png`）。`gsi-dem/` は z14 の東京駅周辺 7×5 タイル（ベクトルタイルと同じ範囲、約 1.3MB）、
`gsi-dem-fuji/` は z12 の富士山周辺 4×4 タイル（x 3625–3628, y 1616–1619、約 1.8MB）。

- 出典：国土地理院 標高タイル <https://maps.gsi.go.jp/development/ichiran.html#dem>
- 利用規約：国土地理院コンテンツ利用規約
- 取得と照合は gsi-bvmap と同じ（`npm --prefix bench run fixtures`、マニフェストは `gsi-dem*.manifest.json`）。
