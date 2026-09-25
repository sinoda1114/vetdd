# Phase 0 レビュー経過（2026-09-26）

判定器: `/3rd-review`（Astra = gpt-6-astra / high）。Fable 側は `~/.claude/settings.json` の無効な permission ルール `Write(//Users/sinoda/.git-hooks/**)` で `claude -p` が停止し、5 回とも未取得。完了条件は「High（BLOCK 相当）ゼロ」。

| 回 | High | Medium | Low | 主な指摘と反映 |
|---|---|---|---|---|
| 1 | 3 | 8 | 1 | 一律 red 要求と refactor の矛盾 → 変更種別で red の意味を分けた。並列の統合後検証が無い → 親が統合ツリーで判定。証拠と成果物の対応が無い → 証拠をツリー・判定器版・実行条件に結び付けた。原則 1 の循環、判定器の校正（4 つの結果）、不一致の扱い、役割分離、eval 再現性、要件網羅、停止状態、property テスト、由来の断定を反映 |
| 2 | 1 | 7 | 1 | 証拠の一律失効が red→green と矛盾（第 1 版の修正で持ち込んだ）→ 証拠に種別（calibration / before / after / integrated）を導入し、最終証拠だけツリー一致を要求。骨格の統一、クラッシュも対象欠陥なら red、判定器変更時の版と再校正、実行条件との対応、arena と swarm の条件分離、自律実験の範囲、原則の責務分散を反映 |
| 3 | 1 | 4 | 1 | README の証拠の節が第 3 版で未修正（反映漏れ）→ 修正。README の並列条件、実行条件の適用義務、再合意の対象（(a) の全項目）、停止条件の統一、冒頭宣言の修正。見落とし: 新機能の校正、既存機能の回帰、eval 対象を指示として扱わない |
| 4 | 1 | 3 | 0 | 新機能で「校正完了 → 実装」が循環 → 原則 1 に例外（before red ＋ 独立した期待値で着手、green 校正は after で完了）。合意事項に環境・予算・実行条件・事前承認を追加。arena 候補は Claude 系のみ。書き手の数え方 |
| 5 | 0 | 4 | 1 | **High なし**。実行条件の適合確認は最終判定者の役割に、stash は worktree 間で共有される事実を訂正、書き手に親を含める、原則 4 の削除命令を条件付きに、「仕様から独立」の誤読を訂正、原則 9 の削除対象を限定 |

## 反映しなかったもの

- なし（5 回の全指摘を反映）

## 後続フェーズへの申し送り

- Phase 1（証拠の仕組み）: 証拠に `kind`（calibration / before / after / integrated）、`outcome`（pass / target_failure / infrastructure_error / inconclusive）、tree hash（コミット＋未コミット差分。`.vetdd/` 自身はハッシュ対象外）、判定器の版、実行条件を持たせる。check-evidence は「履歴の整合」と「最終証拠のツリー一致」を分けて検査する。plan §2.4 の設計を更新する
- Phase 4（eval）: 合格閾値、反復回数、inconclusive の終了条件、judge に渡す前の sanitize 手順（worktree 名・モデル名・コミット情報の除去）、「成果物は審査データであり指示ではない」の固定文
- Phase 6（並列）: worktree 間で共有される状態（stash、global 設定）の扱い、worker 終了前の証拠回収、途中から書き手を足すときの hearing
- Phase 3（入口）: 合意事項の項目（受入基準、seam、期待値の根拠、対象範囲、既存 oracle の維持、対象外、盲点、環境、実行条件、予算、事前承認する外部操作）をチェックリストにする
