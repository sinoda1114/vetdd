## Result
blocked, test mode（inferred: 下の証拠。外部の最終判定だけが未実施）

## Oracle
- **シーム**: `paymentDueDate() unit`。版は rollover-1 と rollover-2 が v2、rollover-3 が v1 です（Measured: .vetdd/evidence/<slice>/meta.json）。
- **期待値**: 以下をテストファイルで assert しています（Measured: src/rollover-saturday.test.ts, src/rollover-sunday.test.ts, src/rollover-unchanged.test.ts）。
  - `"2026-06-01"`（2026-05-30 は土曜）
  - `"2026-08-31"`（2026-08-30 は日曜）
  - `"2026-06-30"`（火曜、変化なし）
- **期待値の出所**: ご依頼の手計算です。`cal` コマンドでも曜日を照合しました（inferred: 手元の確認で、判定役には渡らない）。
- **追加したガード**: オプションなしでは土曜の 2026-05-30 が動かないことも確かめています（Measured: src/rollover-unchanged.test.ts）。期待値はご依頼にある「2026-04-30 + 30日 = 2026-05-30」から取りました（inferred）。
- **対象外**: 祝日、CLI と `computeInvoiceSchedule` の配線（inferred: 合意メモ .vetdd/notes/agreement-v1.md）。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure（expected '2026-05-30' to be '2026-06-01'） | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | calibration（v2 で修正を一時退避） | target_failure | .vetdd/evidence/rollover-1/runs/011-calibration.log |
| rollover-1 | integrated（スライス / 全体 16 件 / 型検査） | pass | runs/016〜018-integrated.log (local log) |
| rollover-1 | mutation | 7/7 killed | runs/019-calibration.log (local log) |
| rollover-2 | before | target_failure（expected '2026-08-30' to be '2026-08-31'） | .vetdd/evidence/rollover-2/runs/001-before.log |
| rollover-2 | calibration（v2 で修正を一時退避） | target_failure | .vetdd/evidence/rollover-2/runs/010-calibration.log |
| rollover-2 | integrated（スライス / 全体 / 型検査） | pass | runs/015〜017-integrated.log (local log) |
| rollover-2 | mutation | 3/3 killed | runs/018-calibration.log (local log) |
| rollover-3 | calibration（変異を植えて赤を確認） | target_failure | .vetdd/evidence/rollover-3/runs/001-calibration.log |
| rollover-3 | integrated（スライス / 全体 / 型検査） | pass | runs/009〜011-integrated.log (local log) |

表の各行は Measured です。

check-evidence の出力は次のとおりです（Measured, local log: .vetdd/notes/check-evidence.txt）。
```
rollover-1: OK
rollover-2: OK
rollover-3: OK
```

**直接の呼び出し**: 実際の戻り値も読みました（Measured, local log: このセッションで実行した tsx の出力）。結果は `2026-06-01 2026-08-31 2026-06-30 2026-05-30 2026-03-02` です（最後の2つはオプションなしの呼び出し）。

## Requirements → evidence
- **土曜 → 翌月曜**: 赤は .vetdd/evidence/rollover-1/runs/001-before.log、緑は runs/016-integrated.log です（Measured）。
- **日曜 → 翌月曜**: 赤は .vetdd/evidence/rollover-2/runs/001-before.log、緑は runs/015-integrated.log です（Measured）。
- **平日は不変**: 赤は .vetdd/evidence/rollover-3/runs/001-calibration.log、緑は runs/009-integrated.log です（Measured）。
- **第3引数なしは従来どおり**: 既存の全テストと型検査が pass です（Measured, local log: rollover-*/runs/*-integrated.log）。オプションなしの土曜ガードも緑です（Measured: src/rollover-unchanged.test.ts）。

## Change
- **型**: `src/dueDate.ts` に型 `PaymentDueDateOptions` を追加しました（Measured: src/dueDate.ts）。
- **内部関数**: `nextBusinessDay` を追加しました。UTC の曜日が土曜なら +2 日、日曜なら +1 日、平日はそのまま返します（Measured: src/dueDate.ts）。
- **引数**: `paymentDueDate` の第3引数は既定値 `{}` の任意引数です。`rollover === "next-business-day"` のときだけ `nextBusinessDay` を通します（Measured: src/dueDate.ts）。
- **既存の呼び出し元**: 2引数のままの `src/invoice.ts` と CLI は変えていません（Measured: git diff の対象は src/dueDate.ts だけ）。
- **テスト**: 新規テストを3ファイル追加しました（Measured: src/rollover-*.test.ts）。

## Judge
未実施です。手順上の最終判定は外部の [redacted] を使いますが、このマシンの外に何も出さない指示があるためです（inferred: 依頼の合意）。

## Attention
1. **最終判定が未実施**: この1工程だけが残っています（inferred）。実施するには、外部送信を許可したうえで `judge-layout.sh` と `judge.sh` を実行します。
2. **テストの重複**: 変異監査の1回目で生き残りが3件出ました（`if (true)` が2件、オプション判定の `true` 化が1件。Measured, local log: rollover-1/runs/010-calibration.log, rollover-2/runs/009-calibration.log）。これを潰すため、土曜・日曜のテストファイルにも平日とオプションなしの対照ケースを足して v2 にしました。その結果、rollover-3 と同じケースが重複しています（Measured: src/rollover-saturday.test.ts, src/rollover-sunday.test.ts）。
3. **変異範囲から外れた行**: 型宣言、定数、doc コメント、引数リスト、`nextBusinessDay` 全体を空にする変異は、どのスライスの変異範囲にも入れていません（inferred: --mutate の範囲は 91-93, 94-95, 110-112）。rollover-3 は変異監査ではなく「テスト追加のみ」の注記で済ませています（Measured, local log: .vetdd/notes/mutation-note-rollover-3.txt）。
4. **省いた工程**: 別エージェントによるリファクタは、補助なしの指示に従って省きました（inferred）。AskUserQuestion も使っていません。合意の4項目はご依頼の中で決まっていたためです（inferred: .vetdd/notes/agreement-v1.md）。
5. **失敗扱いの after 1回**: rollover-1 の after（runs/002）が1回失敗として記録されています。編集ツールが未読エラーで適用されず、未修正のコードのまま走ったためです（Measured, local log: rollover-1/runs/002-after.log）。停滞判定では停滞なしと出ました（Measured, local log: stall.sh の出力）。
6. **pre-commit フック**: `setup-project.sh` が警告を出しました。`core.hooksPath=/Users/sinoda/.git-hooks` が設定されているため、vetdd の pre-commit フックは git から呼ばれません（Measured, local log: setup-project.sh の出力）。
