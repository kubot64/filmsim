# 公式 LUT の置き場

`scripts/fetch_luts.sh` を実行すると、GFX ETERNA 55 用パッケージから次の 2 本がここに入る。

- `FLog2_to_PROVIA_65grid_V.1.00.cube`
- `FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube`

- 入力は F-Log2 / F-Gamut、出力は BT.709 ガンマ
- 65 grid を使う（33 grid も同梱されているが精度で劣る）
- `.cube` は再配布しないので git 管理外（.gitignore 済み）
- ヘッダの `#model:` は GFX ETERNA 55。機種固有の微調整が入っている可能性は ΔE 検証で確認する（docs/OPEN_QUESTIONS.md）
