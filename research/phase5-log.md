# Phase 5 実施記録（2026-09-26）

## 成果物（`feat/verify`、`feat/eval` から分岐）

- `modes/verify.md`（生成 A / 判定器として使う B / 保守 C の 3 手順）
- `references/verify-skill-template.md`、`references/feature-map-template.md`
- 実例: `fixtures/ts-kata/.claude/skills/verify-ts-kata/`（SKILL.md、features 3 本、scripts 5 本）

## 判定器: 生成した verify skill を 1 周（verify.md 手順 A.4）

| 手順 | 結果（Measured） |
|---|---|
| doctor | ok（node v24.16.0） |
| 校正 red（`verify-due.sh --expect "closing: 2026-02-01"`） | target_failure（actual `closing: 2026-01-31`） |
| 校正 green（`verify-due.sh`） | pass |
| usage feature（after） | pass（exit 2、usage 行あり） |
| cleanup | 実行、artifacts は残存（3 件） |
| `check-evidence.sh ts-kata-verify` | OK |

evidence は `.vetdd/evidence/ts-kata-verify/`、artifacts は `.vetdd/artifacts/{due,usage}/`（いずれも gitignore、ローカル証拠）。

## 設計上の判断

- verify script は `--expect` で期待値を上書きできる形にし、校正 red を「わざと間違った期待値」で取れるようにした（対象を壊さずに済む）
- exit code の意味を 0 = 観測して一致 / 1 = 観測して不一致 / 2 = 観測できず に固定。2 は `infrastructure_error`
- artifacts は git root の `.vetdd/artifacts/` に置く。evidence（`.vetdd/evidence/`）と同じ場所に揃え、fixture 側に新しい gitignore 項目を増やさない
- fixture の due feature は 1 月の日付にした。2 月の月末締めは fixture の意図的なバグ（教材）なので、合意済み baseline に含めない

## 申し送り

- 判定（judge）は codex 障害のため未実行（Phase 4 と同じ）
- verify モードの B 手順（変更の判定器として使う）は、fixture の設定変更などで一度通す必要がある。Phase 6 か Phase 7 で `.npmrc` の値変更を題材に実施
- 既存の `.claude/skills/verify-ts-kata` が Skill tool に自動検出された（セッション内で "New skills discovered"）。プロジェクトローカル skill として意図どおり動く
