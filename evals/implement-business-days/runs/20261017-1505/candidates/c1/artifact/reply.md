## Result
**blocked（test モード）**。`paymentDueDate` に3つ目の引数（省略可）`{ rollover: "next-business-day" }` を足しました。ご指定の3つの日付はすべて期待どおりの値を返し、既存の vitest スイートと型検査も通っています（Measured）。止めたのは最後の1工程だけです。プロジェクトの手順（`.[redacted]/skills/vetdd`）は、別系統のモデル（[redacted]）に最終判定をさせることを求めています。しかし「外部サービスやレビュアーを呼ばない」というご指示があるため、その判定の手前で止めました。

---

## Oracle
- **Seam（テストを当てる場所）**: `paymentDueDate()` を直接呼ぶ単体テスト。オラクル（判定に使うテスト）は version 2、ファイルは `src/dueDate.rollover.test.ts` です。
- **期待値**: 4つです。
  - `"2026-06-01"`（土曜 → 月曜）
  - `"2026-08-31"`（日曜 → 月曜）
  - `"2026-06-30"`（火曜なので変わらない）
  - `"2026-05-30"`（3つ目の引数なし。週末でも動かない）
- **期待値の出どころ**: いただいた手計算の値です。曜日は BSD の `date` でも独立に確かめました。5/30 は土曜、8/30 は日曜、6/30 は火曜です（Measured）。
- **カバー範囲**: 土曜・日曜の繰り越し、平日はそのまま、引数なしでは繰り越さないこと。3つ目の引数がないときの従来の動きは、既存の `dueDate.test.ts` と `invoice.test.ts` が見ています。
- **範囲外**: 祝日。
- **見えていないところ**: 確かめた期日はすべて 2026 年です。CLI（`src/cli.ts`）にはこの機能をつないでいません（依頼の範囲外です）。

## Evidence（`/Users/sinoda/tmp/[redacted]/.vetdd/evidence/rollover-1/runs/`）
| slice | kind | outcome | path |
|---|---|---|---|
| rollover-1 | before (v1) | target_failure（土日の2件で AssertionError） | 001-before.log |
| rollover-1 | after（自分のテスト、スイート、型検査） | pass | 005/006/007-after.log |
| rollover-1 | calibration（import を undefined にした監査） | target_failure（TypeError） | 008-calibration.log |
| rollover-1 | calibration（mutation, v1） | 生き残り 2 | 012-calibration.log |
| rollover-1 | calibration（修正を外した赤, v2） | target_failure（土日の2件で AssertionError） | 013-calibration.log |
| rollover-1 | after (v2) | pass（4 passed） | 019-after.log |
| rollover-1 | calibration（undefined 監査, v2） | target_failure（TypeError ×4） | 020-calibration.log |
| rollover-1 | integrated（自分のテスト、全スイート 13 passed、typecheck） | pass | 021/022/023-integrated.log |
| rollover-1 | calibration（mutation, v2） | 12 killed / 0 survived | 024-calibration.log |

check-evidence の出力です。
```
rollover-1: OK
```

## Requirements → evidence
- 2026-04-30 + 30（土曜）が "2026-06-01" になる: 021-integrated.log（Measured）
- 2026-07-31 + 30（日曜）が "2026-08-31" になる: 021-integrated.log（Measured）
- 2026-05-31 + 30（火曜）が "2026-06-30" のまま: 021-integrated.log（Measured）
- 3つ目の引数がなければ従来どおり: 022-integrated.log（既存スイートを含む `Tests 13 passed (13)`）と、021 の引数なしのケース（Measured）
- `npm run typecheck` が通る: 023-integrated.log（Measured）

## Change
- `src/dueDate.ts`: 型 `PaymentDueDateOptions` を追加し、`paymentDueDate` に3つ目の引数 `options?` を足しました。暦日で足した結果が土曜なら +2 日、日曜なら +1 日にします。判定は内部関数 `daysToNextWeekday` で、UTC の曜日を見ます。オプションがなければ、これまでとまったく同じ経路で返します。
- `src/dueDate.rollover.test.ts`（新規）: ご指定の3件に、引数なしのケースを1件加えたテストです。

## Judge
**実行していません。** プロジェクトの手順では、別系統のモデル（`judge.sh` 経由の [redacted]）に判定させます。これは差分と証跡を外部サービスへ送ることになるため、ご指示に従ってこの工程で止めました。

## Attention
- **オラクルを v2 に上げました。** v1 の mutation 監査（012）で、`src/dueDate.ts:113` に生き残りが2件出ました。(1) `if` の条件を常に false にした変異と、(2) `options?.` を `options.` にした変異です。v1 のテストは全件オプション付きで呼んでいたため、これらを殺せませんでした。合意済みの「引数なしでは従来どおり」の範囲で、引数なしのケースを1件足しています。理由は `.vetdd/notes/reason-v2.md` に記録しました。
- **途中で赤の記録が残っています。** 1回目の編集はファイル未読のため失敗しましたが、並行して走らせた `after` 3件（002〜004）が修正前のコードに対して記録されました。いずれも accepted=false です。stall チェックの結果は「停滞なし」でした。
- **自分のテストの v2 `after` を一度記録し損ねました。** zsh で引数を変数にまとめて渡したところ、コマンドが受け付けられず記録されませんでした（使い方エラー）。そのため 014〜018 は自分のテストの v2 `after` より先に並んでいます。019 以降で記録し直してあり、check-evidence は OK です。
- **リファクタは省きました。** 別エージェントの起動が禁止されていたためで、変更も数行です。
- **合意は AskUserQuestion で取っていません。** 依頼文で決まっていた内容を `.vetdd/notes/agreement-*.md` に記録しました（`--agreement-via chat`）。
- `setup-project.sh` によると、`core.hooksPath=/Users/sinoda/.git-hooks` が設定されているため、vetdd の pre-commit フックは git に無視されます。commit も push もしていません。

---

📝 **変更**
- `/Users/sinoda/tmp/[redacted]/src/dueDate.ts:86-115`: `PaymentDueDateOptions`、`daysToNextWeekday`、`paymentDueDate` の3つ目の引数
- `/Users/sinoda/tmp/[redacted]/src/dueDate.rollover.test.ts`（新規、テスト 4 件）
- `/Users/sinoda/tmp/[redacted]/.vetdd/`（git 管理外。証跡とメモ）

🎯 **要対応**
1. 別系統の判定（[redacted]）を回すかどうか決めてください。差分・証跡・オラクルのファイルを外部の [redacted] に送ることになるため、許可が要ります。

⚠️ **懸念**
- 確かめた期日は 2026 年のみです。CLI はこの機能に未対応です。
