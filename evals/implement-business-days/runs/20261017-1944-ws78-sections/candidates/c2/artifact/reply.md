## Result
blocked（test mode）です。別系統の判定だけが未実施です。

## Oracle
- **シーム**: `paymentDueDate()` を直接呼ぶ単体テストで、新規ファイル `src/rollover.test.ts`、版 1 です。期待値はご提示いただいた2026年カレンダーの手計算から取りました。
  - 2026-04-30 + 30 → `"2026-06-01"`（土曜）
  - 2026-07-31 + 30 → `"2026-08-31"`（日曜）
  - 2026-05-31 + 30 → `"2026-06-30"`（火曜、変わらない）
- **4件目のテスト**: 引数なしなら土曜でもずらさないこと（2026-04-30 + 30 → `"2026-05-30"`）を確かめるテストを1件足しました。「引数なしなら今と同じ」というご指定から取った値です。これがないと「常にずらす」という誤った実装をミューテーション監査で捕まえられません。
- **合意の記録**: 手順上は AskUserQuestion で確認する箇所ですが、「確認不要」とのご指示なので、依頼文の内容をそのまま `.vetdd/notes/rollover-1-initial.md` に記録しました。
- **対象外**: 祝日、CLI、`computeInvoiceSchedule` です。CLI からはこのオプションを指定できません。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure（土日の2件が `'2026-05-30'` / `'2026-08-30'` を返して失敗） | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | after | pass（4/4） | runs/004-after.log |
| rollover-1 | calibration（全 export を undefined にする監査） | target_failure（`TypeError: paymentDueDate is not a function`） | runs/005-calibration.log |
| rollover-1 | after（vitest 全件） | pass（13 passed） | runs/006-after.log |
| rollover-1 | after（typecheck） | pass | runs/007-after.log |
| rollover-1 | integrated（専用テスト・全件・typecheck） | pass ×3 | runs/008〜010 |
| rollover-1 | calibration（Stryker、変更行 95-100 と 110-111） | 12 killed / 0 survived | runs/012-calibration.log |

check-evidence の出力は `rollover-1: OK` です（Measured）。

## Requirements → evidence
- **土曜は翌月曜になる**: 001 で赤、008 で緑です（Measured）。
- **日曜は翌月曜になる**: 001 で赤、008 で緑です（Measured）。
- **平日は変わらない**: 008 で緑です。実装前から通るテストなので、これ単体は赤になっていません。ずらしすぎる誤りを捕まえることは、012 のミューテーション監査で確かめました（Measured）。
- **引数なしは今と同じ**: 新規テスト（008）と既存 suite 全件（009、13 passed）で確かめました（Measured）。
- **typecheck が通る**: 010 で確かめました（Measured）。

## Change
- **`src/dueDate.ts`**: 型 `PaymentDueDateOptions` と内部関数 `nextBusinessDay` を追加しました。曜日は UTC で判定し、日曜なら +1日、土曜なら +2日します。`paymentDueDate` の3番目の引数は省略できます。
- **`src/rollover.test.ts`（新規）**: 上の4件のテストです。
- 上の2ファイル以外は変えていません。コミットもしていません。

## Judge
未実施です。手順が求める [redacted] の判定（`judge.sh`、差分と証拠を外部に送る）は「外部サービス・レビュアーを呼ばない」というご指示に当たるので、実行していません。

## Attention
- **作業中の失敗試行が記録に残っています（結果には影響しません）**:
  - 最初の編集がツールに拒否され、変更前のまま `after` を1回記録しました（run 2、未採用の失敗試行）。
  - 未修正の状態で undefined 監査も1回走りました（run 3）。
- **初回のミューテーション監査は範囲の指定ミスで生存6件でした（run 11）**: 範囲を広く取りすぎ、今回触っていない既存の `termDays` 検証（107-108行）まで含めていました。6件はすべてその行です。変更行に絞った再実行（run 12）で 12/12 killed です。既存の検証にテストがないことは今回の範囲外です。
- **リファクタ工程は省きました**: 変更が小さいことと、「ヘルパー不可」のご指示が理由です。
- **一時ファイル**: 監査の出力を一時的に `/tmp/dummy` に置き、すぐ削除しました。リポジトリ外に書いたのはこの一回だけです。
- **pre-commit フックは効きません**: `core.hooksPath`（`~/.git-hooks`）が設定されているためです。設定は変えていません。
