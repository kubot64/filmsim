# 検証用サンプル

実機がないので、公開されている RAF と撮って出し JPEG のペアで検証する。

- DPReview のサンプルギャラリー（X100VI, X-T5 など）には RAF と JPEG が同じショットで揃っている
- ファイル名を揃えて置く: `DSCF0001.RAF` と `DSCF0001.JPG`
- JPEG 側のフィルムシミュレーションは EXIF の MakerNote に入っている。exiftool で確認:
  `exiftool -FilmMode -Saturation -HighlightTone -ShadowTone -WhiteBalanceFineTune DSCF0001.JPG`
- Provia で撮られたペアを最初に集める。Classic Chrome はその次

このディレクトリの中身は git 管理外。
