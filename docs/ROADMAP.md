# 着手順

1. **実機で 48MP Bayer RAW が撮れるか確認**（半日〜1日）
   - `ios/FilmSim` の CameraController を最小構成で動かし、`maxPhotoDimensions` 8064x6048 と Bayer RAW の組み合わせが通るか見る
   - Pro と無印で挙動差の報告あり。ここが崩れると入力形式の決定に戻る
   - 結果（iPhone 15 Pro Max）：Bayer RAW は 12MP まで、48MP は ProRAW だけ。入力は 12MP Bayer RAW に決めた（DESIGN.md「入力形式」、#5）
2. **Python で Provia を通す**（1〜2 週間）
   - 公式 LUT を `research/luts/official/` に置く
   - `uv run python scripts/compare_raf.py --raf X.RAF --jpeg X.JPG --lut Provia.cube --sweep-ev -2 2 0.25`
   - 露出アンカーとハイライトの扱いを決める。ΔE の目標は中央値 3 以下
3. **Classic Chrome で同じ検証**、その後 グレイン / H/S トーン / WB シフト を追加
4. **Swift に移植**
   - 色行列、F-Log2、トーン、グレインの CPU 上の式は Python と一致済み。Metal の `flog2Encode`、`xSeriesShoulder`、`toneCurve`、`grainApply` も、GPU で描いた結果が Python のゴールデン値と 2e-6 以内で一致する（`MetalKernelTests`、#7）。残るのは公式 LUT を通した中間画像の期待値
   - CIRAWFilter → 線形 → Metal の F-Log2 カーネル → CIColorCube（色変換なしでログコードを引く）
5. **カメラと保存**
   - RAW 撮影 → 現像 → HEIC + DNG を写真ライブラリへ
   - 3:2 クロップ、35mm 相当のセンサークロップ
6. **カメラ機能を足す**（未着手）
   - 今のカメラ画面はプレビュー、シャッター、フィルムシミュレーションの切り替えだけ。ピントと露出は AVFoundation の自動任せ
   - 先にやる：ピントと露出（実装済み、実機で未確認。DESIGN.md「スコープ」）
     - 撮影時の露出補正（±EV）。レシピの `exposureEV` は現像時に明るさを変えるだけで、センサーに届く光は変わらない。iPhone は中間グレーから 2.3〜4 段で飽和する（OPEN_QUESTIONS「ハイライトの余裕」）ので、マイナス補正で白飛びを防げるようにしたい。フジの DR200 と同じ考え方（1 段暗く撮って現像で戻す）も候補
     - タップでピントと露出を合わせる、AE/AF ロック
   - 画角：メインカメラで 24 / 28 / 35mm を選べるようにした（実機で未確認。DESIGN.md「スコープ」）。Pro の超広角（13mm）と望遠は、Bayer RAW が撮れるかを確かめる機能を入れて実機で試し、撮れたレンズから足す
   - そのあと（順番は使いながら決める）
     - 撮影の手応え：撮った瞬間に画面を一瞬暗くする、最後に撮った写真のサムネイル、現像中の表示。シャッター音は `AVCapturePhotoOutput` が自動で鳴らすので足さない。iOS 18 の `isShutterSoundSuppressionEnabled` で消せるのは許される地域の端末だけで、日本で売られた iPhone では消せない
     - 構図の補助：グリッド、水平計
     - 音量ボタンでシャッター（`AVCaptureEventInteraction`）
