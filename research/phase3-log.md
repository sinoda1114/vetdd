# Phase 3 実施記録（2026-09-26）

## 成果物

`skills/vetdd/`: `SKILL.md`（入口）、`modes/test.md`、`parallel/select.md`、`references/{test-quality, feedback-loop-ladder, seam-proposal, subagent-brief, reply-format}.md`、`scripts/models.sh`。`modes/verify.md` と `modes/eval.md` は仮置き（Phase 5・4）。`~/.claude/skills/vetdd` に導入済み。

## 判定器: fixture のバグ (a) を `/vetdd` で修正

対象は fixture の複製（scratchpad の独立 git リポジトリ。fixture 本体のバグは教材なので残す）。私がエージェント役、篠田さんが人間役。

| 項目 | 結果（Measured） |
|---|---|
| 合意 | AskUserQuestion 1 バッチ 4 問（受入基準 2 slice、seam = unit、期待値 = 暦、その他既定） |
| slice feb-end-1 | before target_failure（期待 02-28 / 実際 03-31）→ after pass ×3 |
| slice feb-end-2 | before target_failure（うるう年）→ after pass ×3 |
| slice feb-end-refactor | calibration ×2 target_failure → refactorer（別 opus）変更なしで after pass → 親の after pass |
| check-evidence | 3 slice とも OK |
| judge | not run（judge.sh 未実装） |

Phase 3 の完了条件（証拠が揃い check pass、refactor を別エージェントが実行）を満たした。

## ドッグフーディングで直したこと

1. **校正 red の取り方。** 「モジュールを退避」だと vitest が "no tests" で落ちるだけで、狙った欠陥で red になる証明にならない。修正を一時的に戻して取り直した。`modes/test.md` に「欠陥を再導入して校正する。対象を消す方法は不可」と明記
2. **1 修正が複数 slice を覆う場合。** slice 2 の before を修正前に取らないと二度と red にならない。全 slice のテストを先に書き、runner の名前フィルタ（vitest `-t`）で 1 slice ずつ記録する手順を `modes/test.md` に追加

## 気づき（後続フェーズへ）

- 維持判定器（npm test、typecheck）を各 slice の after として記録すると run が重複する。Phase 6 で「coverage slice」にまとめるか、`check-evidence.sh` が最終ツリーの integrated 1 本で代表させる形を検討
- refactorer の「変更なし」は正当な結果として機能した。空の refactor でも after を記録させる設計は維持
- 入口の合意 4 問は、小さなバグ修正でも 1 往復で済んだ。項目 4〜8 を 1 問にまとめる設計は妥当
- CLI 出力の確認は証拠ファイル外だった。Phase 5 の verify モードでこれを証拠化する
