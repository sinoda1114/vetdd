## Result
**blocked（test モード）**: 実装と手元での検証は完了し、証跡検査は `rollover-1: OK` です。止めたのは最後の 1 工程、別系統モデルによる最終判定だけです。プロジェクトの手順（`.[redacted]/skills/vetdd`）ではこの判定を外部の判定役（`judge.sh`）に送る必要がありますが、「外部サービスやレビュー役を呼ばない」という指示に従い、その手前で止めました。

---

## Oracle
- 継ぎ目は `paymentDueDate()` の単体テストで、オラクルの版は 1 です。テストは新規ファイル `src/dueDate.rollover.test.ts` に置きました。
- 期待値は依頼にあった手計算の 3 件です。`("2026-04-30",30,opt)→"2026-06-01"`、`("2026-07-31",30,opt)→"2026-08-31"`、`("2026-05-31",30,opt)→"2026-06-30"` です。
- 第 3 引数がない場合の変化なしを確かめるため、テストを 1 件足しました。`("2026-04-30",30)→"2026-05-30"` です。4 月は 30 日まであるので、手計算で 5/30 になります。
- 期待値の曜日は `cal` で独立に確かめました（Measured）。5/30 は土曜、8/30 は日曜、6/30 は火曜です。
- 範囲外は祝日です。見えていない点として、CLI（`src/cli.ts`）からはこのオプションを指定できません。依頼の範囲外なので触っていません。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | calibration（既知の正常ケース `-t keeps`） | pass | .vetdd/evidence/rollover-1/runs/001-calibration.log |
| rollover-1 | before | target_failure（土曜・日曜の 2 件が期待値の assertion で失敗、2 件 pass） | runs/002-before.log |
| rollover-1 | after（編集が反映されていない状態で走った失敗試行、accepted=false） | target_failure | runs/003-after.log |
| rollover-1 | after | pass（4/4） | runs/004-after.log |
| rollover-1 | calibration（未定義インポート監査） | target_failure（`TypeError: paymentDueDate is not a function`） | runs/005-calibration.log |
| rollover-1 | after（`npm test` 13/13、`npm run typecheck`） | pass | runs/006-after.log, runs/007-after.log |
| rollover-1 | integrated（スライスのテスト、`npm test`、`npm run typecheck`） | pass ×3 | runs/008〜010-integrated.log |
| rollover-1 | calibration（Stryker 変異監査、変更行のみ） | 11 killed / 0 survived / 0 no-cov | runs/011-calibration.log, runs/011-mutation.json |

check-evidence の出力:
```
rollover-1: OK
```

## Requirements → evidence
- 土曜は翌月曜に移る（2026-06-01）: runs/002-before.log が赤、runs/008-integrated.log が緑（Measured）
- 日曜は翌月曜に移る（2026-08-31）: 同上（Measured）
- 平日は動かない（2026-06-30）: runs/008-integrated.log（Measured）
- 第 3 引数なしでは従来どおり: runs/008-integrated.log の土曜ケースと、既存スイートを含む `npm test` 13/13 の runs/009-integrated.log（Measured）
- 既存の vitest と型検査は緑のまま: runs/009-integrated.log と runs/010-integrated.log（Measured）

## Change
`src/dueDate.ts` の `paymentDueDate` に、省略できる第 3 引数 `options: PaymentDueDateOptions = {}` を足しました。型は `{ readonly rollover?: "next-business-day" }` です。暦日を足した結果が土曜なら +2 日、日曜なら +1 日する内部関数 `nextBusinessDay` を追加しました。曜日は既存の UTC 計算と同じ方式で求めています。`rollover` を指定しないときは、以前と同じ式で同じ値を返します。テストは新規ファイル `src/dueDate.rollover.test.ts` に 4 件あります。commit と push はしていません。

## Judge
not run: 手順は `judge.sh` で差分・返信案・証跡を外部の判定役に送るよう求めます。依頼に「何もこのマシンから出さない」とあるので、ここで止めました。必要なローカルの証跡はすべて `.vetdd/evidence/rollover-1/` にそろっています。

## Attention
- 判定が済んでいないので、結果は blocked です。外部送信を許可していただければ、`judge-layout.sh` と `judge.sh` で判定だけを実行できます。
- 失敗試行が 1 件記録に残っています（run 3）。原因はテストの失敗ではなく、私の Edit がツールに拒否されたまま `after` を走らせたことです。手順どおり `stall.sh` を実行し、停滞なしを確認したうえで再実行しました（Measured）。
- リファクタ工程は飛ばしました。理由は「ヘルパー禁止」の指示と、数行の変更で整理する余地がないことの 2 つです。
- `setup-project.sh` が警告を出しました。`core.hooksPath` が `~/.git-hooks` に設定されているので、vetdd の pre-commit フックは git から呼ばれません。設定は変更していません。
- 手順書は AskUserQuestion での合意取りを求めます。合意は依頼文に書かれていた決定事項で代えて、`.vetdd/notes/rollover-1-initial.txt` に記録しました。

---

📝 **変更**
- /Users/sinoda/tmp/[redacted]/src/dueDate.ts:86-115 に `PaymentDueDateOptions` 型、`nextBusinessDay`、`paymentDueDate` の第 3 引数を追加
- /Users/sinoda/tmp/[redacted]/src/dueDate.rollover.test.ts（新規、テスト 4 件）
- /Users/sinoda/tmp/[redacted]/.vetdd/（証跡。git 管理外）

🎯 **要対応**
1. 別系統の最終判定（外部送信）を実行するか、見送るかを決めてください。

⚠️ **懸念**
- CLI からは rollover を指定できません（依頼の範囲外）。
- vetdd の pre-commit フックは hooksPath の設定で無効になっています。
