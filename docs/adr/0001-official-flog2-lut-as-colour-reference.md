# 富士フイルムの公式 F-Log2 用 LUT を色の正解にする

狙う見た目は X100 系のフィルムシミュレーションだが、富士のカメラを持っていないので、RAW と撮って出し JPEG のペアを自分では撮れない。そこで、富士フイルムが配布している F-Log2 → フィルムシミュレーションの 3D LUT（.cube、65 grid）を色の正解とし、iPhone の線形の色をいったん F-Log2 のコード値に符号化してから、その LUT を引く。

入力側の符号化は F-Log2 データシート Ver.1.1 の式に従い、F-Gamut の原色は BT.2020 と同じ、白は D65 とする。LUT が正解として妥当かは、公開されている RAF と撮って出し JPEG のペアを LibRaw で同じパイプラインに通し、ΔE2000 で確かめる。

X100 系を選んだのは、公式 LUT が基準に使え、参考になる作例も多いため。LUT と撮って出しのずれは、LUT の後ろに足す補正で詰める（[0004](0004-x-series-corrections-only-on-fujifilm-luts.md)）。

## Consequences

- Provia と Classic Chrome を含む 10 種は GFX ETERNA 55 用パッケージにしか入っていない（X100VI 用は ETERNA 系だけ）。LUT は GFX 用なので、X シリーズの撮って出しとのずれは残る
- 公式 LUT は再配布できないので、リポジトリにはコミットせず `scripts/fetch_luts.sh` で取得する。配布版では使う人が各自読み込む形にできる（[0007](0007-detect-imported-lut-input-log.md)）
- 露出アンカー（線形の 18% グレーを F-Log2 の 0.391 に置くゲイン）を決める必要が生じる（#6）
