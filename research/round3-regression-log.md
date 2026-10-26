# 第 3 周の修正後の回帰（2026-10-26）

判定器: Phase 7 の回帰のうち、Phase 3（test モード）と Phase 6 の swarm を clean install した版で回し直し、どちらも最終判定 pass になること。対象は round3-hits の P1〜P4 の修正（#116、#118、#119、#121）を入れた main 968dfb7 です。合意（1a）は、篠田さんと結んだ前回の Phase 3・6・7 のもの（research/phase7-log.md）を使い回しました。ゴール盤は docs/goals/round3-hits/state.yaml です。

## 入れ直し

`./install.sh`（2026-10-26 19:09、main 968dfb7）。既存の版は `~/.claude/skills-backup/vetdd-20261026-190901` に退避されました。入れた版は main の `skills/vetdd` と一致しました（`diff -rq`、Measured）。以下はすべてこの版で行いました。

## Phase 3: fixture のバグ (a) を test モードで

- 作業場所: scratchpad に fixture を複製した独立の git リポジトリ（KATA.md は除外）。
- スライスは 3 つで、合意は前回と同じです。
  - feb-end-1: 2026 年 2 月の月末は 28 日。
  - feb-end-2: 2028 年は 29 日。
  - feb-end-refactor: 別のエージェント（opus）による refactor。
  - 今回は、スライスごとに専用のテストファイルを持たせ、そのファイルに既知の正常例を同居させました。

### 結果（Measured）

| スライス | 記録 |
|---|---|
| feb-end-1 | 正常例の較正 pass、before target_failure（'2026-03-31' を返し '2026-02-28' を期待）、after pass、import の監査 target_failure（TypeError: closingDate is not a function）、既存一式・型検査 pass、integrated pass ×3、変異 1 件を殺す（生き残り 0） |
| feb-end-2 | 同じ形（うるう年 '2028-02-29'） |
| feb-end-refactor | plant / planted の較正 target_failure（7 件失敗）、refactor 前の after pass、opus の担当者は「変更なし」、after pass、integrated pass ×2、変異テストは mutate-ranges.sh の exit 3（空の refactor）に従い理由を記録 |
| check-evidence | 3 スライスとも OK、exit 0。WARN 2 件（名前で絞った正常例が integrated では skipped。前回と同じ） |
| 最終判定 | pass、confidence high、6 基準すべて 2 点、disagreements なし。judge.json.meta.json に rubric_sha256 が入った（#116 の確認） |

### 時刻

| 段階 | 時刻 | 所要 |
|---|---|---|
| 複製、npm ci、setup-project | 19:09:46 – 19:10:20 | 約 34 秒 |
| テスト 2 つ、合意の記録、正常例の較正、before ×2 | 19:10:20 – 19:10:47 | 27 秒 |
| 修正、after、import の監査、既存一式・型検査 | 19:10:47 – 19:11:17 | 30 秒 |
| refactor の較正と担当者 | 19:11:35 – 19:12:38 | 約 60 秒（担当者 30 秒） |
| Close（integrated、範囲、変異テスト、check-evidence） | 19:12:38 – 19:13:40 | 約 60 秒（下の摩擦 2・3 を含む） |
| 返信の下書き、layout、判定 | 19:13:40 – 19:15:30 | 約 110 秒（判定 51 秒） |

合わせて約 5 分 45 秒です。前回の約 4 分より長いのは、親の書き損じと範囲の広げ直し（下の摩擦 2・3）のためです。

## Phase 6: KATA (b) を swarm の 2 単位で

- 形は前回と同じです。
  - 親が契約を先にコミットしました。契約は次の 3 つです。
    - 第 3 引数 `{ rollover }`
    - 何もしない `rollSaturday`・`rollSunday`
    - `addDays`・`toUtc`・`CalendarDate` の export
  - そのうえで、opus の担当者 2 体が別々の worktree で同時に埋めました。
- 今回は各単位のオラクルに、最初から 3 ケースを入れました。
  - 土曜（日曜）に当たる例
  - オプション無しで土曜（日曜）に当たる例
  - 平日の例

  前回は Close の変異テストで「常に繰り越す」変異が生き残り、版を上げて plant / planted で取り直しました（Phase 7 の摩擦 10）。オプション無しの例を初めから入れておくことで、この取り直しをなくしました。

### 結果（Measured）

| 項目 | 記録 |
|---|---|
| sat-rollover | before target_failure（'2026-05-30' を返し '2026-06-01' を期待）、after pass、import の監査 target_failure、既存一式・型検査 pass、統合後の integrated pass、変異 3 件を殺す（生き残り 0） |
| sun-rollover | 同じ形（'2026-08-30' を返し '2026-08-31' を期待） |
| 変異の範囲 | mutate-ranges.sh が統合した木で出した範囲をそのまま使った（土曜 `saturday.ts:1-4,8-9`、日曜 `sunday.ts:1-3,7-7`）。契約のコミットにあった行（doc コメント、関数の宣言、閉じ括弧）は正しく外れた。前回は親が手で範囲を取って変わっていない行を含めた（Phase 7 の摩擦 12）が、#119 の後は再発しない |
| check-evidence | 2 スライスとも OK、WARN なし、exit 0 |
| 最終判定 | 1 回目 partial（下の摩擦 4）、返信の下書きを直した 2 回目 pass（confidence high、6 基準すべて 2 点、disagreements なし） |

### 時刻

| 段階 | 時刻 | 所要 |
|---|---|---|
| 複製、npm ci、setup-project | 19:16:02 – 19:16:03 | 約 1 秒（npm のキャッシュ済み） |
| 契約を書いてコミット、worktree 2 つ、合意の記録 | 19:16:03 – 19:16:41 | 約 38 秒 |
| 担当者 2 体（同時） | 19:16:50 – 19:18:19 | 約 90 秒（自己申告は土曜 59 秒、日曜 53 秒） |
| 順に統合（npm ci、check、merge、remove、integrated、--before-close） | 19:18:47 – 19:18:56 | 9 秒 |
| Close（integrated、範囲、変異テスト、check-evidence） | 19:19:09 – 19:19:19 | 10 秒 |
| 返信の下書き、layout、判定（1 回目） | 19:19:19 – 19:21:23 | 約 2 分（判定 78 秒） |
| 下書きの手直しと判定（2 回目） | 19:21:23 – 19:23:09 | 約 105 秒（判定 53 秒） |

合わせて約 7 分、判定の取り直しを除くと約 5 分半です。前回（swarm 単独で約 4 分、変異の取り直しを含む）と同じ程度で、Close は取り直しが無いぶん短くなりました。

## 摩擦

1. **グローバルの `core.hooksPath` があると、pre-commit フックが効かない**（Phase 7 の摩擦 1 と同じ）。setup-project.sh は警告と、つなぐための 1 行を出します。今回はコミットしない作業だったので影響はありませんでした。
2. **自動で取った範囲に変異が 1 つも無かった（Phase 3）。** mutate-ranges.sh は修正した 2 行（`src/dueDate.ts:50-51`、コメントと演算子の無い return）を正しく出しました。Stryker はそこに変異を作らず、規則 10c が「関数の閉じ括弧まで広げよ」と FAIL を出しました。案内どおり 49-52 に広げると、関数本体を空にする変異 1 件が生まれて殺されました。手順書の「A range must hold whole statements」のとおりで、仕組みは止まらず正しく導きました。ただ、親が 1 手かける場面です。
3. **親（私）の書き損じが 2 回。** 補助スクリプトを複製の中に置いてしまい、後で外に出しました。mutate-ranges.sh はそれを「スライスが消したファイル」として stderr に出し、範囲から外しました。また、補助スクリプトで変数を定義し忘れ、1 回目の変異テストが走らずに終わりました。どちらも記録には残っていません（Measured: meta.json に mutation の run が無いことを確かめてから回し直した）。スキルの不具合ではありません。
4. **swarm の 1 回目の判定は partial でした。** 原因は 2 つです。
   - 1 つ目は私の書き損じで、Oracle 節の箇条書き 2 行にラベルがありませんでした。
   - 2 つ目は判定者の読み違いです。判定者は「土曜の変異の範囲が、変更した定数の行を外している」としましたが、範囲 `1-4` には定数の行（4 行目）が入っています（Measured: 011-mutation.json の config.mutate と収めた全文）。
   - rubric は変えず、返信の下書きだけを直しました。ラベルを付け、範囲の内訳を Attention に根拠付きで書いた結果、2 回目は pass でした。判定者の行番号の読み違いは前回までに見ていない形なので、次に rubric を見直すとき（#95）の材料として記録します。

## まとめ

| 項目 | 結果 |
|---|---|
| clean install | install.sh で入れ直し、main 968dfb7 と一致（Measured） |
| Phase 3（test） | 再現。最終判定 pass（high、全 6 基準 2 点） |
| Phase 6（swarm） | 再現。最終判定 pass（high、全 6 基準 2 点）。1 回目の partial は返信の書き損じと判定者の読み違い |
| P1（#119）の実物での確認 | mutate-ranges.sh が test モードの範囲、空の refactor の exit 3、swarm のマージ越しの範囲を正しく出した |
| P2（#121） | この回帰では 10a の取り直しの場面は出なかった（監査はすべて 1 回目で捕まえた）。確認は bats のテストによる |
| P3（#118） | この回帰の外。CI の fixture ジョブと bats-bash32 が本物の vitest・tsc・Stryker を回している |
| P4（#116） | 2 回の判定とも judge.json.meta.json に rubric_sha256 が入った（Measured） |

第 3 周の修正の後も、vetdd の test モードと swarm は実物の fixture で最後まで回り、別系統の判定者が pass を出しました。完了条件は満たしたと判断します。
