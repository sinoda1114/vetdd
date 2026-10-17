`paymentDueDate` は3つ目の引数 `{ rollover: "next-business-day" }` を受け付けるようになり、指定した3つの日付はすべて期待どおりの値を返します。既存の vitest と `npm run typecheck` は通っています。ただし結果は blocked です。プロジェクトの手順では最後に別系統の外部モデルによる判定が必要ですが、今回は外部サービスを呼ばない条件なので、その手前で止めています。足りないのはその判定だけです。コミットも push もしていません。

---

## Result
blocked（test モード）。外部ジャッジの判定だけが未実施です。

## Oracle
- **シーム**: `paymentDueDate()` を直接呼ぶユニットテストで、版は1です（Measured: `.vetdd/evidence/rollover-1/meta.json`, `.vetdd/evidence/rollover-2/meta.json`）。
- **期待値**: `"2026-06-01"`（土曜の繰り越し）、`"2026-08-31"`（日曜の繰り越し）、`"2026-06-30"`（平日はそのまま）、オプションなしなら `"2026-05-30"` のままです（Measured: `src/dueDate.rollover.test.ts` で assert しています）。
- **期待値の出所**: 値はあなたが2026年のカレンダーから手で出したものです。私も `cal 5/6/8 2026` で曜日を照合し、一致しました（inferred: ジャッジはこれらの資料を受け取りません）。
- **範囲外**: 祝日と、CLI・`computeInvoiceSchedule` へのオプション配線です（inferred: 依頼内容から判断）。
- **確認方法**: 合意事項は依頼文に「決定済み」と書かれていたので、プロジェクト手順にある AskUserQuestion は使っていません。代わりに `.vetdd/notes/agreement-v1.md` に記録しました（inferred）。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1（土曜） | before | target_failure（`expected '2026-05-30' to be '2026-06-01'`） | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | calibration（平日・オプションなしの正常ケース） | pass | .vetdd/evidence/rollover-1/runs/002-calibration.log |
| rollover-1 | after | pass | .vetdd/evidence/rollover-1/runs/004-after.log |
| rollover-1 | calibration（import を undefined にした監査） | target_failure（`TypeError: paymentDueDate is not a function`） | .vetdd/evidence/rollover-1/runs/005-calibration.log |
| rollover-1 | integrated（自スライス / 全テスト 13 passed / typecheck） | pass | .vetdd/evidence/rollover-1/runs/008〜010-integrated.log |
| rollover-1 | 変異テスト（91-100, 110-113行） | 11 killed / 0 survived | .vetdd/evidence/rollover-1/runs/012-mutation.json |
| rollover-2（日曜） | before | target_failure（`expected '2026-08-30' to be '2026-08-31'`） | .vetdd/evidence/rollover-2/runs/001-before.log |
| rollover-2 | calibration | pass | .vetdd/evidence/rollover-2/runs/002-calibration.log |
| rollover-2 | after | pass | .vetdd/evidence/rollover-2/runs/004-after.log |
| rollover-2 | calibration（import を undefined にした監査） | target_failure（TypeError） | .vetdd/evidence/rollover-2/runs/005-calibration.log |
| rollover-2 | integrated（自スライス / 全テスト 13 passed / typecheck） | pass | .vetdd/evidence/rollover-2/runs/008〜010-integrated.log |
| rollover-2 | 変異テスト（同じ範囲） | 11 killed / 0 survived | .vetdd/evidence/rollover-2/runs/011-mutation.json |

すべての行は Measured です。check-evidence の出力は次のとおりで、終了コードは0でした（Measured）。
```
rollover-1: OK
rollover-1: WARN (9c: 3 skipped and 0 todo tests in the latest integrated run 8, ...)
rollover-2: OK
rollover-2: WARN (9c: 3 skipped and 0 todo tests in the latest integrated run 8, ...)
```

## Requirements → evidence
- **土曜は翌月曜**: `.vetdd/evidence/rollover-1/runs/008-integrated.log` で確認しました（Measured）。
- **日曜は翌月曜**: `.vetdd/evidence/rollover-2/runs/008-integrated.log` で確認しました（Measured）。
- **平日はそのまま / オプションなしは従来どおり**: 正常ケースは `.vetdd/evidence/rollover-1/runs/002-calibration.log`、全テスト 13 passed は `.vetdd/evidence/rollover-1/runs/009-integrated.log` で確認しました（Measured）。
- **typecheck が緑**: `.vetdd/evidence/rollover-1/runs/010-integrated.log` で確認しました（Measured）。

## Change
- **`src/dueDate.ts`**: `DueDateOptions` 型と `daysToNextBusinessDay`（土曜なら+2日、日曜なら+1日、平日は0日）を追加しました。`paymentDueDate` に省略可能な第3引数 `options: DueDateOptions = {}` を足しています（Measured: the diff）。
- **オプション未指定時の動き**: `rollover` が `"next-business-day"` でなければ、従来と同じ `formatDate(due)` を返します（Measured: the diff）。既存の呼び出し側（`invoice.ts`, `cli.ts`）は変わりません（inferred: 引数が省略可能なため）。
- **曜日の判定**: 既存の `toUtc` と同じ UTC 基準で曜日を取っているので、TZ には左右されません（inferred: the diff）。
- **新規テスト**: `src/dueDate.rollover.test.ts` に4件追加しました（Measured）。

## Judge
未実施です。手順では最後に別系統のモデル（[redacted]）が判定しますが、それは外部サービスへの送信になります。「Nothing leaves this machine」の条件に従い、`judge.sh` の手前で止めました。

## Attention
- **ジャッジが未実施**: これが唯一の未完了ステップです。進めるなら、外部ジャッジへの送信を許可するか、手元で判定を済ませるかを決めてください（inferred）。
- **after の失敗記録が1件ある**: 最初の `after`（run 003、両スライス）は、私の編集操作が反映されないまま走ったため、target_failure として記録が残っています（Measured: `.vetdd/evidence/rollover-1/runs/003-after.log`）。その後 `stall.sh` を回し、停滞なしを確認しました。
- **WARN 9c の3件スキップ**: 名前フィルタで外した残り3件のことです。これらは全テストを流した run 009（13 passed）で実行済みです（Measured: `.vetdd/evidence/rollover-1/runs/009-integrated.log`）。
- **変異テストの範囲**: 最初は 106-113 行全体で回しました。すると今回触っていない既存の入力検証（107-108行、`termDays < 0` の分岐とエラーメッセージ）で6件が生き残りました（Measured: `.vetdd/evidence/rollover-1/runs/011-mutation.json`）。既存の入力検証にはテストがないということで、今回の範囲外として残しています。変更行に絞った最終実行では全件 killed です。
- **リファクタ工程は省略**: 手順では別のサブエージェントが行う工程ですが、「helpers なし」の指定に従って省きました（inferred）。

---

📝 **変更**
- `src/dueDate.ts:86-113` — `DueDateOptions` 型、`daysToNextBusinessDay`、`paymentDueDate` の第3引数を追加
- `src/dueDate.rollover.test.ts`（新規、テスト4件）
- `.vetdd/notes/agreement-v1.md`, `.vetdd/notes/agreement-v1-reason.txt`（新規、合意の記録。`.vetdd/` は gitignore 対象）

🎯 **要対応**
1. 最終ジャッジを外部（[redacted]）に送ってよいか判断してください。送る場合は、差分・返信案・証跡がマシンの外に出ます。

⚠️ **懸念**
- `paymentDueDate` の既存の入力検証（負の日数・非整数）にはテストがありません。今回の範囲外です。
- CLI と `computeInvoiceSchedule` にはまだこのオプションを渡す手段がありません。依頼の範囲外です。
