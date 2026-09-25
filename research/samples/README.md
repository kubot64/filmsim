# 検証用サンプル

実機がないので、公開されている RAF と撮って出し JPEG のペアで検証する。

- DPReview のサンプルギャラリー（X100VI, X-T5 など）には RAF と JPEG が同じショットで揃っている
- ファイル名を揃えて置く: `DSCF0001.RAF` と `DSCF0001.JPG`
- JPEG 側のフィルムシミュレーションは EXIF の MakerNote に入っている。exiftool で確認:
  `exiftool -FilmMode -Saturation -HighlightTone -ShadowTone -WhiteBalanceFineTune DSCF0001.JPG`
- Provia で撮られたペアを最初に集める。Classic Chrome はその次

このディレクトリの中身は git 管理外。

## iPhone の DNG（露出アンカー、#6）

- FilmSim で撮った DNG を写真アプリから AirDrop で Mac に送り、`samples/iphone/` に置く
- `uv run python scripts/iphone_anchor.py samples/iphone/*.DNG --ev 0 -0.35 --libraw` で、中央の明るさ、無地の面から出したアンカー、白飛びまでの段数を出し、`out/iphone_anchor/sheet.jpg` に候補の EV ごとの現像を並べる
- 線形化は CIRAWFilter（`scripts/ci_linear.swift`）なので macOS でしか動かない。LibRaw は iPhone の DNG の周辺減光の補正を掛けないので、周辺の明るさは比べられない
- アンカーの値を直接出せるのは、画面いっぱいの無地の面（白い壁など）だけ。明暗差のある場面は、並べた現像を見て判断する
