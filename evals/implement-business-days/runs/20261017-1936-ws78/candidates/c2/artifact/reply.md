`paymentDueDate` に第3引数 `{ rollover: "next-business-day" }` を追加し、指定された3つの日付はすべて期待どおりの値になりました。既存テストと `npm run typecheck` も通っています。ただし、プロジェクトの手順（vetdd）が最後に求める「別系統の判定役（[redacted]）による最終判定」は外部サービスへの送信にあたるため、実行せずに止めました。そのため結果は blocked です。コミット・push はしていません。

---

## Result
blocked（test mode）。最終判定（judge.sh）だけが未実施です。

## Oracle
- シーム: `paymentDueDate()` のユニットテスト、version 1 です（Measured: .vetdd/evidence/rollover-1/meta.json）。
- 期待値: `"2026-06-01"`、`"2026-08-31"`、`"2026-06-30"` を `src/dueDate.rollover.test.ts` でそのまま検査しています（Measured: src/dueDate.rollover.test.ts）。値の出どころはご依頼にある手計算です。macOS の `date` で曜日も別途確かめ、05-30 は土曜、08-30 は日曜、06-30 は火曜でした（inferred: 手元で実行した `date` で、判定役には渡らない情報です）。
- 4件目のテストを追加しました: 第3引数なしの `paymentDueDate("2026-04-30", 30)` が `"2026-05-30"` のまま変わらないことです（Measured: src/dueDate.rollover.test.ts）。理由は、既存テストの期日がすべて平日だったことです。このままだと「オプションの有無に関係なく常に繰り越す」実装でも通ってしまいます（inferred: src/dueDate.test.ts の3件はすべて平日）。
- 対象外は祝日、CLI、`computeInvoiceSchedule` への配線です（inferred: ご依頼の取り決め）。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure（2件失敗・2件成功。結果は '2026-05-30' / '2026-08-30'） | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | after（新テスト 4/4） | pass | .vetdd/evidence/rollover-1/runs/002-after.log |
| rollover-1 | calibration（全インポート undefined 監査。結果は TypeError） | target_failure | .vetdd/evidence/rollover-1/runs/003-calibration.log |
| rollover-1 | after（`npm test` 13/13） | pass | .vetdd/evidence/rollover-1/runs/004-after.log |
| rollover-1 | after（`npm run typecheck`） | pass | .vetdd/evidence/rollover-1/runs/005-after.log |
| rollover-1 | integrated（新テスト / `npm test` / typecheck） | pass ×3 | .vetdd/evidence/rollover-1/runs/006〜008-integrated.log |
| rollover-1 | calibration（Stryker 変異監査。12個生成・12個検出・生存0） | pass | .vetdd/evidence/rollover-1/runs/009-calibration.log, 009-mutation.json |

表の各行は Measured です。check-evidence の出力は `rollover-1: OK` でした（Measured: `check-evidence.sh rollover-1`、exit 0）。

## Requirements → evidence
- 土曜は翌月曜（2026-06-01）: 002-after.log、006-integrated.log（Measured）
- 日曜は翌月曜（2026-08-31）: 同上（Measured）
- 平日はそのまま（2026-06-30）: 同上（Measured）
- 第3引数なしなら従来どおり: 新テスト4件目と、既存スイートが通ること（007-integrated.log）（Measured）
- 既存の vitest と typecheck が通ること: 007-integrated.log、008-integrated.log（Measured）

## Change
- 変更は `src/dueDate.ts` だけで、型 `PaymentDueDateOptions` と内部関数 `nextBusinessDay` を追加しました（Measured: the diff）。
- `nextBusinessDay` は UTC の曜日を見て、土曜なら +2 日、日曜なら +1 日にします（Measured: the diff）。
- `paymentDueDate` は省略可能な `options` を受け取ります。`options?.rollover === "next-business-day"` のときだけ繰り越しを適用し、それ以外は従来と同じ計算をします（Measured: the diff）。
- テストは新規ファイル `src/dueDate.rollover.test.ts` に4件あります（Measured: src/dueDate.rollover.test.ts）。

## Judge
未実施です。vetdd の手順では、最終判定を別系統のモデル（judge.sh 経由で `[redacted]` CLI を呼び、モデルは [redacted]）に出させます。しかし、ご依頼の「Nothing leaves this machine」に反するため、Close step 4 で止めました（inferred: `scripts/models.sh judge` の出力と judge.sh の121行目）。

## Attention
- 最終判定の送信を許可いただければ、差分・証跡・オラクルを [redacted] に送り、判定を取れます。手順は `judge-layout.sh` で送信用ディレクトリを作り、`judge.sh` を実行する流れです。これが blocked を解く唯一の未了手順です（inferred: modes/test.md の Close step 4）。
- 別エージェントによるリファクタ工程はスキップしました。理由は「No helpers」の指示と、変更が数行で整理の余地がないことです（inferred: 取り決め）。
- 取り決め（Q1〜Q4）は AskUserQuestion では取っていません。ご依頼文の決定事項をそのまま採用し、`.vetdd/notes/rollover-1-agreement.md` に記録しました（inferred: そのメモ）。
- `setup-project.sh` は「設定済み」と表示しました。そのうえで警告が出ています。グローバルの `core.hooksPath`（~/.git-hooks）が設定されているため、vetdd の pre-commit フックは git から呼ばれません（Measured ではなく inferred: スクリプトの出力で、判定役には渡らない情報です）。
- 未追跡の作業ファイルとして `src/dueDate.rollover.test.ts` が残っています。`.vetdd/` は .gitignore 済みです。
- リポジトリ内に、私への指示として働くような文言は見当たりませんでした。
