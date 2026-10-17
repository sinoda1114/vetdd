# Phase 7 の作業記録

判定器: eval の回帰と、別の Mac に相当する clean install。完了条件は「`~/.claude/skills/vetdd` を消してリポジトリから入れ直しても Phase 3〜6 の完了条件が再現し、CI（bats、fixture の vitest、audit）が緑」です（research/plan-2026-09-25.md）。進め方の決定は 2026-10-17 のヒアリングによります。合意（1a）は前回の phase3〜6-log のものを使い回し、Phase 4 の A/B は計画どおり 2 体で初めて実施します。

## PR A: 配布（#49、#51）

- `install.sh`、README の導入手順、clean install の smoke テスト（`tests/smoke-install.bats`）、CI の追加（macOS の bash 3.2 で bats、fixture の vitest・型検査・audit）。
- 新しい macOS ジョブが製品のバグを 1 件見つけました。bash 3.2 の `[a-z]` はロケールの照合順に従い、UTF-8 では大文字にも一致します。そのため `calibrate.sh` が普通の追跡ファイルをすべて assume-unchanged として拒んでいました（#51 で修正、残りの洗い出しは #50）。
- 計測のミス: 手元で bash 3.2 として使っていた差し替えディレクトリが消えていて、10/17 の「3.2 で通過」は bash 5 でした。作り直して、版とロケール（en_US.UTF-8）を確かめてから流しています。
- `bats-bash32` と `fixture` を main の必須チェックにしました（#49 は macOS ジョブが落ちたまま自動マージされたため）。

## 入れ直し

`./install.sh`（2026-10-17 12:21）。既存の版は `~/.claude/skills-backup/vetdd-20261017-122116` に退避されました。入れた版は main（6c3152c）の `skills/vetdd` と一致します（`diff -rq`、Measured）。以下はすべてこの版で行いました。

## eval の再実行（隔離した判定者、gpt-6-sol、effort high）

| eval | 前回（effort medium） | 今回 | 読み |
|---|---|---|---|
| rubric-calibration | c1 pass（2, 2）、c2 fail（0, 0）、勝者 c1 | c1 partial（2, 1）、c2 fail（0, 0）、勝者 c1 | 正例 c1 の Oracle 行にラベルが無く、rubric v1 の段階がこの場合を覆っていない。判定者は文言どおりに厳しくなった。校正の目的（正例が勝ち、負例が fail）は保たれている。rubric は結果を見てから直さず、v2 の候補を #53 に |
| final-judge-dogfood | pass（全 6 基準 2 点） | pass（全 6 基準 2 点）、disagreements も同じ 1 件 | 回帰なし |

記録は `evals/<id>/runs/20261017-12xx/`（synthesis.md）と `evals/index.tsv`（rubric_sha256 列を追加）。

## Phase 3 の再現: fixture のバグ (a) を test モードで

- 作業場所: scratchpad に fixture を複製した独立の git リポジトリ（KATA.md は除外）。
- 合意（前回と同じ）: 2 スライス（2026 年 2 月の月末は 28 日、2028 年は 29 日）、seam は `closingDate(invoiceDate, "end")` の単体、期待値は暦、既存のテスト一式と型検査は緑のまま、refactor は別のエージェント（opus）。
- 前回から増えた手順も通しました: 既知の正常例の較正、`--test-report` の件数、import を undefined にする監査、Close の変異テスト（Stryker の command runner）、最終判定者。

### 結果（Measured）

| スライス | 記録 |
|---|---|
| feb-end-1 | before target_failure（'2026-03-31' を返し '2026-02-28' を期待）、正常例の較正 pass、after pass、import の監査 target_failure（TypeError: closingDate is not a function）、既存一式・型検査 pass、integrated pass ×3、変異 1 件を殺す（生き残り 0） |
| feb-end-2 | 同じ形（うるう年 '2028-02-29'） |
| feb-end-refactor | plant/planted の較正 target_failure（7 件失敗）、修正前の after pass、別の opus は「変更なし」、after pass、integrated pass ×2、変異テストは「製品コードを変えていない」理由を記録 |
| check-evidence | 3 スライスとも OK。WARN 2 件（名前で絞った正常例が integrated では skipped。較正で別に pass） |
| 最終判定 | pass、confidence high、6 基準すべて 2 点、disagreements なし |

### 時刻

| 段階 | 時刻 | 所要 |
|---|---|---|
| 複製、npm ci、setup-project | 12:31:31 – 12:31:5x | 約 20 秒 |
| テスト 2 つと before ×2 | 12:31:55 – 12:32:11 | 16 秒 |
| 修正、after、import の監査、既存一式 | 12:32:11 – 12:32:40 | 29 秒 |
| refactor の較正と担当者 | 12:32:40 – 12:33:39 | 約 60 秒（打ち間違いのやり直しと担当者の 25 秒を含む） |
| Close（integrated、変異テスト、check-evidence） | 12:33:39 – 12:34:00 | 約 20 秒 |
| 返信の下書き、layout、判定 | 12:34:00 – 12:35:25 | 約 85 秒（判定 40 秒） |

合わせて約 4 分です。

### 摩擦

1. **グローバルの `core.hooksPath` があると、pre-commit フックが効かない。** この Mac は ai-review の pre-push のために `core.hooksPath=~/.git-hooks` を設定しています。setup-project.sh は警告を出しますが、利用者が自分でつなぐ必要があります。
2. **親（私）が zsh で配列を展開し損ねた。** `$OF` が単語に分かれず plant が失敗し、壊した版のまま after を記録しました（accepted=false の履歴として残り、判定には影響しません）。スキルの不具合ではありませんが、`calibrate.sh` の利用例は bash の配列を前提にしているので、Bash ツールが zsh のときに踏みます。
3. `#28` の `--include-new` は、オラクルの未追跡テストファイルを自動で通し、不要でした（狙いどおり）。

## Phase 4: SKILL.md の A/B eval（初実施）

完了条件は「今の SKILL.md（候補 A）と principles.md を読まない版（候補 B）を A/B し、judge.json がスキーマを通り、index.tsv に 1 行増える。A が負けたら原因を synthesis.md に書く」です。phase4-log の時点では実行コストを理由に先送りされていました。

### 枠組み（篠田さんと合意、2026-10-17）

- eval `implement-business-days`（fixture の (b)、土日の繰り越し）を evals/ に足しました（task.md、rubric.md、fixture.md）。
- 候補はどちらも opus です。人に質問できないので、合意済みの内容（期待値 3 つ、seam、既存一式と型検査、外部に出さない、補助なし）を依頼文に書きました。
- 盲検の例外を 2 つ合意しました。
  - 置いたスキル自体に、評価の語（test、eval、judge など）とモデル名が入っている。スキルの文面は評価される製品そのものなので、置いたスキルのディレクトリに限って許可しました。
  - CLAUDE.md と指示書の `claude`（Claude Code の指示ファイル名）。
- transcript は判定者に送らないことにしました。

### 校正（判定器を先に red にする）

正例（私が test モードで実装し、証拠と返信を付けたもの）、負例（値を 1 つしかアサートしない、red が無い、祝日・別モード・検査を足した、ラベルの無い「Done」）、空（依頼文をそのまま返したもの）の 3 点で回しました。

| rubric | 結果 | 直したこと（どれも候補を走らせる前、合意のうえ） |
|---|---|---|
| v1 | 正例が fail | 返信の冒頭の結論行（reply-format.md の Result 行）をラベルの対象外にし、Measured の根拠を artifact/ にも広げた |
| v2 | 正例が fail | 作業場所のパス（src/、.vetdd/evidence/）と判定者側のパスの対応を書き、「最後の緑」を「そのファイルを走らせた緑」に直した |
| v3 | 正例 partial → ラベルを入れ替えると pass | 正例の返信の曖昧な 1 か所にラベルを付けた（判定器でなく校正用の正例を直した） |
| v3 | 正例 pass、負例 fail、空は全基準 0。ラベルを入れ替えても同じ | 固定 |

rubric の 2 回の改訂は、どちらも rubric が vetdd 自身の返信の書式に合っていなかったためです。

### 本番（2 回）

| run | full | no-principles | 勝者 |
|---|---|---|---|
| 20261017-1459 | 2, 2, 2, 0 | 2, 2, 2, 0 | 引き分け |
| 20261017-1505 | 2, 2, 2, 0 | 2, 2, 2, 0 | 引き分け |

- 4 体とも CLAUDE.md からスキルに入りました。test モードを選び、合意値をそのままアサートしています。red→green、import の監査、変異テストを通して `check-evidence: OK` まで進み、外部の判定者の手前で `blocked` として止まりました（依頼どおり）。うち 2 体は、変異テストの生き残りを見てテストを足し、版を上げて red を取り直しました。
- 違いが出なかったのは「主張と証拠の対応」も同じで、4 体とも 0 点でした。返信の節の形は守っていますが、ラベルが付いていません（#55）。
- 結論は inconclusive です（2 回とも引き分け）。この課題では、principles.md の有無は rubric で観測できる差を生みませんでした。振る舞いは mode のファイルとスクリプトが担っています。

### 摩擦

4. **sanitize-candidates.sh に製品の語を許可する口が無い。** fixture の package-lock.json の `baseline-browser-mapping` が出所の語 `baseline` に当たり、集められませんでした。`--strip baseline` で回避しています（#54）。
5. **候補も親と同じ摩擦を踏んだ。** グローバルの core.hooksPath の警告、zsh の単語分割、反映前の編集のまま走らせた after（accepted=false）です。
6. **候補はユーザーのグローバル指示を引き継ぐ。** 2 体は日本語で返信し、📝 のまとめも付けていました。rubric は言語に依らないので、採点には影響していません。

## Phase 5 の再現: verify skill の生成と、テスト免除の変更（B 手順）

完了条件は「fixture に verify skill を生成し、Launch → Doctor → Drive → Evidence → Cleanup を 1 周して証拠を残す。テスト免除の変更（`.npmrc` の値変更）を verify で判定する流れを 1 回通す」です。前回は前者だけで、B 手順と最終判定は未実施でした。

- 作業場所: fixture の複製（既存の `.claude/` は除外）。
- 合意（前回と同じ）: CLI の 2 機能（due、usage）、due は 1 月の日付（2 月の月末はバグの教材）、node v24、サーバーなし。
- A 手順（生成）: テンプレートから SKILL.md、features 3 本、scripts 5 本を書き、期待値は README の例と `src/cli.ts` の usage 定数から取りました。較正は `--expect "closing: 2026-02-01"` で target_failure、合意の期待値で pass、cleanup の後も成果物が残ることを確かめ、skill をコミットしました。
- B 手順: `.npmrc` に `fund=false` を足しました。変更前の green（due、usage）、変更後の after、integrated はすべて pass です。変異テストと import の監査は「当てはまらない」として理由を記録しました。`check-evidence: ts-kata-verify: OK`。
- 最終判定は 3 回とも partial でした。
  1. 期待値の出どころ（README と src/cli.ts）を Measured と書いたが、そのファイルは判定者に渡っていない（返信の欠点。直した）。
  2. 返信に `.agent/...` と書いたため、judge-layout.sh が `.claude` を `.agent2` にし、パスがずれた（摩擦 8）。
  3. Attention の 1 行にパスが無い（返信の欠点）。あわせて red→green を 1 点とされた。verify の較正 red（期待値の上書き）を rubric の「合意した振る舞いの失敗」と読むかどうかが曖昧で、判定者の点が 2・2・1 と揺れた（#56）。
- 時刻: 15:08:25 開始、15:09:44 に B 手順まで完了（約 1 分 20 秒、skill の執筆を含む）。判定 3 回で 15:12:58 まで。

### 摩擦

7. **設定変更の監査が手順書に無い。** 変異テストは JS/TS が対象で、表面が読まない設定ファイルには欠陥を植えられません（#56）。
8. **返信に `.agent` と書くと `.agent2` になる。** 作者は最終的な名前を前もって知れないので、作業場所の名前で書くのが正解です。手順書に無い（#56）。
9. **verify の判定入力の組み方。** 手順書は手で組むとしていますが、judge-layout.sh で土台を組み、verify の成果物の写しを足す方が安全でした（#56）。

## Phase 6 の再現: swarm 2 単位と arena 1 回

### swarm（KATA (b) を土曜と日曜の 2 単位で）

- 前回と同じ形です。親が契約（第 3 引数、何もしない土曜・日曜の関数、`addDays` と `toUtc` の export）を先にコミットし、opus の担当者 2 体が別々の worktree で埋めました。
- 時刻: 15:14:35 に worktree を作り、担当者は 47 秒と 50 秒で終わりました。統合は 15:16:05 – 15:16:09 の 4 秒です。
- Close の変異テストで、土曜の単位に生き残りが 7 件出ました。
  - 6 件は親の範囲の誤り（変えていない `termDays` の検査の行を含めた。前回と同じ誤り）。
  - 1 件は本物の穴（分岐を「常に繰り越す」にしても気づかない）で、オプション無しの土曜の例を足し、版を 2 に上げました。
- 版 2 の red は、`calibrate.sh unfix` が「HEAD に対する変更が無い」と断ったので、plant / planted で取りました。swarm では統合の時点で修正がコミット済みなので、unfix が使えません（摩擦 10）。
- 結果: check-evidence は 2 単位とも OK、変異は土曜 8/8・日曜 4/4 を殺す、最終判定は pass（confidence high、全 6 基準 2 点）。

### arena（第 3 引数の設計を 3 人の走者で）

- 前回と同じ合意です。KATA (b)、将来の変更は祝日と「前の営業日」モード。判定器は親が先に書き、red を確かめてからコミットしました。
- 走者: opus、fable、sonnet（ランダムなレーン名。対応はローカルの統合記録にだけ残しました）。時間は 110 秒、247 秒、66 秒です。
- 今回は設計がはっきり分かれました。前回（2026-10-11）は 3 案とも同じ形でした。
  - opus: dueDate.ts の中で、モードごとの向きを表で持つ
  - fable: 日付の基本関数を calendar.ts に移し、`BusinessCalendar` のインターフェースを立てる
  - sonnet: 規則を businessDay.ts の `applyRollover` に集める
- ゲートは 3 案とも緑でした。arena rubric の合計は 10 / 11 / 8 で、opus の案が選ばれました（単純さ 2 点。fable の案は抽象が過剰として単純さ 0 点、最小の変更 1 点）。移植するものは無し。
- 勝者の変異テスト: 13 件中、10 件を殺し、3 件がタイムアウト、生き残り 0。タイムアウトは、どれも週末で歩みが終わらなくなる変異でした。
- 最終判定は pass（confidence high、全 6 基準 2 点）。
- 時刻: 15:19:35 開始、走者は 15:19:48 – 15:24:48、取り込みと並べ替えで 7 秒、arena の判定 60 秒、統合と Close と最終判定で 15:27:56 まで。合わせて約 8 分半。

### 摩擦

10. **swarm の Close で版を上げると unfix が使えない。** 修正は統合時点でコミット済みです。test.md の「版を上げたら unfix」は、swarm と arena の Close では plant / planted と読み替える必要があり、手順書に書かれていません。
11. **親が `bash -c '...'` の中にアポストロフィを書いて、コマンド全体が実行されなかった。** zsh を避けるために bash -c を使うと、今度は引用の罠を踏みます。スクリプトに書き出すか、文書は Write ツールで書くのが安全でした。
12. **変異テストの範囲を、変わっていない行まで広げた（前回と同じ誤り）。** `git diff -U0 <base>` の `@@` 行から範囲を取る、と手順書に一言あれば防げます。

## まとめ（Phase 7 の完了条件）

| 項目 | 結果 |
|---|---|
| 消して入れ直す | install.sh で入れ直し、main と一致（Measured） |
| Phase 3（test） | 再現。最終判定 pass（high） |
| Phase 4（eval の A/B） | 初実施。rubric v3 を校正し、2 回とも引き分け（inconclusive）。principles.md の有無で差は出なかった |
| Phase 5（verify） | 再現し、B 手順を初めて通した。最終判定 partial ×3（返信の欠点 2 つと rubric の曖昧さ、#56） |
| Phase 6（swarm、arena） | 再現。最終判定は両方 pass（high）。arena は前回と違い設計が分かれた |
| eval の回帰 | final-judge-dogfood は変わらず、rubric-calibration は正例が partial に（rubric の取りこぼし、#53） |
| CI | bats（Linux、macOS bash 3.2）、fixture の vitest・型検査・audit が緑、必須チェックに追加 |

完了条件は満たしたと判断します。ただし、Phase 5 の最終判定は pass に届いていません。新しく見つかった課題は Issue にしました（#50、#53〜#56）。
