`scripts/fetch_luts.sh` がここに公式 LUT を置く。

- `FLog2_to_PROVIA_65grid_V.1.00.cube`
- `FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube`

ファイル名は `FilmSimCore/Recipe.swift` の `lutFileName` と一致させること。
.cube は git 管理外。XcodeGen がこのフォルダをアプリのリソースとして取り込む。
