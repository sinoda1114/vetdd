# 突き合わせ: pstack と mattpocock/skills

- 元資料: `research/pstack.md`（485 行）、`research/mattpocock.md`（409 行）
- 目的: vetdd（Verification / Eval / Test Driven Development）の設計に入る前に、二人の共通点・相違点・空白を 1 枚にする
- 日付: 2026-09-25

---

## 1. 二人が共通して言っていること（vetdd の土台にしてよいもの）

| # | 共通の主張 | pstack での形 | mattpocock での形 |
|---|---|---|---|
| 1 | **完了は自己申告ではなく、実物の証拠で示す** | prove-it-works（Measured / inferred / guess のラベル、決定的スクリプトが最強の証明） | diagnosing-bugs Phase 1（red になるコマンドを 1 つ名指しし、実行済みの出力を見せるまで先に進まない） |
| 2 | **red を見てから green にする。順序そのものが証明** | sequence-verifiable-units（failing test → fix の commit 順）、tdd step 4（意図した理由で落ちることを確認） | tdd「Red before green」、diagnosing-bugs Phase 5（失敗を見る → 修正 → 成功を見る） |
| 3 | **テストは振る舞いを見る。実装をなぞるテストは害** | test-behavior-not-implementation（undefined テスト、禁止 5 形） | tdd の 3 アンチパターン（implementation-coupled / tautological / horizontal slicing）、「期待値は独立した真実の源から」 |
| 4 | **悪いテストより無いテスト** | "Prefer no new test over a bad test" | 「正しい seam が無ければ、それ自体が発見」（テストを書かず記録する） |
| 5 | **観測方法を先に疑う。計測器を先に検証する** | prove-it-works「検証が失敗したら観測方法を疑う」、hillclimb「harness の感度を証明してから凍結」 | diagnosing-bugs Phase 2（ループが本当にそのバグで red になるか確認、要素を 1 つずつ削って load-bearing を確かめる） |
| 6 | **仮説を先に複数立て、反証可能な予測を書く** | bug-fix 手順 2（仮説を列挙し二分探索）、attack-the-premise | diagnosing-bugs Phase 3（3〜5 個のランク付き仮説、予測が書けないものは "vibe" として捨てる） |
| 7 | **書いた者と判定する者を分ける** | interrogate / shipping（「CI green は verdict ではない」、作者と別の agent が判定） | code-review docs（"Same context reviewing itself isn't review, it's confirmation bias"）、retro（規約の強制はレビュー側へ） |
| 8 | **指示文より構造で強制する** | encode-lessons-in-structure（lint / runtime check / script に落とし、指示文は消す）、check-plan.mjs | retro「機械的違反は決定的チェックへ、判断事項だけを文書へ」 |
| 9 | **1 単位ずつ検証可能な形で進める** | sequence-verifiable-units、hillclimb（1 変更 1 計測、keep か revert） | to-tickets の vertical slice / tracer bullet（1 スライスは単独で demo・検証可能）、tdd「One slice at a time」 |
| 10 | **サブエージェントには文脈をポインタで渡し、生出力を親に持ち込まない** | guard-the-context-window、swarm「worker の生出力は貼らない」 | implement-spec「context pointer で疎に」、research を background で |
| 11 | **人間には、実験で決められないことだけ聞く** | never-block-on-the-human、Non-negotiables（観測で決まる分岐は prototype で決める） | loop-me の Push right（checkpoint を後ろに寄せ、聞くのは 1 回・遅く・準備万端で） |

篠田さんの CLAUDE.md にある「検証を先に用意する」「計測器そのものを先に検証する」「ユーザーをテスターにしない」は、上の 1・5・11 と同じ主張です。vetdd の思想はここから書き始められます。

## 2. 二人で立場が違うこと（vetdd が選ぶ必要があるもの）

| # | 論点 | pstack | mattpocock | 備考 |
|---|---|---|---|---|
| A | **着手前の計画** | 「計画は信じない。最良の仕様はコード」。分岐は実験で決める | 最大の失敗は意図のずれ。grilling で先に詰め、seam を合意してから書く | 篠田さんの「可逆コストで計画の重さを決める」は両者の中間 |
| B | **並列** | 積極的。arena（N 案の競争）、swarm（分割・レース）、独立 worktree ごとに worker | 慎重。並列はコンテキスト分離と待ち時間の隠蔽のためだけ。実装は 1 セッション 1 チケット | 篠田さんは pstack 寄り。ただしマットさんの事故報告（同一 checkout での `--amend` 事故、stash 共有）は実害なので設計に織り込む |
| C | **複数モデル** | 中核。「second opinion は同じ prompt を別モデルへ」。判定は作者と別系統 | 使わない。"works with any model"。2 軸レビューも同一モデル | 篠田さんの `/ai-review`（Opus と Codex の並列ブラインド）は pstack 寄り |
| D | **TDD の適用範囲** | 狭い。バグ修正で安価なテスト経路があるときだけ。自動発火しない | 広い。実装の既定。ただし「100% 遵守は求めない」 | 篠田さんの「原則 TDD」はマットさん寄り。ただし遵守の事後確認が要る |
| E | **refactor の位置** | tdd に無い。Refactoring playbook が別途担当（pin を green に保ったまま） | 2026-06 に tdd から削除。code-review の仕事 | 両者とも red-green のみ。refactor を誰がいつやるかは vetdd が決める |
| F | **テストの置き場所** | 明示規定なし（既存の最も近いテスト種別を選ぶ） | 事前合意した seam のみ。「理想の seam 数は 1」 | seam 合意はマットさん固有の強い部品 |
| G | **評価の対象** | skill / prompt の変更（eval playbook）、metric（hillclimb） | 無い | 3 節参照 |
| H | **自律性** | 外部アクションも確認なしで進める | 人の checkpoint を残す（仮説提示） | 篠田さんの安全規則（送信・公開は明示許可）があるので pstack の自律性はそのまま持ち込めない |

## 3. どちらにも無いもの（vetdd が自分で設計するもの）

1. **評価駆動の永続形式。** pstack の eval playbook はブラインド化の規則は完成度が高いが、結果の保存形式（ファイル名・スキーマ・回帰セット）を定めていない。マットさんには評価の仕組み自体が無い。「評価データセットをリポジトリに置き、skill / prompt の変更ごとに回帰させる」仕組みは vetdd が最初から設計する。
2. **並列実装の安全な形。** pstack は並列を推すが、実装の並列化は「密結合な仕事は owner 1 人」と限定している。マットさんは並列実装を「No」と言う。「独立 worktree × 1 スライス 1 worker × 各 worker が自分の red テストを持つ × 統合は直列」という形は、二人の部品を組み合わせて vetdd が定義する。
3. **TDD 遵守の事後確認。** マットさんは「red を飛ばすことがある。強制はしない」と認め、pstack は tdd を自動発火させない。「red を見たことを transcript かテスト実行ログで機械的に確認する」ゲートはどちらにも無い。encode-lessons-in-structure に従えば、これは指示文ではなく check スクリプトにする。
4. **3 つの駆動を 1 つの骨格で扱う視点。** 二人とも検証・テスト・評価を別々の skill として持つ。「判定器を先に作る → 判定器を検証する → red → green → 実物で証明」という共通骨格を明示し、判定器の種類（テスト / verify スクリプト / ブラインド judge）だけを差し替える設計は、どちらにも無い。
5. **80% カバレッジのような数値規約との整合。** 二人とも「悪いテストより無いテスト」で、数値目標を持たない。篠田さんの rules は 80% を要求している。数値と品質基準のどちらを優先するかは vetdd が明文化する。

## 4. 部品として取り込む候補（優先順）

### 検証駆動
1. red-capable な 1 コマンドを、実行済み出力付きで示すまで進まないゲート（mattpocock diagnosing-bugs Phase 1）
2. tight の 4 条件: red-capable / deterministic / fast / agent-runnable（同上）
3. feedback loop 構築手段の 10 段ラダー（同上）。テストが書けない状況の次善策が決まる
4. 証拠ラベル Measured / inferred / guess と、blast-radius の確信度 5 段階（pstack）
5. create-verification-skill の Launch / Doctor / Drive / Evidence / Cleanup と feature map、「生成した skill を 1 周回して証拠が残るか確かめる」ゲート（pstack）
6. verdict に head SHA・base SHA・`git patch-id` を添え、rebase 後の再利用可否を判定（pstack shipping）

### テスト駆動
7. undefined テストと禁止 5 形（pstack test-behavior-not-implementation）。lint に落とせる
8. tautological テストの禁止、「期待値は独立した真実の源から」（mattpocock tdd）
9. 事前合意した seam でのみテストする。seam 候補には「何を捕まえ何を見逃すか、実行時間」を併記（mattpocock to-spec / tdd、docs の issue #607 を踏まえて改良）
10. failing test → fix の commit 順（pstack sequence-verifiable-units）
11. vertical slice / tracer bullet の 4 規則（mattpocock to-tickets）
12. mock はシステム境界のみ、SDK 型の個別関数で DI（mattpocock mocking.md）

### 評価駆動
13. ブラインド化の規則: 禁止語リスト、自然な prompt、transcript と成果物で採点、judge にモデル名を伏せる、2 variant は 1 judge が 1 pass（pstack eval）
14. hillclimb の計測規律: harness の感度を証明してから凍結、median of N、試行回数下限付き stop predicate、1 変更 1 計測、`decision.tsv`（pstack）
15. interrogate の lead-judgment: Act on / Consider / Noted / Dismissed、Act On は 5 件以下、Dismissed を信頼の仕組みとして示す（pstack）
16. 2 軸を別コンテキストで評価し、再ランク付けせず並べる。各指摘に根拠の引用を必須にする（mattpocock code-review）

### 並列・複数モデル
17. arena の Frame → Fan out → Cross-judge → Pick → Graft → Verify（pstack）
18. swarm の PASS / ISSUES / BLOCKED と「gap は pass ではない」（pstack）
19. 「独立した成果物を生む slice だけ親レベルで fan-out。密結合は owner 1 人」（pstack feature step 3）
20. サブエージェント brief に「直接実行し、スキル呼び出しや追加のエージェント起動をしない」を必ず入れる（mattpocock の再帰増殖バグ、50 体超・450k トークンの教訓）

### 書き方
21. 各ステップは completion criterion で終わる（clarity × demand、premature completion の防止）（mattpocock writing-for-agents）
22. leading word を繰り返し、肯定形で書き、no-op の文を削る（同上）
23. 「Delegate to other skills by path. Don't restate.」（pstack authoring-a-skill）と「Call the Skill tool with "<name>"」（mattpocock invocation.md）のどちらかに統一する

## 5. 持ち込まないもの

- pstack の Autonomy「Just do it」（外部アクションも確認なし）。篠田さんの安全規則と衝突する
- pstack の multi-phase-plan「PR ごとに 10 live lane」。Cursor クラウド VM 前提でコストが大きい。lane 数は可変にする
- mattpocock の `implement`「レビュー前に commit しない」「現在ブランチに直接 commit」。code-review が commit 済み差分しか見ない欠陥と、feature ブランチ運用との不整合
- mattpocock の「refactor を TDD から外す」をそのまま。受け皿に収束保証が無い。取り込むなら「refactor 後に全テスト再実行で green 確認」を明示する
- 英語向けの散文規則（long dash 禁止、unslop）。日本語の出力規約は `output-format.md` が正本
- Cursor 固有のメカニクス（`~/.cursor/rules/*.mdc`、Task の `readonly` / `environment: cloud`、`grok-*` slug の直接指定）

## 6. 思想を決めるために篠田さんに聞くこと

設計に入る前に決めるべき分岐です。2 節の A〜H と 3 節の空白から出しています。

1. **3 つの駆動の関係**: 「1 つの骨格＋3 つのモード」（判定器だけ差し替える）にするか、「3 つの独立した skill」にするか
2. **着手前の計画**: 可逆コストで分岐させるとして、閾値は何か（例: 単一ファイル・未マージなら即着手、スキーマ・公開 API・並列 3 worker 以上なら先に hearing）
3. **並列の既定形**: arena 型（同じ課題を N モデルで競わせる）と swarm 型（課題を分割して N worker）のどちらを既定にするか。両方なら選び方の規則
4. **複数モデルの構成**: 実装・判定・レビューに何を割り当てるか。Claude Code の Agent tool で native に選べるのは Claude 系のみで、Codex 等は外部 CLI 経由になる制約をどう扱うか
5. **TDD の適用範囲**: 「原則 TDD」の例外（config、配線、glue、単純 CRUD）を明文化するか
6. **refactor の位置**: red-green の直後に入れるか、レビュー段階に回すか
7. **カバレッジ数値**: 80% を維持するか、「悪いテストより無いテスト」に置き換えるか、両立させるか
8. **評価駆動の最初の対象**: skill / prompt の変更（pstack eval 型）、metric の改善（hillclimb 型）、アプリの振る舞い回帰（独自）のどれから始めるか
9. **配布形態**: Claude Code プラグイン（read-only、自動更新）か、`~/.claude/skills/` へのコピー（編集可）か。両方なら二重登録をどう防ぐか
10. **既存 open-pstack 移植版の扱い**: `~/.claude/plugins/marketplaces/open-pstack/` にある多モデル dispatch を再利用するか、vetdd で独自に持つか（ゼロベース方針との兼ね合い）
