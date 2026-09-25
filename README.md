# filmsim

iPhone で撮った RAW を、富士フイルムの公式 F-Log2 用フィルムシミュレーション LUT を基準に
X100 系の色に仕上げる自分用アプリ。

- `research/` : Python で色変換パイプラインを組み、公開 RAF と撮って出し JPEG のペアで ΔE を検証する
- `ios/`      : Swift パッケージ `FilmSimCore`（変換ロジック）と、XcodeGen で生成する iOS アプリ `FilmSim`
- `docs/`     : 設計判断（DESIGN.md）、着手順（ROADMAP.md）、未決事項（OPEN_QUESTIONS.md）

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

## 公式 LUT と検証データ

- 公式 LUT: https://www.fujifilm-x.com/global/support/download/lut/ から取得し `research/luts/official/` に置く（再配布しないので git 管理外）
- F-Log2 データシート: https://dl.fujifilm-x.com/technical-data/F-Log2_DataSheet_E_Ver.1.1.pdf
- 検証用 RAF + JPEG: `research/samples/README.md` を参照
