# Claude Code on the web で開発する

claude.ai/code のクラウドのセッションで mbmap の開発を続けるための準備と使い方。作業の決まりは AGENTS.md（特に §2 と §9）、いまどこまで進んでいるかは PROGRESS.md の冒頭にある。

## 1. 環境を作る（最初に一度）

claude.ai/code で、このリポジトリ（t-ujiie-g/mbmap）の環境を作り、次のように設定する。

### ネットワーク

「Network access」を **Custom** にし、「Also include default list of common package managers」に印を付けたうえで、次のドメインを足す（Full でもよい）。

```
cli.moonbitlang.com
cyberjapandata.gsi.go.jp
tiles.openfreemap.org
raw.githubusercontent.com
build.protomaps.com
cdn.playwright.dev
playwright.download.prss.microsoft.com
services.arcgisonline.com
sampleserver6.arcgisonline.com
basemaps.arcgis.com
services.arcgis.com
demo.mapserver.org
demo.pygeoapi.io
gibs.earthdata.nasa.gov
assets.cms.plateau.reearth.io
api.plateauview.mlit.go.jp
```

- `cli.moonbitlang.com`：MoonBit のツールチェーン（`scripts/toolchain.env` で版と sha256 を固定）
- `cyberjapandata.gsi.go.jp`：ベンチと黄金テストのフィクスチャ（国土地理院のタイル。manifest の sha256 と照合する）
- `tiles.openfreemap.org`、`raw.githubusercontent.com`、`build.protomaps.com`：公開スタイルの比較（`npm run style:public`）に使うタイルとスプライト（manifest の sha256 と照合する）。Node の `fetch` はプロキシを読まないので `NODE_USE_ENV_PROXY=1` を付ける（`scripts/setup.sh` は付けている）
- `assets.cms.plateau.reearth.io`：PLATEAU の 3D Tiles のフィクスチャ（`plateau-chiyoda`、東京駅まわりの建物。manifest の sha256 と照合する）。`api.plateauview.mlit.go.jp`：PLATEAU のデータカタログ（フィクスチャを選び直すとき）
- Playwright の 2 つ：黄金テストと npm パッケージのテストで使う Chromium
- `services.arcgisonline.com` から `gibs.earthdata.nasa.gov` までの 7 つ：`mbmap/services` を公開されている GIS の Web サービスで確かめる黄金テスト（`npm run services:golden`）。応答は記録せず、毎回取りに行く

GitHub と npm は既定の一覧に入っている。

### セットアップ

次のどちらか（両方でもよい）。

**(a) 環境の「Setup script」**（作った結果がキャッシュされ、2 回目からのセッションが速い）

```bash
#!/bin/bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" && [ -x scripts/setup.sh ] && scripts/setup.sh || true
```

セットアップスクリプトが動く時点でリポジトリがどこにあるかは確かめていない。セッションの中で `moon version` が通らなければ (b) を使う。

**(b) リポジトリの SessionStart フック**（セッションを開くたびに動く。`scripts/setup.sh` は入っているものを飛ばすので、2 回目以降は npm ci と Playwright の確認だけ）

`.claude/settings.json` に次の `hooks` を足す（Claude 自身は自分の設定を書き換えられないので、手で足す）。

```json
{
  "enabledPlugins": {
    "moonbit-skills@moonbit-code-plugins": true
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "if [ \"$CLAUDE_CODE_REMOTE\" = \"true\" ]; then \"$CLAUDE_PROJECT_DIR\"/scripts/setup.sh > /tmp/mbmap-setup.log 2>&1 || echo 'scripts/setup.sh failed: see /tmp/mbmap-setup.log' >&2; fi",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

ローカル（`CLAUDE_CODE_REMOTE` が true でない）では何もしない。

## 2. セッションを始める

最初の指示の例：

> AGENTS.md と PROGRESS.md を読んで、「現在の状況」の次の段階を進めて下さい。

- セッションは、まず `moon version` と `ls bench/fixtures/gsi-bvmap | head` で準備ができているかを確かめる。なければ `scripts/setup.sh` を流す。
- 進め方はローカルと同じ（AGENTS.md §2）：段階ごとに PR を出し、CI が通ったら日本語で報告して止まる。「マージしました」で次へ。
- 並列に進めたいときは、作業ごとに別のセッションを開く（同じセッションの中の worktree のエージェントは、クラウドでは確かめていない）。

## 3. クラウドでできないこと

- **性能ベンチ**（`worker:browser`、`render`、`*:node` の時間）：数字は M2 の開発機で測ったものだけを PROGRESS に載せる（VISION §2、AGENTS.md §5）。クラウドのセッションは、測る必要があるときは報告にそう書く。ローカルのセッションでまとめて測る。
- **moonbit-skills プラグイン**：リポジトリの設定に書いてあっても、クラウドでは読み込まれない。API は `moon ide doc`、生成された `.mbti`、docs.moonbitlang.com で確かめる。
- **ローカルの自動メモリ**：クラウドには届かない。続けてほしい決まりは AGENTS.md §2 に書く。
- **GitHub の一部の操作**：プロキシが GraphQL を止めることがあり、そのときは `gh pr create` / `gh pr checks` が失敗する。REST（`gh api repos/t-ujiie-g/mbmap/pulls`、`.../commits/<sha>/check-runs`）を使う。ブランチの削除とタグの push はできない。

## 4. ツールチェーンを上げるとき

`scripts/toolchain.env` の `MOONBIT_VERSION` と 2 つの sha256 を書き換える。CI も Web の環境も同じファイルを読む。ローカルの `moon upgrade` で上がった版と合わせ、PROGRESS.md に版を記録する（AGENTS.md §8.1）。
