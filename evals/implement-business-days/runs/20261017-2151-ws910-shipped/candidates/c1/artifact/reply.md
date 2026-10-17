## Result
blocked（test モード）。実装と、手元で回せる検証はすべて済んでいます。止まっているのは最後の別系統モデル判定（[redacted]）だけです。この判定は外部サービスを使うため、「マシンの外に出さない」という指示に従って手前で止めました。

`paymentDueDate` の第3引数 `{ rollover: "next-business-day" }` は動いています。指定いただいた 3 件の期待値は `paymentDueDate` を直接呼ぶテストで通りました。既存の vitest スイート（13 件）と `npm run typecheck` も緑です（Measured）。

---

## 経緯
プロジェクトの `[redacted].md` は「`.[redacted]/skills/vetdd/SKILL.md` に従え」と指示しています。タスクの Oracle 欄が「プロジェクト自身の指示に従う」だったので、この手順に従いました。Skill ツールは使わず、ファイルを直接読んで進めています。

vetdd の手順のうち、次の 3 つは指示に合わせて変えました。
- **合意（AskUserQuestion）**: ご依頼文で決定済みだったため、質問はしていません。依頼文の内容を `.vetdd/notes/rollover-1-v1.txt` に記録しました。
- **最終判定（`judge.sh` / [redacted]）**: 外部サービスなので実行していません。
- **任意のリファクタ（別エージェント）**: 「ヘルパー禁止」と変更量が小さいことから省略しました。

## Oracle
Seam: `paymentDueDate()` のユニットテスト（src/dueDate.ts）、version 1。
期待値は、依頼文で手計算いただいた次の 3 件です。
- `("2026-04-30", 30, opt)` → `"2026-06-01"`
- `("2026-07-31", 30, opt)` → `"2026-08-31"`
- `("2026-05-31", 30, opt)` → `"2026-06-30"`

曜日はコードを通さずに macOS の `date` でも確認しました。5/30 が土曜、8/30 が日曜、6/30 が火曜です（Measured）。

テストを 1 件追加しています。「第3引数なしなら今と同じ」という要件ですが、既存テストの期待値はすべて平日でした。このため「常に繰り延べる」ような誤りを既存テストでは検出できません。そこで、週末に当たる例として `paymentDueDate("2026-04-30", 30)` → `"2026-05-30"` を加えました。期待値は現行コードの出力と手計算の 4/30 + 30 日です。

- 対象外: 祝日。
- 見えない部分（Blind spots）: CLI（`src/cli.ts`）と `computeInvoiceSchedule` にはこのオプションを通していないので、そこは検証していません。

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before | target_failure（土曜・日曜の 2 件が `expected '2026-05-30' to be '2026-06-01'` などのアサーションで失敗） | .vetdd/evidence/rollover-1/runs/001-before.log |
| rollover-1 | after（不採用） | target_failure | runs/002-after.log |
| rollover-1 | after | pass（4/4） | runs/003-after.log |
| rollover-1 | calibration（import を undefined にする監査） | target_failure（`TypeError: paymentDueDate is not a function`） | runs/004-calibration.log |
| rollover-1 | after（全スイート / 型チェック） | pass / pass | runs/005-after.log, runs/006-after.log |
| rollover-1 | integrated（スライド単体 / 全スイート 13 passed / 型チェック） | pass ×3 | runs/007〜009-integrated.log |
| rollover-1 | calibration（Stryker 変異監査、src/dueDate.ts:86-99, 113-114） | 11 mutants、11 killed、0 survived | runs/010-calibration.log, runs/010-mutation.json |

run 2 は不採用の試行です。編集ツールのエラーで修正が入らないまま after を流してしまいました。記録上は accepted=false の試行として残っており、stall.sh の判定は「停滞なし」でした。

check-evidence の出力:
```
rollover-1: OK
```

## Requirements → evidence
- 土曜 → 翌月曜（2026-06-01）: runs/003, runs/007（Measured）
- 日曜 → 翌月曜（2026-08-31）: runs/003, runs/007（Measured）
- 平日はそのまま（2026-06-30）: runs/003, runs/007（Measured）
- 第3引数なしは従来どおり: 追加した週末ケースが pass し、既存 dueDate/invoice テストも全件 pass しました（runs/008、13 passed）（Measured）
- `npm run typecheck` が緑: runs/006, runs/009（Measured）

## Change
- `src/dueDate.ts`
  - `PaymentDueDateOptions` 型を追加しました。`rollover?: "next-business-day"` を持ちます。
  - 内部関数 `nextBusinessDay` を追加しました。土曜なら +2 日、日曜なら +1 日、平日はそのままです。
  - `paymentDueDate` に第3引数 `options`（既定値 `{}`）を足しました。暦日加算の結果に、オプション指定時だけ `nextBusinessDay` を適用します。
- `src/dueDate.rollover.test.ts`（新規）: 依頼の 3 件と、オプションなしの週末ケース 1 件を入れました。
- 証拠は `.vetdd/` に置いています（gitignore 済み）。コミットも push もしていません。

## Judge
not run: 最終判定は別系統モデル（[redacted]、`.[redacted]/skills/vetdd/scripts/judge.sh`）への送信が前提で、外部サービスの呼び出しにあたります。指示どおりここで止めました。この判定だけが未実施の手順です。実行する場合は、手順に沿って `judge-layout.sh` で判定用ディレクトリを作り、`judge.sh` を流すことになります。送られるのは差分・返信草稿・check-evidence 出力・オラクルファイル・meta.json・赤ログ・変異レポートです。

## Attention
- 確認が要る点: `setup-project.sh` が警告を出しました。`core.hooksPath` が `/Users/sinoda/.git-hooks` を指しているため、`.git/hooks/pre-commit` に入った vetdd フックは git から呼ばれません。設定は変更していません。
- 変異監査の範囲は変更した行だけです。範囲外にある既存の `termDays` 入力チェック（行 110-112）を検出できるテストは、既存スイートにもありません。
- README と CLI は更新していません。README の支払期日の説明にオプションを追記するかどうかは、そちらで判断してください。
- 上記のとおり、リファクタ工程は省略しました。

変更ファイル:
- /Users/sinoda/tmp/[redacted]/src/dueDate.ts
- /Users/sinoda/tmp/[redacted]/src/dueDate.rollover.test.ts（新規）
- 証拠: /Users/sinoda/tmp/[redacted]/.vetdd/evidence/rollover-1/
