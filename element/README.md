# element/

Web Component `<mb-map>` のソース（`element.ts`）。npm パッケージの `mbmap/element` として配布する（ビルドは `npm/scripts/build.mjs`）。

- 地図は Shadow DOM の中にあるので、仮想 DOM 系のフレームワークからは「中身を触らない1要素」に見える。
- 属性は厳密に解釈する。不正な値は受け付けず、`mb-error` を出して前の値を保つ。
- `center` と `zoom` のプロパティは、値（`{lng, lat}` や数値）と、属性と同じ形の文字列のどちらでも受け付ける。React 19 は、要素に同じ名前のプロパティがあると、props をプロパティとして設定するため。
- `main` の入口（`./index.js`）を import する。`Map` を二重にバンドルしない。
