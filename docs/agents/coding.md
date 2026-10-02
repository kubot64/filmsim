# コードの書き方

このリポジトリでコードを書くときの約束。すでにコードが守っていることを書き出したもので、なぜそうかは ADR と各ファイルの先頭コメントにある。振る舞いは `docs/SPEC.md`、用語は `CONTEXT.md`、置き場所の方針は `AGENTS.md`。

## 研究側とアプリ側を同期する

色の変換は `research/filmsim/`（Python）と `ios/FilmSimCore/`（Swift）に同じ構成で 2 回ある。研究側が正で、Swift はその写し（[ADR 0009](../adr/0009-research-pipeline-is-the-reference.md)）。

- 変換の式や定数を変えるときは、まず Python で変えて ΔE で確かめ、同じ PR で Swift（必要なら `ios/FilmSim/Shaders/FilmSim.metal`）も直す。片方だけの PR にしない
- Swift の各ファイルの先頭コメントに、写し元の Python のモジュールか関数名を書く（例：`Same as x_series_shoulder in research/filmsim/tone.py`）
- 定数は出典をコメントに書く。データシートの値はそのまま写し、丸めない
- 焼いた LUT（`ios/FilmSim/LUTs/Portra400VC_65grid.cube`）は研究側のスクリプトで作って commit する。公式 LUT は `scripts/fetch_luts.sh` が取るので commit しない。手で編集しない。モデルを変えたら焼き直す（研究側のテストが古いことを検出する）
- 両側にある画素ごとの変換は、フィクスチャで一致を確かめる。`research/filmsim/fixtures.py` がシード固定の乱数の入力と Python の出力を `research/tests/fixtures/transforms.json` に書き、Swift の CPU 版のテスト（`TransformFixtureTests`）と Metal のテスト（`MetalKernelTests`）が全件を比べる。変換を変えたら `make fixtures` で作り直して commit する（古いままだと研究側のテストが落ちる）。Swift のテストに Python の値を手で写さない
- フィクスチャに載らない定数（`unit_noise_gain` のように画素ごとの変換でないもの）は、Python のテストが Swift の定数を固定する（`test_grain.py` の `matches_swift_constants`）

## FilmSimCore とアプリの境界

- **`FilmSimCore`**：Foundation、CoreImage、simd のようなシステムのフレームワークだけに依存し、UI や OS のサービス（カメラ、写真ライブラリ）は呼ばない。macOS の `swift test` で回る。色の変換、レシピ、記録のような、画面のない処理はここに置く
- **`FilmSim`（アプリ）**：SwiftUI、AVFoundation、Photos、Metal。Core Image のカーネル（`.metal`）は `-fcikernel` が要るのでアプリ側に置き、Core はロードしたカーネルを受け取る
- 新しい処理は、まず Core に純粋な関数か値型として置き、テストを付けてからアプリで使う。アプリ側に残すのは、画面の状態と OS の API を呼ぶ部分だけ
- アプリ側の失敗は、使う人に見せる文言（`SPEC.md` の「知らせ」）に変えて 1 か所で出す。Core は `throw` で返し、文言を持たない

## テスト

- 変換の関数には、例の値だけでなく**性質のテスト**を足す。どの入力でも成り立つ規則（往復、単調性、恒等、継ぎ目の連続性、範囲に収まることなど）を、乱数の入力で確かめる。`InvariantTests.swift` が手本
- 操作を重ねると状態が変わる型（`RecipeBook` など）にも性質のテストを足す。乱数で選んだ操作の列のあとでも成り立つ規則（保存して読み戻しても同じ、読み込んだ LUT ごとにそれを使うレシピがある、など）を確かめ、失敗メッセージに操作の列を入れる
- 性質のテストには `INV-<モジュール>-<番号>`（例：`INV-FLOG2-1`）の ID を doc コメントに付け、issue や PR からはこの ID で指す。入力の範囲はアプリで選べる範囲にする
- 性質のテストは、わざと壊した実装（定数を 1 つずらすなど）で落ちることを確かめてから残す
- 性質が成り立たなかったら、振る舞いのバグとして別の issue にし、`XCTExpectFailure` に issue 番号を添えて残す。性質のテストを足す PR では直さない
- 乱数を使うテストは `SplitMix64` でシードを固定し、失敗メッセージに入力値を入れる（`"x=\(x)"`）。再現できない失敗を作らない
- 性質のテストは Swift 側に、依存を足さずに書く。Python と同じであることはフィクスチャで確かめる。研究側で新しい変換を作るときに必要になったら hypothesis を入れる
- 許容誤差には根拠を書く。GPU の float32 なら 1e-6 前後、CPU の double なら 1e-8 以下、データシートの 10bit 値なら ±1 コード。緩めたときはなぜかをコメントに残す
- 公式 LUT を要るテストは、LUT が無ければ skip にする（`scripts/fetch_luts.sh` が取れない環境でも他のテストは回す）
- 画面の振る舞いはテストしない。代わりに `SPEC.md` を直す

## 言葉

- コードのコメント、docstring、識別子は英語。コミット、PR、issue、`docs/` は日本語
- 画面に出す文言は `SPEC.md` と同じ言葉を使う（HEIC は「写真」、DNG は「RAW」、「明るさ」と「露出補正」は別物）
- 新しい型や関数の名前は `CONTEXT.md` の用語に合わせる。既存の名前が用語とずれているとき（`FilmSimulation` は組み込みのルック全体を指す）は、黙って直さず、`CONTEXT.md` の _Note_ か issue に残す
- ファイル名の `FilmSim` と `filmsim` はターゲット名とリポジトリ名。アプリ名の Irocam は画面とドキュメントにだけ出す

## コミットと PR

- コミットの 1 行目は、使う人から見える変化を日本語で書く。「〜を足す」「〜に替える」のように、何が変わったかで書き、どう実装したかは本文に回す（例：`ピントが合うたびに枠を一瞬緑にする`）
- 振る舞いを変える PR は、同じ PR で `SPEC.md` を直す。設計判断を変える PR は ADR を足す
- PR の本文に、何で確かめたかを書く。`make test`（Python と Swift のテスト）か `make ci`（iOS アプリのビルドまで）。実機でしか確かめられないこと（カメラ、写真ライブラリ）は、どの端末で何をしたかを書く
- 整形は道具に任せ、細則は決めない。Python は ruff（`research/pyproject.toml`）、Swift は Xcode 同梱の swift-format（`.swift-format`）。`make fmt` で直し、`make lint` で確かめる。CI も同じものを回す
- データシートの表のように並びに意味がある所は `# fmt: off` / `# fmt: on` で囲み、理由を 1 行添える
