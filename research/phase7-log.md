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
