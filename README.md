# filmsim

アプリ名は **Irocam**（ホーム画面に出る名前。ターゲット名とリポジトリ名は FilmSim / filmsim のまま）。

iPhone で撮った RAW を、富士フイルムの公式 F-Log2 用フィルムシミュレーション LUT を基準に
X100 系の色に仕上げる自分用アプリ。

- `research/` : Python で色変換パイプラインを組み、公開 RAF と撮って出し JPEG のペアで ΔE を検証する
- `ios/`      : Swift パッケージ `FilmSimCore`（変換ロジック）と、XcodeGen で生成する iOS アプリ `FilmSim`
- `docs/`     : 今のアプリの振る舞い（SPEC.md）と設計判断（adr/）。用語は直下の CONTEXT.md、測定の記録は `research/notes/`、未決事項とこれからやることは GitHub の issue に置く（AGENTS.md「ドキュメント」）

## セットアップ

```bash
# Python 側
cd research && uv sync && uv run pytest

# Swift パッケージ側（macOS でテスト可能）
# この Mac は xcode-select が CommandLineTools を指しているので Xcode のツールチェーンを明示する
cd ios/FilmSimCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# iOS アプリの Xcode プロジェクト生成
cd ios && xcodegen generate && open FilmSim.xcodeproj
```

## CI

GitHub Actions（`.github/workflows/ci.yml`）で push と PR ごとに 3 ジョブが走る。

| ジョブ | ランナー | 内容 |
|---|---|---|
| python | ubuntu | `uv sync --locked`、ruff（lint と整形の確認）、pytest（公式 LUT のサニティテスト含む） |
| swift-package | macos-15 | `swift format lint`（`.swift-format` の設定）と `ios/FilmSimCore` の `swift test` |
| ios-app | macos-15 | XcodeGen で生成してシミュレータ向けに署名なしビルド（Debug と Release）。Debug に .cube が入り、Release に富士の LUT が入らないことを確認 |

公式 LUT は `scripts/fetch_luts.sh` の SHA-256 をキーにキャッシュされる。Fujifilm が zip を差し替えるとチェックサム不一致で CI が赤になるので、内容を確認してスクリプトの `ZIP_SHA256` を更新する。
`main` は 3 ジョブが required なブランチ保護付き。ローカルで同じことを回すには `make ci`。lint だけなら `make lint`、整形を直すには `make fmt`。

## App Store に出す

App Store に出すのは Release 構成のビルド。富士の公式 LUT は再配布できないので Release には入れず、組み込みのルックはアメリカだけになる（[ADR 0010](docs/adr/0010-no-fujifilm-luts-in-app-store-build.md)）。入っていればビルドが失敗する。

1. `ios/project.yml` の `CURRENT_PROJECT_VERSION` を上げる（アップロードごと）。出す版が変わるなら `MARKETING_VERSION` も上げる
2. `make archive TEAM=<Team ID>` で `ios/build/Irocam.xcarchive` を作る（Team ID は Apple Developer の Membership にある 10 文字）
3. Xcode の Window → Organizer で、そのアーカイブを「Distribute App」→「App Store Connect」でアップロードする

App Store Connect に最初に登録するときに決めること：

| 項目 | 値 |
|---|---|
| Bundle ID | `com.morikubo.FilmSim`（`project.yml` の `bundleIdPrefix` とターゲット名から） |
| 名前 | Irocam |
| カテゴリ | 写真/ビデオ |
| プライバシーポリシーの URL | https://github.com/kubot64/filmsim/blob/main/docs/privacy.md |
| サポートの URL | https://github.com/kubot64/filmsim/issues |
| App のプライバシー | 「データを収集しない」（`ios/FilmSim/PrivacyInfo.xcprivacy` と同じ） |
| 輸出コンプライアンス | 申告不要（`ITSAppUsesNonExemptEncryption` = NO を Info.plist に入れてある） |
| 対応端末 | iPhone のみ。Bayer RAW が撮れない端末ではシャッターを押せないので、説明文に書いておく |
| スクリーンショット | 6.9 インチの iPhone の縦向き |

審査の注意：説明文や画面に、富士フイルムや Kodak の名前、フィルムシミュレーションの名前（Provia、Classic Chrome など）を出さない（商標。組み込みのルックの名前はそのために「ナチュラル」などにしてある）。公式 LUT を読み込めることは、「F-Log2 用の LUT を読み込める」と書く。

## 公式 LUT と検証データ

- 公式 LUT は `scripts/fetch_luts.sh` が取得して `research/luts/official/` と `ios/FilmSim/LUTs/` に置く（git 管理外）
  - Claude Code では `.claude/settings.json` の SessionStart フックで自動実行される。クラウド環境では `dl.fujifilm-x.com` への通信許可が必要
  - Provia / Classic Chrome を含む 10 種の F-Log2 用 LUT は GFX ETERNA 55 用パッケージにしか入っていない（X100VI 用は ETERNA 系のみ）
  - 配布元: https://www.fujifilm-x.com/global/support/download/lut/
- F-Log2 データシート: https://dl.fujifilm-x.com/technical-data/F-Log2_DataSheet_E_Ver.1.1.pdf
- 検証用 RAF + JPEG: `research/samples/README.md` を参照
