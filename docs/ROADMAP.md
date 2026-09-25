# 着手順

1. **実機で 48MP Bayer RAW が撮れるか確認**（半日〜1日）
   - `ios/FilmSim` の CameraController を最小構成で動かし、`maxPhotoDimensions` 8064x6048 と Bayer RAW の組み合わせが通るか見る
   - Pro と無印で挙動差の報告あり。ここが崩れると入力形式の決定に戻る
2. **Python で Provia を通す**（1〜2 週間）
   - 公式 LUT を `research/luts/official/` に置く
   - `uv run python scripts/compare_raf.py --raf X.RAF --jpeg X.JPG --lut Provia.cube --sweep-ev -2 2 0.25`
   - 露出アンカーとハイライトの扱いを決める。ΔE の目標は中央値 3 以下
3. **Classic Chrome で同じ検証**、その後 グレイン / H/S トーン / WB シフト を追加
4. **Swift に移植**
   - `FilmSimCore` の各ステップに Python の中間画像を期待値として持ち込む
   - CIRAWFilter → 線形 → Metal の F-Log2 カーネル → CIColorCubeWithColorSpace
5. **カメラと保存**
   - RAW 撮影 → 現像 → HEIC + DNG を写真ライブラリへ
   - 3:2 クロップ、35mm 相当のセンサークロップ
