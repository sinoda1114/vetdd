# Phase 4 実施記録（2026-09-26）

## 成果物（`feat/eval`、`feat/entry` から分岐）

- インターフェース: `modes/eval.md`、`references/judge-prompt.md`、`references/final-judge-rubric.md`、`schemas/verdict.schema.json`、`evals/README.md`、`evals/index.tsv`
- スクリプト: `scripts/{check-blind.sh, sanitize-candidates.sh, judge.sh, check-verdict.sh}`、`scripts/lib/{blind-words.sh, validate-json.mjs}`
- テスト: `tests/{check-blind, sanitize-candidates, judge, check-verdict}.bats`（bats 全 129 件 pass、Measured）
- 証拠: `.vetdd/evidence/phase4/`（calibration target_failure → after pass、`check-evidence.sh phase4` は OK、Measured）

## 統合時に見つけて直したもの

**judge 側の blind 検査が必ず落ちる設計だった。** 候補側の禁止語リスト（`test`、`eval` …）を judge の入力にも適用していたが、TDD の成果物にはテストファイルの diff が必ず含まれる。judge が見てはいけないのは出所（variant / baseline / winner）とモデル名であって「テスト」ではない。`check-blind.sh --profile judge` を追加（bats 2 件、RED → GREEN）し、`judge.sh` と `eval.md` 手順 5 を合わせた。

## 未完（blocked）

**本物の codex による rubric 校正（eval.md 手順 2）が実行できない。** 正例 c1（before red → after pass、証拠パス付きの reply）と負例 c2（red 無し、「verified」の自己申告のみ）の手作りペアを scratchpad に用意し `judge.sh` を実行したが、codex が次の順で失敗した（Measured、2026-09-25 23:23〜23:25 UTC）。

1. WebSocket の再接続に 5 回失敗し、HTTPS へフォールバック
2. `401 Unauthorized: Incorrect API key provided`（キーの値は伏せる）（URL は `chatgpt.com/backend-api/codex/responses`）

`codex login status` は "Logged in using ChatGPT"、`auth.json` の `auth_mode` は `chatgpt`、`last_refresh` は 23:25 UTC。同じ `codex exec` を使う `/3rd-review` は同日 15:34 UTC まで動いていた。ChatGPT のトークンが拒否され、別の認証情報へフォールバックしている疑いがあった（詳細は記録しない）。認証情報は AI が触らない方針のため、ユーザーの対応待ち。`--output-schema` の実挙動もこのため未検証（guess のまま）。

解除条件: `codex exec` が 200 を返すこと。確認コマンドは `printf 'Reply OK' | codex exec -s read-only --skip-git-repo-check -m gpt-6-sol -o /tmp/ok.txt -`。

## サブエージェントが仕様から逸脱した点（受け入れ済み）

- `validate-json.mjs` は ajv を使わない自前実装（導入先 `~/.claude/skills` に node_modules が無いため）。ajv との一致テストで担保
- `check-blind` は `.git` もスキップ。単語一致は「前が英数字でない、後ろが英字でない、複数形 s は許容」。`_` は区切り
- `sanitize` はファイル名・ディレクトリ名も伏せる（`.claude/` → `.[redacted]/`）
- `judge.sh` の終了コード: 2 = 既存 rubric と不一致、3 = codex 未導入/未ログイン、4 = blind 検査ヒット、5 = verdict 検査失敗、6 = codex exec 失敗
- 判定メタ（model / effort / invoked_at / family）は `<out>.meta.json` に分離（schema が additionalProperties: false のため）

## 申し送り

- codex 復旧後: 校正ペアで judge.sh を実行 → `--output-schema` の挙動確認 → 校正が c1 > c2 になることを確認 → eval `implement-business-days` で SKILL.md の A/B（Phase 4 完了条件）
- `/ai-review` も codex を使うため、同じ障害で止まる
- `sanitize` は transcript.jsonl と variants.json の対応を扱わない。transcript の sanitize は Phase 4 の A/B 実行時に足す

## 追記: codex 復旧後（2026-09-26 08:45 JST〜）

1. **本物の codex で `--output-schema` が 400 を返した。** `invalid_json_schema: 'uniqueItems' is not permitted`（Measured）。サブエージェントが guess として残した懸念が的中。verdict を strict 互換の配列形式に変え（`scores: [{label, score, evidence}]`、`verdicts: [{label, verdict}]`）、strict が表現できない検査（ラベル重複、1 ラベル 1 スコア、空の引用）は `check-verdict.sh` に移した。`tests/verdict-schema.bats` がスキーマの strict 逸脱（禁止キーワード、開いた object、全 property を required にしていない object）を検出する
2. **rubric 校正が通った。** 正例 c1 = 2/2（pass）、負例 c2 = 0/0（fail）、私の事前採点と完全一致。記録は `evals/rubric-calibration/runs/20260926-0930/`、index に 1 行
3. judge の出力を `<out>.log` に保存し、失敗時だけ末尾を表示する形に変更（bats 2 件、RED → GREEN）
4. bats 全 136 件 pass、`check-evidence.sh phase4` OK（Measured）

## Phase 4 の残り

完了条件の「SKILL.md の A/B eval」は未実施。候補 2 体（SKILL.md あり / principles.md を読まない版）に fixture の機能 (b) を実装させ、judge で比較する。実行コストが大きいので、着手前にユーザーの判断を仰ぐ
