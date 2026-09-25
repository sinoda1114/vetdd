# ts-kata

請求書の締め日と支払期日を計算する、小さな TypeScript プロジェクトです。vetdd の練習台として同梱しています。

- 締め日: 請求日がその月の締め日以前なら当月の締め日、過ぎていれば翌月の締め日です。締め日は 1〜28 の日付か `end`（月末）で指定します。
- 支払期日: 締め日に支払サイト（日数）を暦日で足した日です。祝日は扱いません。

## 使い方

```sh
npm ci
npm test            # vitest
npm run typecheck   # tsc --noEmit
npx tsx src/cli.ts due 2026-01-10 --closing end --term 30
```

CLI の出力は 2 行です。

```
closing: 2026-01-31
due: 2026-03-02
```

`--closing` の既定は `end`、`--term` の既定は 30 日です。入力が不正なときは usage を表示して終了コード 2 で終わります。

## 構成

- `src/dueDate.ts`: `closingDate` と `paymentDueDate`（純粋関数、日付は `YYYY-MM-DD` 文字列）
- `src/invoice.ts`: 両者を組み合わせる `computeInvoiceSchedule`
- `src/cli.ts`: `due` コマンド

`.npmrc` で `ignore-scripts=true` にしているので、`npm ci` は依存のインストールスクリプトを実行しません。
