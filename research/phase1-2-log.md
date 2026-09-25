# Phase 1・2 実施記録（2026-09-26）

## 結果

| Phase | 成果物 | 判定器 | 結果 |
|---|---|---|---|
| 1 証拠の仕組み | `skills/vetdd/scripts/{evidence.sh, check-evidence.sh, setup-project.sh, hooks/pre-commit, lib/}`、`schemas/evidence.schema.json`、`tests/*.bats` | bats 78 件 | 全 pass（Measured） |
| 2 fixture | `fixtures/ts-kata/`（TS + vitest + tsx CLI、意図的なバグ 1、未実装機能 1、答えは `KATA.md`） | vitest 9 件、typecheck、audit、CLI 出力 | 全 pass、CLI は仕様どおり誤答 `closing: 2026-03-31`（Measured） |

統合後の証拠: `.vetdd/evidence/{phase1,phase2}/`、`check-evidence.sh` が両方 `OK`（Measured、gitignore のため未コミット）。

## 統合時に判定器が見つけたもの

1. **evidence.sh のバグ（実バグ）。** コマンド引数を `jq --args "$@"` で渡していたため、`npm --prefix fixtures/ts-kata test` の `--prefix` を jq がオプションとして解釈し、run の記録に失敗した。bats テストを 1 件追加して RED を確認し、引数を NUL 区切りで JSON 配列にしてから `--argjson` で渡す形に修正して GREEN（78 件）。サブエージェントの 77 件のテストは `sh test.sh` のような単純なコマンドしか使っておらず、盲点だった
2. **私自身の原則 7 違反。** worktree `vetdd-evidence` の `.vetdd/` を main に回収する前に worktree を削除し、phase1 の校正 red の履歴を失った。check-evidence が rule 1（red が無い）で FAIL にして検出した。校正 red を取り直して回復

## 教訓（後続フェーズへ）

- **Phase 6（並列）**: worktree の撤去前に `.vetdd/evidence/<slice>/` を main へコピーする手順を `parallel/swarm.md` と `worktree.sh remove` に組み込む。原則 7 の文言だけでは親（私）が守れなかったので、構造で強制する（原則 9）
- **Phase 3（入口）**: 統合後の `integrated` 記録と `check-evidence.sh` の実行を、完了報告の前の固定手順にする
- **Phase 7（配布）**: この Mac は `core.hooksPath=~/.git-hooks` が global に設定されているため、`setup-project.sh` が置くプロジェクトローカルの pre-commit は動かない（setup は警告を出す）。`~/.git-hooks/pre-commit` から chain する案内を README に書くか、`setup-project.sh` に `--chain-global` を足す
- **evidence.sh の校正 red の取り方**: 判定器の対象（scripts、src モジュール）を一時的に退避して赤にする方法は、対象が「無い」ことしか検証しない。狙った欠陥で赤になることの校正は、Phase 3 で fixture のバグ (a) を使って本来の形で行う

## サブエージェントが仕様から逸脱した点（受け入れ済み）

- tree_hash: `git add -A . ':!.vetdd'` は `.vetdd/` が gitignore 済みだと失敗するため、`git add -A .` の後に一時 index から `git rm -r --cached .vetdd` する方式
- schema 検証: `ajv-cli@5.0.0` に high の audit 指摘があったため `ajv@8.20.0` ＋ 20 行のヘルパー
- テストの置き場: root `tests/`（plan §3 は `skills/vetdd/tests/`）。配布物（`skills/vetdd/`）にテストを含めない方が cp で導入しやすいので root を採用
- `--keep`（`.vetdd/` のコミット）は未実装。必要になったときに足す
- exit 126/127 は infrastructure_error 扱い（打ち間違いを red に数えない）
- fixture の数値の締め日は 1〜28 に制限（月末は `"end"`）
