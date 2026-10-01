# 色の変換は研究側の Python を正とし、Swift はその写しにする

色の変換（F-Log2、ガマット、LUT、肩、暖色の色相、トーン、グレイン）は `research/filmsim/` と `ios/FilmSimCore/` の両方にある。正は研究側で、Swift と Metal は同じ結果を出す写しとして扱う。式や定数を変えるときは Python から変え、ΔE で確かめてから、同じ PR で Swift に写す。

研究側を正にするのは、色の正しさを判定できるのが研究側だけだから。撮って出し JPEG と比べる ΔE の計測（[0001](0001-official-flog2-lut-as-colour-reference.md)）、交差検証（[0004](0004-x-series-corrections-only-on-fujifilm-luts.md)）、LUT の焼き出しと当てはめは、すべて numpy と colour-science の上にある。Swift にはこれがなく、Swift で先に変えると「iPhone で見て良さそう」以上の根拠が持てない。

写しであることは、テストで保証する。Python のテストが Swift の定数を固定し、Swift のテストが Python のゴールデン値を固定する。Metal のカーネルも `MetalKernelTests` で同じゴールデン値と比べる。焼いた LUT は研究側が作って commit し、モデルが変わったら研究側のテストが古さを検出する。

## Considered Options

- **Swift を正にして、研究側を捨てる**：ΔE の検証と当てはめを Swift に移す必要があり、colour-science 相当のものを自分で持つことになる
- **共通のコードを 1 つにする**：Python と Core Image / Metal の間で共有できる形がない。LUT に焼いて渡す手はあるが、肩やグレインのようにパラメータで動く処理は焼けない

## Consequences

- Swift の各ファイルの先頭に、写し元の Python のモジュールか関数名を書く
- 式や定数を変える PR は、Python と Swift の両方を含む。片方だけの変更は、写しが崩れているので受け入れない
- Swift だけで必要になる処理（プレビューの幾何、ピント、持つ向き）はこの ADR の対象外。研究側に写しは要らない
- 書き方の細部は [docs/agents/coding.md](../agents/coding.md)
