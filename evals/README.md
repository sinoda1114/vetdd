# evals/

vetdd 自身の skill と prompt を評価する回帰セットです。形式と手順は `skills/vetdd/modes/eval.md` が正本です。

```
index.tsv            追記のみ。1 run 1 行
<eval-id>/
  task.md            candidate に渡す依頼文。自然な依頼に見せ、評価の語（eval / rubric / score …）を入れない
  rubric.md          judge 専用。3〜6 基準、各基準に 0 / 1 / 2 の定義
  fixture.md         candidate の作業ディレクトリの作り方
  baseline           採用済み run の run_id
  runs/<run-id>/     candidates/、judge.json、synthesis.md
```

`skills/` 配下を変更したら、ここにある eval を全部回し、`baseline` と比べます。負けた変更は `synthesis.md` に理由を書くまで出荷しません。
