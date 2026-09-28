# 富士以外のルックも「F-Log2 → 表示」の 3D LUT として作る

Leica Standard や Kodak Portra 400VC のような富士以外のルックも、富士の公式 LUT と同じ「F-Log2 のコード値 → 表示のコード値」の 3D LUT（65 grid）として作る。入力の側（線形 → F-Log2）は変えないので、アプリのパイプラインはそのまま使え、ルックを足すのは LUT を 1 本足すだけで済む。

ルックごとに LUT の作り方は違う。

- **Leica Standard**：公式の LUT はないが、DNG と撮って出し JPEG のペアはある。ペアから LUT を最小二乗で当てはめる（#76）
- **Portra 400VC**：ネガフィルムなので RAW と JPEG のペアがない。Kodak の技術資料から特性曲線と分光データを読み取り、ネガとプリントを計算で通して LUT に焼く（[portra400vc.md](../../research/notes/portra400vc.md)）

## Consequences

- ルックごとの計算（ネガとプリントのモデルなど）は Python で LUT に焼くところまでで、アプリには持ち込まない
- 当てはめた LUT は、当てはめたときの露出の置き方を前提にする。アプリの露出アンカーとそろえる必要がある（#76）
- 富士専用の補正は掛けない（[0004](0004-x-series-corrections-only-on-fujifilm-luts.md)）
