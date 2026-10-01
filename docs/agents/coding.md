# コードの書き方

このリポジトリでコードを書くときの約束。すでにコードが守っていることを書き出したもので、なぜそうかは ADR と各ファイルの先頭コメントにある。振る舞いは `docs/SPEC.md`、用語は `CONTEXT.md`、置き場所の方針は `AGENTS.md`。

## 研究側とアプリ側を同期する

色の変換は `research/filmsim/`（Python）と `ios/FilmSimCore/`（Swift）に同じ構成で 2 回ある。研究側が正で、Swift はその写し（[ADR 0009](../adr/0009-research-pipeline-is-the-reference.md)）。

- 変換の式や定数を変えるときは、まず Python で変えて ΔE で確かめ、同じ PR で Swift（必要なら `ios/FilmSim/Shaders/FilmSim.metal`）も直す。片方だけの PR にしない
- Swift の各ファイルの先頭コメントに、写し元の Python のモジュールか関数名を書く（例：`Same as x_series_shoulder in research/filmsim/tone.py`）
- 定数は出典をコメントに書く。データシートの値はそのまま写し、丸めない
- 焼いた LUT（`ios/FilmSim/LUTs/Portra400VC_65grid.cube`）は研究側のスクリプトで作って commit する。公式 LUT は `scripts/fetch_luts.sh` が取るので commit しない。手で編集しない。モデルを変えたら焼き直す（研究側のテストが古いことを検出する）
- 両側の対応を保証するテストを置く。Python のテストが Swift の定数を固定し（`test_grain.py` の `matches_swift_constants` のように）、Swift のテストが Python のゴールデン値を固定する

## FilmSimCore とアプリの境界

- **`FilmSimCore`**：Foundation、CoreImage、simd のようなシステムのフレームワークだけに依存し、UI や OS のサービス（カメラ、写真ライブラリ）は呼ばない。macOS の `swift test` で回る。色の変換、レシピ、記録のような、画面のない処理はここに置く
- **`FilmSim`（アプリ）**：SwiftUI、AVFoundation、Photos、Metal。Core Image のカーネル（`.metal`）は `-fcikernel` が要るのでアプリ側に置き、Core はロードしたカーネルを受け取る
- 新しい処理は、まず Core に純粋な関数か値型として置き、テストを付けてからアプリで使う。アプリ側に残すのは、画面の状態と OS の API を呼ぶ部分だけ
- アプリ側の失敗は、使う人に見せる文言（`SPEC.md` の「知らせ」）に変えて 1 か所で出す。Core は `throw` で返し、文言を持たない

## テスト

- 変換の関数には、例の値だけでなく性質のテストを足す。往復（decode(encode(x)) == x）、単調性、継ぎ目の連続性、エネルギーの保存など。`InvariantTests.swift` が手本
- 乱数を使うテストはシードを固定し、失敗メッセージに入力値を入れる（`"x=\(x)"`）。再現できない失敗を作らない
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
- 整形と命名の細則は決めない。既存のファイルに合わせる
