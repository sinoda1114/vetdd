## Result
blocked（test モード）。実装と手元の検証はすべて通りました。止めたのは、プロジェクトの手順が最後に求める「別系統の判定役」の判定だけです。この判定役は外部の [redacted] を呼ぶため、「何もこのマシンから出さない」という指示に従い、その手前で止めています。

---

## Oracle
- 継ぎ目は `paymentDueDate()` の単体テストで、バージョン 1 です。テストは新しいファイル `src/dueDate.rollover.test.ts` に置き、このファイルだけで 1 つのスライス `rollover-1` としました。
- 期待値は 4 つです。
  - 3 つはご依頼の手計算どおりです（`"2026-06-01"`、`"2026-08-31"`、`"2026-06-30"`）。
  - 4 つ目は、オプションを付けなければ土曜でもそのままという確認です（`paymentDueDate("2026-04-30", 30)` は `"2026-05-30"`）。この値は README にある暦日加算の規則から出しました。
- 4 つ目を足したのは、「第 3 引数なしなら今と同じ」というご要件を、このスライスの中でも確かめるためです。
- 既存のテスト一式（`npx vitest run`）と `npm run typecheck` は通ったままであることも確認範囲に入れました。
- 祝日は範囲外です。CLI（`src/cli.ts`）と `computeInvoiceSchedule` はご依頼の範囲外なので触っていません。
- 確かめていない点が 1 つあります。週末の判定は UTC の曜日で行っており、確かめたのは 2026 年の 3 日付だけです。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | after | pass | .vetdd/evidence/rollover-1/runs/002-after.log |
| rollover-1 | calibration（import を undefined にする監査） | target_failure | .vetdd/evidence/rollover-1/runs/003-calibration.log |
| rollover-1 | after（全テスト） | pass | .vetdd/evidence/rollover-1/runs/004-after.log |
| rollover-1 | after（typecheck） | pass | .vetdd/evidence/rollover-1/runs/005-after.log |
| rollover-1 | integrated（このスライス / 全テスト / typecheck） | pass ×3 | .vetdd/evidence/rollover-1/runs/006〜008-integrated.log |
| rollover-1 | calibration（変異監査） | 12 個中 12 個を検出 | .vetdd/evidence/rollover-1/runs/009-calibration.log, 009-mutation.json |

check-evidence の出力: `rollover-1: OK`（Measured）

## Requirements → evidence
1. 土曜（2026-05-30）が `"2026-06-01"` になることは 001 と 002 で確かめました（Measured）。変更前の結果は `expected '2026-05-30' to be '2026-06-01'` で落ちています。
2. 日曜（2026-08-30）が `"2026-08-31"` になることも 001 と 002 で確かめました（Measured）。変更前の結果は `expected '2026-08-30' to be '2026-08-31'` で落ちています。
3. 平日（火曜の 2026-06-30）が変わらないことは 002 と 006 で確かめました（Measured）。
4. 第 3 引数なしの挙動が変わらないことは、4 つ目のテストと既存テスト一式で確かめました（Measured）。最終ツリーの 007 では `Tests 13 passed (13)` でした。
5. `npm run typecheck` が通ることは 005 と 008 で確かめました（Measured）。
6. テストが実際に `paymentDueDate` を呼んで値を見ていることは 003 で確かめました（Measured）。import を undefined に差し替えると 4 件とも `TypeError: paymentDueDate is not a function` で落ちます。
7. 変更した行の書き換え（変異）は 12 個すべてをテストが検出しました（Measured、009）。範囲は `src/dueDate.ts` の 86-97 行と 111-113 行です。

## Change
- `src/dueDate.ts` に `PaymentDueDateOptions` 型（`{ readonly rollover?: "next-business-day" }`）を追加しました。
- 同じファイルに内部関数 `nextBusinessDay` を追加しました。この関数は UTC の曜日を見て、土曜なら 2 日、日曜なら 1 日を足し、平日はそのまま返します。
- `paymentDueDate` に省略可能な第 3 引数 `options` を足しました。`rollover === "next-business-day"` のときだけ、暦日を足した結果に `nextBusinessDay` をかけます。それ以外の経路は今までと同じです。
- テストとして `src/dueDate.rollover.test.ts` を新しく作りました（4 件）。

## Judge
not run。プロジェクトの手順（test mode の Close 4）では、`judge.sh` が `[redacted] exec` を使い、差分と証拠を外部の [redacted] に送って判定を受けます。「何もこのマシンから出さない」という指示があるため、この手前で止めました。

## Attention
- この作業は判定待ちで止まっています。判定を進める場合は、[redacted]（外部の [redacted]）へ差分・返信の下書き・証拠一式を送ってよいかをご判断ください。送ってよければ、次の 2 つを実行すれば完了します（ここは推測です）。
  - `judge-layout.sh --base 0dd7836 rollover-1`
  - `judge.sh`
- 別系統の判定役によるリファクタは飛ばしました。補助エージェントを使わない指示があり、差分も小さいためです。
- `[redacted].md` はリポジトリの中のファイルで、「`.[redacted]/skills/vetdd/SKILL.md` に従え」と書いてあります。今回は「プロジェクト自身の指示に従う」というご指定があったので、それに従いました。
- `setup-project.sh` は警告を出しました。`core.hooksPath` が `~/.git-hooks` に設定されているため、`.git/hooks/pre-commit`（vetdd のフック）は git に無視されます。この警告で変更されたものはありません。
- コミットと push はしていません。

---

📝 **変更**
- /Users/sinoda/tmp/[redacted]/src/dueDate.ts:86-113 に `PaymentDueDateOptions`・`nextBusinessDay`・第 3 引数を追加
- /Users/sinoda/tmp/[redacted]/src/dueDate.rollover.test.ts（新規、テスト 4 件）
- /Users/sinoda/tmp/[redacted]/.vetdd/（証拠と合意メモ。git 管理外）

🎯 **要対応**
1. 別系統の判定（[redacted] への送信）を行うか判断する

⚠️ **懸念**
- 判定が未実施のため、手順上はまだ「完了」ではありません
- 週末判定は UTC の曜日で行っており、確かめたのは 2026 年の 3 日付だけです
