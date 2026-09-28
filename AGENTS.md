## Agent skills

### Issue tracker

issue は GitHub の kubot64/filmsim で管理し、`gh` CLI で操作する。詳しくは `docs/agents/issue-tracker.md`。

### Triage labels

既定の 5 つのラベル（needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix）をそのまま使う。詳しくは `docs/agents/triage-labels.md`。

### Domain docs

single-context 構成で、リポジトリ直下に `CONTEXT.md` と `docs/adr/` を置く。詳しくは `docs/agents/domain.md`。

## ドキュメント

同じことを 2 か所に書かない。書く場所は中身の種類で決まる。

- **今のアプリの振る舞い**：`docs/SPEC.md`。使う人から見える振る舞いを変える PR では、同じ PR で SPEC.md も直す
- **後から変えにくい設計判断とその理由**：`docs/adr/`。判断を変えるときは、新しい ADR を足して古いものを置き換える
- **用語**：`CONTEXT.md`
- **測定と検証の記録**：`research/notes/`
- **未決事項と、これからやること**：GitHub の issue
- **キー名、関数名、パラメータの値など実装の細部**：コード（必要ならコメント）。ドキュメントには書かない
