# App Store 版には富士フイルムの公式 LUT を入れない

Irocam を App Store に出す。今の組み込みのルックのうち「ナチュラル」（Provia）と「ネガフィルム」（Classic Chrome）は、富士フイルムが配布する公式 F-Log2 用 LUT をアプリに同梱したものだが、公式 LUT は再配布できない（[0001](0001-official-flog2-lut-as-colour-reference.md)）。App Store で配るのは再配布に当たるので、App Store に出すビルドには入れない。

App Store に出すのは Release 構成のビルドで、`EXCLUDED_SOURCE_FILE_NAMES` で `FLog2_to_*.cube` を外す。外し忘れても出せないように、Release のビルドに富士の LUT が入っていたらビルドを失敗させ、CI でも Release をビルドして確かめる。手元で動かす Debug 構成には今までどおり入れる。

アプリは、組み込みのルックのうち LUT がバンドルにあるものだけを出す（構成ではなくバンドルの中身で決めるので、どちらの構成でも同じコードで動く）。LUT がないルックの調整なしのレシピは消し、ほかのレシピはあるルックに移して調整を残す。

公式 LUT を使いたい人は、富士フイルムのサイトから取って読み込む（[0007](0007-detect-imported-lut-input-log.md)）。名前が `FLog2_to_` で始まるので、ハイライトの肩と Provia の暖色の色相も、組み込みのときと同じく掛かる（[0004](0004-x-series-corrections-only-on-fujifilm-luts.md)）。

## Consequences

- App Store 版の組み込みのルックは「アメリカ」（Portra 400VC、Kodak の技術資料から自分で焼いたもの）だけになる
- 公式 LUT の代わりに、それに似せた LUT を自分で焼いて入れることはしない。公式 LUT から作ったものは、やはり再配布に当たりうるため
- 組み込みの Provia / Classic Chrome を使っていたレシピを持つ人は、App Store 版ではいない（新しく入れるので）。それでも、Debug 版の記録を持ち込んだ場合に備え、レシピはあるルックに移す
