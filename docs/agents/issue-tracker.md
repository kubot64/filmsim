# issue の置き場所：GitHub

このリポジトリの issue と仕様は GitHub の issue に置く。操作はすべて `gh` CLI で行う。

## 決まった操作

- **issue を作る**：`gh issue create --title "..." --body "..."`。複数行の本文はヒアドキュメントで渡す
- **issue を読む**：`gh issue view <番号> --comments`。コメントは `jq` で絞り、ラベルもあわせて取る
- **issue の一覧**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`。必要に応じて `--label` と `--state` で絞る
- **コメントする**：`gh issue comment <番号> --body "..."`
- **ラベルを付ける・外す**：`gh issue edit <番号> --add-label "..."` / `--remove-label "..."`
- **閉じる**：`gh issue close <番号> --comment "..."`

リポジトリは `git remote -v` から決まる。クローンの中で実行すれば `gh` が自動で判断する。

## プルリクエストをトリアージの対象にするか

**PR を要望として扱う：しない。**（外部からの PR を機能の要望として扱うリポジトリなら `yes` にする。`/triage` がこの値を読む）

`yes` にすると、PR も issue と同じラベルと状態で扱い、`gh pr` の同じ操作を使う。

- **PR を読む**：`gh pr view <番号> --comments`。差分は `gh pr diff <番号>`
- **トリアージする外部の PR の一覧**：`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` を取り、`authorAssociation` が `CONTRIBUTOR`、`FIRST_TIME_CONTRIBUTOR`、`NONE` のものだけを残す（`OWNER`、`MEMBER`、`COLLABORATOR` は外す）
- **コメント、ラベル、閉じる**：`gh pr comment`、`gh pr edit --add-label` / `--remove-label`、`gh pr close`

GitHub では issue と PR が同じ番号の並びを使うので、`#42` だけではどちらかわからない。`gh pr view 42` で確かめ、PR でなければ `gh issue view 42` を使う。

## スキルが「issue に登録する」と言ったとき

GitHub の issue を作る。

## スキルが「関係する ticket を取ってくる」と言ったとき

`gh issue view <番号> --comments` を実行する。

## wayfinder の操作

`/wayfinder` が使う。**マップ**は 1 つの issue で、その**子**の issue が ticket になる。

- **マップ**：`wayfinder:map` のラベルを付けた 1 つの issue。本文に Notes / Decisions-so-far / Fog を持つ。`gh issue create --label wayfinder:map`
- **子の ticket**：マップに GitHub の sub-issue としてつないだ issue（sub-issues のエンドポイントに `gh api` で登録する）。sub-issue が使えない場合は、マップの本文のタスクリストに子を足し、子の本文の先頭に `Part of #<マップ>` と書く。ラベルは `wayfinder:<種類>`（`research` / `prototype` / `grilling` / `task`）。着手したら、その作業を進める開発者に割り当てる
- **ブロック**：GitHub の**標準の issue 依存関係**を使う。UI でも見える正式な表し方。`gh api --method POST repos/<owner>/<repo>/issues/<子>/dependencies/blocked_by -F issue_id=<ブロックする側の database id>` で追加する。`<ブロックする側の database id>` は数値の **database id**（`gh api repos/<owner>/<repo>/issues/<n> --jq .id`）で、`#番号` や `node_id` ではない。GitHub は `issue_dependencies_summary.blocked_by`（開いているブロック元の数。実際の判定に使う）を返す。依存関係が使えない場合は、子の本文の先頭に `Blocked by: #<n>, #<n>` と書く。ブロック元がすべて閉じたら、その ticket はブロックが解ける
- **次に着手できるものの一覧**：マップの開いている子を取り（`gh issue list --state open` を、マップの sub-issue かタスクリストに絞る）、開いているブロック元がある（`issue_dependencies_summary.blocked_by > 0`、または `Blocked by` の行に開いている issue がある）ものと、担当者がいるものを外す。マップの順で最初のものを選ぶ
- **着手する**：`gh issue edit <n> --add-assignee @me`。セッションで最初に行う書き込み
- **片付ける**：`gh issue comment <n> --body "<答え>"`、続けて `gh issue close <n>`。そのあと、マップの Decisions-so-far に文脈への手がかり（要点とリンク）を足す
