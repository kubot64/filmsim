`scripts/fetch_luts.sh` がここに公式 LUT を置く。

- `FLog2_to_PROVIA_65grid_V.1.00.cube`
- `FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube`

- `Portra400VC_33grid.cube`：Kodak の技術資料から `research/scripts/bake_negative.py` で焼いたもの。公式 LUT と違いこれだけは git で管理する（`.gitignore` の例外）

ファイル名は `FilmSimCore/Recipe.swift` の `lutFileName` と一致させること。
公式の .cube は git 管理外。XcodeGen がこのフォルダをアプリのリソースとして取り込む。
