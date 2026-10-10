# Phase 6 の作業記録

## PR 1: swarm（2026-10-11）

### 実地試験: ts-kata の (b) を swarm の 2 単位で

- 題材: KATA (b)「土日の支払期日を翌営業日に繰り越す」。
- 単位: `sat-rollover`（`src/rollover/saturday.ts`）と `sun-rollover`（`src/rollover/sunday.ts`）。
- 進め方: 2 つとも `paymentDueDate` の中に入るので、親が先に「契約」をコミットしました。契約は、第 3 引数 `{ rollover }` と、何もしない土曜・日曜の関数です。各 worker は自分のファイルだけを書きます。この手順は swarm.md の「The contract first」に書きました。
- 親は私（このセッション）です。worker は opus の 2 体で、それぞれ別の worktree で、裏で同時に動かしました。
- 結果:
  - check-evidence は 2 slice とも OK でした。
  - 最終判定は 3 回目で pass（confidence high、全基準 2 点）でした。1・2 回目の partial は、どちらも親が書いた返信の不備です（下の摩擦 3・4）。

### 時刻（親の記録）

| 段階 | 時刻 | 所要 |
|---|---|---|
| 契約を書いてコミット | 08:21:31 – 08:21:47 | 16 秒（型検査の import の直しは別途） |
| worktree 2 つと最初の合意の記録 | 08:22:04 – 08:22:05 | 1 秒 |
| worker 2 体（同時） | 08:22:37 – 08:23:37 | 60 秒（各 worker の自己申告は約 37 秒） |
| 順に統合（merge、remove、integrated） | 08:23:37 – 08:23:40 | 3 秒 |
| Close（integrated、変異テスト、check-evidence） | 08:24:04 – 08:24:24 | 20 秒（取り直しは 08:28 – 08:29:02） |
| 判定の準備と判定 | 08:29:14 – 08:30:23 | 約 70 秒（1 回あたり） |

摩擦を除けば、契約から判定までおよそ 3 分です。worker 2 体を同時に動かして 60 秒、直列なら約 100 秒の見込みなので、縮んだのは 40 秒ほどです。今回は単位が小さいため、並列の効果は小さく出ました。

### 摩擦と、この PR での手当て

1. **親が単位のコマンドを打ち間違えた（約 14 秒）。** `integrated` を記録するときに、テストファイル名を `satday.test.ts` と組み立てて赤になりました。記録には accepted=false が 2 件残っています。
   - 手当て: `evidence.sh <slice> integrated --rerun` を足しました。単位の `after` に記録されたコマンドを、もう一度走らせます。swarm.md の統合と Close はこれを使います。
2. **worker のログに worktree のパスが残り、judge-layout が exit 4 で止まった（約 1.5 分）。** ログに `<repo>.vetdd-wt/<slice>` が残り、判定者への検査に当たりました。
   - 手当て: judge-layout.sh が `<root>.vetdd-wt/<slice>` も `<repo>` に置き換えます（テストあり）。
3. **親が Close で既存のテスト一式の `integrated` を飛ばした（判定 partial）。** 全テストと型検査を記録しないまま、返信で緑と書きました。
   - 手当て: swarm.md の Close に「各 slice の自分のコマンド（`--rerun`）と、合意した既存のテスト一式」と明記しました。`--rerun` は、間に記録した既存のテストのコマンドではなく、`after` のコマンドを使います。
4. **返信の主張に根拠を示していなかった（判定 partial）。** 「第 3 引数なしでは今と同じ」を実測と書いたのに、根拠の記録を示していませんでした。親の書き方の問題で、判定者が正しく見抜きました。

### 気づいたこと

- worker の指示書の「Report」に、開始と終了の時刻を入れると、親の記録と突き合わせられます。今回は手で入れました。
- calibrate.sh は、校正の状態を `.git/worktrees/<slice>/vetdd-calib/` に置きます。worktree を消すと一緒に消えるので、問題はありません。
