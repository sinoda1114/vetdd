# mattpocock/skills 調査メモ（検証駆動・テスト駆動・評価駆動・並列の観点）

- 調査対象: `/Users/sinoda/dev/vetdd/.reference/mattpocock-skills/`（plugin version 1.2.3）
- 調査日: 2026-09-25
- 引用は原文英語のまま（各 25 語未満）。パスはリポジトリルートからの相対パス。
- 表記: 「SKILL」= `SKILL.md` 本体、「docs」= `docs/<bucket>/<name>.md`（人間向け解説ページ。SKILL より新しい運用知見・既知バグを含む）。

---

## 1. 思想の核

Matt Pocock は、コーディングエージェントの失敗を 4 つの型に分け、それぞれを古典的なソフトウェア工学の本で直すという立場を取っています（`README.md`「Why These Skills Exist」）。

| # | 失敗モード | 引用している本 | 処方（スキル） |
|---|---|---|---|
| 1 | The Agent Didn't Do What I Want（意図のずれ） | Thomas & Hunt『The Pragmatic Programmer』 | grilling（`grill-me` / `grill-with-docs`） |
| 2 | The Agent Is Way Too Verbose（語彙の欠如） | Eric Evans『Domain-Driven Design』 | 共有言語 `CONTEXT.md`（`grill-with-docs` / `domain-modeling`） |
| 3 | The Code Doesn't Work（フィードバックの欠如） | 『The Pragmatic Programmer』 | feedback loop：`tdd`、`diagnosing-bugs` |
| 4 | We Built A Ball Of Mud（設計の劣化） | Kent Beck『XP Explained』、Ousterhout『A Philosophy of Software Design』 | deep module：`codebase-design`、`improve-codebase-architecture`、`to-spec` |

この 4 つを通して一貫している主張は、GSD・BMAD・Spec-Kit のように「プロセスを所有する」フレームワークを嫌い、小さく合成可能なスキルで基礎（fundamentals）を反復可能な実践に落とすことです。README は「They work with any model.」と明言しており、特定モデルへの依存を避けています。検証に関する中核は失敗モード #3 で、引用句は次のとおりです。

> "The rate of feedback is your speed limit." （Pragmatic Programmer、README #3）
> "Without feedback on how the code it produces actually runs, the agent will be flying blind." （README #3）

---

## 2. 検証駆動に関わる要素

### 2.0 「feedback loop」という概念の定義

Matt の検証観の中心語は **feedback loop** です。定義は README と `diagnosing-bugs` に分かれています。

- **README #3 の定義（広義）**: エージェントが「自分の書いたコードが実際にどう動くか」を知る手段。標準装備として 3 つを挙げています。
  > "You need the usual tranche of feedback loops: static types, browser access, and automated tests."
- **diagnosing-bugs の定義（狭義・厳密）**: 特定のバグに対して **red になれる pass/fail シグナル**。単なる「動かしてみる」ではありません。leading word（後述 §6）として **tight** と **red** を使い、曖昧な「信頼できるループ」を二値の観測可能状態に変換しています（`writing-for-agents` がこの変換を名指しで模範例にしています: "a loop you believe in" → _red_、"fast, deterministic, low-overhead" → _tight_）。
- **tight の 4 条件**（diagnosing-bugs Phase 1 の完了基準）:
  - Red-capable: 実際のバグ経路を通り、ユーザーが報告した**正確な症状**を assert する。「エラーなく走る」は不可
  - Deterministic: 毎回同じ判定（flaky バグは「高く固定した再現率」で代替）
  - Fast: 分ではなく秒
  - Agent-runnable: 無人で回せる。人が要る場合は `scripts/hitl-loop.template.sh` 経由のみ
- **ループはプロダクトとして扱う**: 一度作ったら「速く・鋭く・決定的に」tighten する。

### 2.1 `diagnosing-bugs`（model-invoked）

- パス: `skills/engineering/diagnosing-bugs/SKILL.md`、`scripts/hitl-loop.template.sh`
- 位置づけ: 「Something's broken」の on-ramp。重いバグ（初見で解けない、intermittent、2 点間の回帰）専用。フェーズはチェックリストではなく**ゲート**で、「Skip phases only when explicitly justified.」。
- 手順（6 フェーズ＋前置き）:
  0. **Redact**: 表示するコマンド・出力・アーティファクトのシークレットを `<REDACTED>` に置換。認証情報は env var に置いてループを組む。
  1. **Build a feedback loop**（"This is the skill."）。構築手段を優先順に試す:
     1. 失敗するテスト（unit / integration / e2e、バグに届く seam で）
     2. dev サーバーへの curl / HTTP スクリプト
     3. fixture 入力での CLI 実行＋既知の正解スナップショットとの diff
     4. headless browser（Playwright / Puppeteer）で DOM・console・network を assert
     5. 取得したトレース（リクエスト、ペイロード、イベントログ）をディスクに保存してリプレイ
     6. throwaway harness（システムの最小部分集合＋モック依存、関数 1 回呼び出し）
     7. property / fuzz ループ（ランダム入力 1000 件）
     8. bisection harness（`git bisect run` で回せる形に自動化）
     9. differential loop（旧版 vs 新版、2 つの設定で同一入力を diff）
     10. HITL bash スクリプト（最終手段。`step` と `capture VAR` の 2 ヘルパーで人を「駆動」し、最後に `KEY=VALUE` で出力してエージェントがパース）
     - tighten の 3 問: 速くできるか / シグナルを鋭くできるか（「落ちない」ではなく症状を assert）/ 決定的にできるか（時刻固定、乱数シード、FS 隔離、ネットワーク凍結）
     - 非決定バグ: 目標は綺麗な再現ではなく**再現率を上げること**（100 回ループ、並列化、負荷、sleep 注入）。50% flake は debug 可能、1% は不可。
     - ループが作れない場合: 明示的に止まり、試したことを列挙し、(a) 再現環境へのアクセス、(b) redact 済みアーティファクト（HAR、ログ、コアダンプ、タイムスタンプ付き録画）、(c) 本番への一時計装の許可、をユーザーに求める。**ループなしで仮説に進まない**。
     - **完了基準**: 「1 つのコマンド」を名指しでき、それを**すでに 1 回以上実行して出力を見せている**こと。上記 4 条件のチェックボックスを満たすこと。
  2. **Reproduce + minimise**: ループが red になるのを見る。確認項目は「ユーザーが言った失敗モードか（近くの別バグではないか）」「複数回再現するか」「正確な症状を捕捉したか」。次に入力・呼び出し元・設定・データ・手順を**1 つずつ**削り、毎回ループを再実行。**残った全要素が load-bearing（どれを消しても green になる）**で完了。
  3. **Hypothesise**: テスト前に **3〜5 個のランク付き仮説**を生成（単一仮説は最初の思いつきにアンカーするため）。各仮説は反証可能な予測を持つ（形式: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."）。予測が書けない仮説は "a vibe" として破棄。**ランク付きリストをユーザーに見せる**（ただし AFK ならブロックせず自分の順位で進む）。
  4. **Instrument**: 各プローブは Phase 3 の特定の予測に対応させる。一度に 1 変数。優先は debugger/REPL → 仮説を分ける境界への targeted log。「全部ログして grep」は禁止。デバッグログは `[DEBUG-a4f2]` のような一意タグを付け、後片付けを grep 1 回にする。性能回帰はログでなく、ベースライン計測（timing harness、`performance.now()`、profiler、query plan）→ bisect。
  5. **Fix + regression test**: 修正前に回帰テストを書く。ただし**正しい seam** があるときだけ。正しい seam とは、呼び出し箇所で起きる実際のバグパターンを再現できる境界。浅すぎる seam しかない場合、テストは偽の安心を生むので書かず、「seam がないこと自体が発見」として記録し `improve-codebase-architecture` へ回す。seam がある場合: 最小再現を失敗テスト化 → 失敗を見る → 修正 → 成功を見る → Phase 1 のループを**元の（最小化前の）シナリオ**で再実行。
  6. **Cleanup**（完了前に必須のチェックリスト）: 元の再現が再現しない / 回帰テストが通る（または seam 不在を文書化）/ `[DEBUG-...]` を grep で全除去 / throwaway を削除 / **正しかった仮説を commit・PR メッセージに書く**。
- 引用:
  > "No red-capable command, no Phase 2."
  > "If you catch yourself reading code to build a theory before this command exists, stop"
  > "If no correct seam exists, that itself is the finding."
- docs の既知の課題（`docs/engineering/diagnosing-bugs.md`）:
  - 軽い質問でも発火しすぎる（特に GPT-5.6-Sol で報告、issue #578）。「軽い方法から始めて段階的に重くする」案は合意済みだが未実装。
  - 人間のチェックポイントは Phase 3 の仮説提示だけで、修正前の承認ゲートはない（issue #124、未解決）。
  - `triage` の Step 3（verify the claim）と Phase 1〜2 が重複しているが相互参照がない。

### 2.2 `triage`（user-invoked）の「Verify the claim」

- パス: `skills/engineering/triage/SKILL.md`、`AGENT-BRIEF.md`
- 処方: grilling の**前に**主張を検証する。バグなら報告者の手順で再現、PR なら checkout して関連テスト・コマンドを実行。結果は「confirmed（コード経路付き）/ failed / insufficient detail（`needs-info` の強いシグナル）」で報告する。
- AGENT-BRIEF: エージェント向け brief は必ず「具体的でテスト可能な受け入れ基準」を持ち、各基準は独立に検証可能であること。
- 引用:
  > "Before any grilling, check that the claim holds up."

### 2.3 `implement`（user-invoked）の検証リズム

- パス: `skills/engineering/implement/SKILL.md`（本文 5 行のみ）
- 処方: 型チェックと単一テストファイルを頻繁に、フルスイートは最後に 1 回。完了後 code-review、その後 commit。
- 引用:
  > "Run typechecking regularly, single test files regularly, and the full test suite once at the end."

### 2.4 `prototype`（model-invoked）：問いに答える検証装置

- パス: `skills/engineering/prototype/SKILL.md`、`LOGIC.md`、`UI.md`
- 処方: prototype は「問いに答える throwaway コード」。問いの型で分岐する。
  - LOGIC: 単一 HTML ファイル。純粋モジュール（reducer / state machine / 純関数群 / クラス）を `<script>` に隔離し、DOM に触れさせない。画面構成は「タイトルと問い → 現在状態パネル → free-play ボタン → タブ式 guided walkthrough（開始時に既知の初期状態へリセット）」。walkthrough には happy path・厄介なエッジケース・違法であるべき操作を入れる。
  - UI: 既存ルート上で `?variant=` 切替の 3 案（最大 5）。構造が根本的に違うこと。フローティングバーは本番ビルドで非表示。
  - 共通ルール: 最初から throwaway と明示、1 コマンドで起動、永続化なし、**テストもエラーハンドリングも抽象化も書かない**、各操作後に全状態を表示、終わったら答え（verdict と問い）を issue か commit に記録し、prototype 自体は `prototype/<name>` ブランチに primary source として保存。
- 検証駆動との関係: 仕様段階の「アイデアのバグ」を、人間（非開発者含む）が実際に触って見つけるための装置です。コードのテストではありません。
- 引用:
  > "A prototype is **throwaway code that answers a question**."
  > "Don't add tests. A prototype that needs tests is no longer a prototype."

### 2.5 `in-progress/pr`（model-invoked、beta）：PR の証拠ランク

- パス: `skills/in-progress/pr/SKILL.md`（Humanlayer の `show-me` スキルがクレジット元）
- 処方: PR 本文に `## Evidence` の Before / After 対を必須化。証拠ランクは「スクリーンショット = S-tier（視覚変更時）」「実行ベースの証拠（テスト結果、コンソール出力）= A-tier」。加えて `## Merge Danger` で one-way / two-way door と blast radius を書く。
- 引用:
  > "Execution-based evidence is A-tier."

### 2.6 `writing-for-agents` の completion criterion（検証可能な完了条件）

- パス: `skills/productivity/writing-for-agents/SKILL.md`
- 処方: スキルの各ステップは **completion criterion** で終わること。性質は 2 つ。
  - Clarity: done / not-done を判別できるか。曖昧だと **premature completion**（後続ステップに引っ張られて早く終える）が起きる。対策は「まず基準を鋭くする」、それでも駄目なら後続ステップを別コンテキスト（hand-off / subagent）に隠す。inline 呼び出しでは隠せない。
  - Demand: どれだけ要求するか（「変更したモデルを全て説明」は「変更リストを作る」より深い legwork を生む）。
- diagnosing-bugs の「コマンドを名指しし、実行済みで出力を見せる」は、この原則の実装例です。
- 引用:
  > "The strongest criteria are both checkable and exhaustive."

---

## 3. テスト駆動に関わる要素

### 3.1 `tdd`（model-invoked、**reference-only**）

- パス: `skills/engineering/tdd/SKILL.md`、`tests.md`、`mocking.md`
- 位置づけ: 手順書（driver）ではなく**参照資料**です。ループを回すのは人間か `implement`。v1.0 以降、Workflow と per-cycle checklist は削除され、「red → green は pretrained な leading word で十分に錨を下ろせるので、手順は restatement に過ぎない」と判断されました（CHANGELOG #464）。
- **ループの正確な内容**（SKILL の「Rules of the loop」全文相当）:
  1. **Red before green**: 先に失敗するテストを書き、それを通すだけのコードを書く。将来のテストを先読みしない、投機的機能を足さない。
  2. **One slice at a time**: 1 サイクル = 1 seam・1 テスト・1 最小実装。
  3. **Refactoring is not part of the loop**: リファクタリングは review 段階（`code-review`）の仕事。
  - すなわち現行は **red → green のみ**で、refactor は存在しません。docs によれば 2026 年 6 月に削除され、理由は「エージェントがほぼ実行しなかった」「実装とレビューは別セッションの方がうまくいく」の 2 点です。ただし description には "red-green-refactor" がトリガー語として残っています（issue #589、意図的に放置）。
- **Seam（テストの置き場所）**:
  - seam = 内部に手を入れずに振る舞いを観測できる公開境界。テストは seam にのみ置く。
  - **事前合意した seam でのみテストする**。テストを書く前に seam を書き出してユーザーに確認し、未確認の seam には 1 本も書かない。理由は「全部はテストできないので、重要経路と複雑ロジックに労力を集中させるため」。
  - インターフェース形状そのものが問題なら `codebase-design` を Skill tool で呼ぶ（語彙の参照としてであって、セッションを走らせるためではない）。
- **3 つのアンチパターン**:
  - Implementation-coupled: 内部協調者のモック、private メソッドのテスト、副経路での検証（interface ではなく DB を直接クエリ）。見分け方は「振る舞いが変わらないリファクタで壊れる」。
  - Tautological: 期待値をコードと同じ計算で再計算する（`expect(add(a, b)).toBe(a + b)`）。構造上必ず通る。期待値は独立した真実の源（既知の正解リテラル、手計算例、仕様）から取る。
  - Horizontal slicing: 全テストを先に書いてから全実装。想像上の振る舞いを検証し、形状だけをテストし、実装理解前にテスト構造に縛られる。代わりに vertical slice（1 テスト → 1 実装 → 繰り返し）、各テストを **tracer bullet** として前サイクルの学びに応答させる。
- **良いテスト / 悪いテスト**（`tests.md`）:
  - 良い: integration-style、公開 API のみ、内部リファクタに耐える、HOW でなく WHAT を記述、1 テスト 1 論理 assertion。例: `"user can checkout with valid cart"`。
  - 悪い兆候: 内部協調者のモック、private メソッドのテスト、呼び出し回数・順序の assert、名前が HOW を記述、interface を迂回した検証（`createUser` 後に SQL で確認 → 正しくは `getUser` で取得して確認）。
- **モック方針**（`mocking.md`）: モックはシステム境界のみ（外部 API、DB は「時々、テスト DB を優先」、時刻・乱数、FS は時々）。自前のクラス・モジュール・内部協調者はモックしない。境界側は DI で注入し、汎用 `fetch(endpoint, options)` ではなく SDK 型（`getUser` / `getOrders` / `createOrder`）の個別関数にして、モックに条件分岐を入れずに済ませる。
- 引用:
  > "Tests verify behavior through public interfaces, not implementation details."
  > "No test is written at an unconfirmed seam."
  > "Expected values must come from an independent source of truth: a known-good literal, a worked example, the spec."
- docs の既知の課題・運用知見（`docs/engineering/tdd.md`）:
  - 「このチェンジはループに値するか」を判断する仕組みがない（config、配線、glue、型注釈、単純 CRUD では独立した真実の源がなく、tautological テストを別方向から生む）。issue #746、未解決。「その判断はあなたか CLAUDE.md の仕事」。
  - seam 選択を求められても候補が名前だけで判断材料がない（issue #607）。回避策は「トレードオフを先に聞く」。だから上流の `to-spec` で seam を合意する設計になっている。
  - エージェントが red を飛ばして実装を先に書くことがある。Matt の立場は「100% 遵守させる指示はない。強制を強めると創造性を削るだけ。緩く守られてもループは総合的に良い結果を出す」。厳密さが必要なスライスは人が監視する。
  - ブラウザ/E2E テストを先に書かせない。遅すぎて red-green が割に合わない。CLAUDE.md に「動いた後に書く」と宣言する。
  - tdd は他チケットを知らない（issue #129）。仕様を一緒に渡すか、チケットを適正サイズにする。

### 3.2 `codebase-design`（model-invoked）：テスト容易性の語彙

- パス: `skills/engineering/codebase-design/SKILL.md`、`DEEPENING.md`、`DESIGN-IT-TWICE.md`
- 処方（テストに関わる部分）:
  - 原則「**The interface is the test surface.**」: 呼び出し側とテストは同じ seam を越える。interface の「向こう側」をテストしたくなるなら、モジュールの形が間違っている。
  - 「One adapter means a hypothetical seam. Two adapters means a real one.」: port は本番用とテスト用の 2 adapter が正当化できるときだけ作る。
  - 依存の 4 分類で seam を越えたテスト方法が決まる（`DEEPENING.md`）: in-process（直接テスト）/ local-substitutable（PGLite・in-memory FS をテストで起動）/ remote but owned（port & adapter、テストは in-memory adapter）/ true external（注入された port にモック adapter）。
  - **Replace, don't layer**: モジュールを深くしたら、浅いモジュールに対する古い unit テストは削除し、新しい interface にテストを書き直す。
  - テスト容易な interface の 3 条件: 依存を受け取る（生成しない）/ 副作用でなく結果を返す / 表面積を小さく。
- 引用:
  > "If a test has to change when the implementation changes, it's testing past the interface."

### 3.3 `to-spec`（user-invoked）：seam の事前合意

- パス: `skills/engineering/to-spec/SKILL.md`
- 処方: ユーザーに再インタビューせず会話を合成して spec を作るが、**書く前に seam だけはユーザーに確認する**。既存 seam を優先、できるだけ高い seam、数は少ないほど良く「理想は 1」。spec テンプレートに `## Testing Decisions`（良いテストの定義 = 外部振る舞いのみ、どのモジュールをテストするか、既存テストの prior art）を持つ。完成したら issue tracker に `ready-for-agent` ラベルで公開。
- docs は「合意した seam は spec を通って旅をする。`tdd` は合意済み seam でのみ動き、`code-review` は spec に対して diff を見るので、合意外の seam はレビュー指摘として表面化する」と説明しています。ただし `code-review` SKILL 本文には seam を明示的にチェックする指示はなく、Spec 軸経由の間接的な拘束です。
- 引用:
  > "The fewer seams across the codebase, the better - the ideal number is one."

### 3.4 `to-tickets`（user-invoked）：vertical slice / tracer bullet

- パス: `skills/engineering/to-tickets/SKILL.md`
- vertical slice ルール（原文の `<vertical-slice-rules>`）:
  - 各スライスはすべての層（schema、API、UI、tests）を貫く細く完全な経路。1 層の水平スライスではない。
  - 完了したスライスは単独で demo 可能または検証可能。
  - 1 つの新鮮なコンテキストウィンドウに収まるサイズ。
  - prefactoring は先に行う（"Make the change easy, then make the easy change."）。
- 各チケットは **blocking edges** を宣言し、blocker がすべて done のものが **frontier**。ユーザーに粒度・依存関係・分割統合を確認して承認を得てから公開する。
- 例外: **wide refactor**（列名変更など、blast radius が全体に及ぶ機械的変更）は tracer bullet にせず **expand–contract** で順序付ける（expand → blast radius 単位のバッチ移行 → contract）。各バッチで CI を green に保ち、無理なら共有統合ブランチ＋最終 integrate-and-verify チケットでのみ green を約束。
- チケット本文には `- [ ]` の受け入れ基準を持つ。
- 引用:
  > "A completed slice is demoable or verifiable on its own"

### 3.5 `implement` から `tdd` がどう呼ばれるか

- `implement` 本文は「Use /tdd where possible, at pre-agreed seams.」「Once done, use /code-review to review the work.」の 2 行で tdd / code-review を呼びます。
- 注意点: `.agents/invocation.md` は「スキル間依存は `Call the Skill tool with "<name>"` と明示的に書け、`/name` を散文に置くな」と定めていますが、`implement` はその規約に従っておらず `/tdd` `/code-review` 表記のままです（規約違反の残骸）。`in-progress/implement-spec` も `/code-review` 表記です。
- 1 回の実行は 5 拍（docs）: チケット/spec を読み seam を決める → 合意 seam で tdd を 1 スライスずつ → 型チェックと単一テストを頻繁に → 最後にフルスイート 1 回 → code-review → 現在のブランチに commit。
- docs の既知の課題:
  - `implement` 自身は seam を合意しない。上流（spec）か実行冒頭で合意されなければ「前提条件が発火せず、ただコードを書くだけ」になる。
  - `code-review` は `<fixed-point>...HEAD` を見るので未コミット変更が見えない。implement はレビュー後に commit するため、中間 commit がないとレビュー対象が空になる（未修正）。
  - チケットのクローズも受け入れ基準のチェックもしない。code-review の指摘にも対応しない。
  - 1 チケットで 100k トークン超は正常。膨らむならチケットを分割する。

---

## 4. 評価駆動に関わる要素

### 4.0 結論

mattpocock/skills には**評価駆動（eval-driven）の仕組みは実質的にありません**。具体的には次のとおりです。

- スキル自体の eval スイート、テスト、ベンチマーク、LLM-as-judge は存在しません。リポジトリの CI は `.github/workflows/release.yml`（changesets による版上げ）だけで、スキルの挙動を検証するジョブはありません。
- `writing-for-agents` の docs が明言しています。
  > "There is no automated eval here; the check is a manual run plus the failure-mode vocabulary as a diagnostic."
- スキルの品質管理は、GitHub issues・Discord・個人 wiki から「実際に報告された質問・失敗」を集め、docs の `## Common questions` と `## It's working if` に反映する運用です（`.agents/writing-docs.md`）。これは定性的なフィールドフィードバックであり、評価セットではありません。

以下は評価駆動に「隣接する」要素です。

### 4.1 `code-review` の 2 軸（Standards / Spec）

- パス: `skills/engineering/code-review/SKILL.md`
- 手順:
  1. **fixed point を固定**: ユーザー指定（SHA、ブランチ、タグ、`main`、`HEAD~5`）。無ければ聞く。`git diff <fp>...HEAD`（three-dot、merge-base 基準）と `git log <fp>..HEAD --oneline` を取得。`git rev-parse` で解決可能か、diff が空でないかを**サブエージェント起動前に**確認。
  2. **spec の所在を探す**: commit メッセージの issue 参照 → 引数のパス → `docs/` `specs/` `.scratch/` のブランチ名一致ファイル → ユーザーに聞く → 無ければ Spec 軸はスキップして「no spec available」と報告。
  3. **standards の所在を探す**: `CODING_STANDARDS.md`、`CONTRIBUTING.md` など。加えて Fowler『Refactoring』3 章の **12 smell ベースライン**（Mysterious Name、Duplicated Code、Feature Envy、Data Clumps、Primitive Obsession、Repeated Switches、Shotgun Surgery、Divergent Change、Speculative Generality、Message Chains、Middle Man、Refused Bequest）を常に持つ。各 smell は「何か → どう直すか」の形。repo の文書化された標準が常に優先。smell は常に judgement call（"possible Feature Envy"）。tooling が強制済みのものはスキップ。
  4. **2 つのサブエージェントを並列起動**:
     - Standards: diff コマンド、commit 一覧、standards ファイル一覧、smell ベースライン全文を渡す。指示は「(a) 文書化標準違反を standard のファイル＋ルールを引用して、(b) smell を名前＋hunk 引用で。hard violation と judgement call を区別。400 語以内」。
     - Spec: diff コマンド、commit 一覧、spec のパスまたは内容を渡す。指示は「(a) 欠落・部分的な要件、(b) 頼まれていない振る舞い（scope creep）、(c) 実装されたように見えて間違っている要件。各指摘に spec の行を引用。400 語以内」。
  5. **集約**: `## Standards` と `## Spec` に分けて verbatim または軽微整形で提示。**マージも再ランク付けもしない**。最後に軸ごとの件数と軸ごとの最悪指摘を 1 行で。軸を越えた勝者は選ばない。
- 評価駆動との関係: 「spec への忠実性」を独立した軸として判定する点は、仕様を評価基準にする発想に近いものです。ただし合否の閾値、スコア、収束条件はありません。
- 引用:
  > "Reporting them separately stops one axis from masking the other."
- docs の重要な運用知見（`docs/engineering/code-review.md`）:
  - このスキルは**バグ探しをしない**。null 経路・race・off-by-one の探索は Claude Code 組み込みの `/code-review` の役割で、名前衝突が最多報告の問題。
  - サブエージェントが `/code-review` を再発見して再帰的に増殖する既知バグ（50 体超の報告）。フォーク側の修正は両 brief に「Do not invoke `/code-review` or spawn additional agents: perform this review directly.」を 1 行足すこと。未出荷。
  - 同じセッションでのレビューより新しいセッションを推奨（利用者引用: "Same context reviewing itself isn't review, it's confirmation bias with a slash command."）。
  - 「Sub-agent output is a hypothesis, not evidence」。各指摘の引用（rule / smell+hunk / spec 行）を読んで確認してから動く。
  - **収束保証はない**。judgement call 側は非決定的で、修正が新しい表面を作る。「clean になるまでループで回すな、ならないから」。

### 4.2 `in-progress/retro`（user-invoked、**STUB: 設計メモのみ、未機能**）

- パス: `skills/in-progress/retro/SKILL.md`。README 上の扱いは「STUB: design notes only, not functional yet」ですが、本文には手順が書かれています。
- 処方: セッション後に**エージェントの環境**（steering ファイル、coding standards、自動チェック、ツール）の改善候補を出す。手順は「`writing-for-agents` を呼ぶ → 指定セッションのログ（primary source）を読む → 7 カテゴリで候補を探す → 深刻度順に提示」。7 カテゴリは Navigation / Automated checks / Coding standards / Global AGENTS.md / Tool economy / No-ops / Information access。
- 評価駆動に近い核心:
  - **機械的違反は決定的チェックにする**（固定の構文パターン、禁止 API、import 形状、ファイル配置ルール → リンターのカスタムルール、pre-commit、CI ジョブ）。`CODING_STANDARDS.md` は本物の judgement call 専用。
  - pre-commit も CI の lint/typecheck/test もないリポジトリは、それ自体が指摘事項。
  - **実装エージェントとレビューエージェントの分業**: 実装側は context pressure が最大（探索・実装・デバッグ）、レビュー側は最小（diff を受け取るだけ）。だから coding standards を課すのはレビュー側。`CODING_STANDARDS.md` はレビュー時に読むもので実装時ではない。
- 引用:
  > "Default to building the check over writing the rule."
  > "the review agent should be responsible for imposing coding standards, not the implementation agent."

### 4.3 `in-progress/loop-me`（user-invoked、beta）

- パス: `skills/in-progress/loop-me/SKILL.md`
- 内容: 生活・仕事の繰り返しパターン（loop）を見つけ、`workflows/*.md` に workflow spec として書き出す stateful grilling。語彙は Trigger（event / schedule）、Checkpoint（人間の検証・判断点）、**Push right**（checkpoint をできるだけ後ろに寄せ、人に聞くのは 1 回・遅く・準備万端で）、Brief（生出力ではなく判断可能な要約）。
- 評価駆動との関係: 薄いです。ただし完了定義が「実装者エージェントが 1 問も質問せずに作れる」という**外部の実行者を基準にした判定**になっている点は参考になります。
- 引用:
  > "A workflow spec is done when an implementer agent could build it without asking a single question."

### 4.4 `writing-for-agents` の no-op テスト

- 「その文を消したらエージェントの振る舞いが変わるか」を判定する no-op テストは model-relative で、**議論ではなく文書を実行して決着させる**と述べています。自動化されてはいませんが、「挙動差で判定する」という評価の考え方は明示されています。
- 引用:
  > "settle it by running the document, not by debate."

### 4.5 `to-tickets` / `triage` の受け入れ基準

- チケット・agent brief はチェックボックス形式の受け入れ基準を必須にしています。ただし `implement` はそれを消化（チェック）しないため、受け入れ基準を自動評価するループは閉じていません（§3.5）。

---

## 5. 並列・複数モデルの使い方

### 5.1 サブエージェントを使う場所（網羅）

| 場所 | 形態 | 目的 |
|---|---|---|
| `code-review` | Standards / Spec の 2 サブエージェントを並列 | 軸同士のコンテキスト汚染を防ぐ（"so they don't pollute each other's context"） |
| `research` | background agent 1 体 | 読む作業を委譲し、呼び出し元のコンテキストを汚さず作業を続ける |
| `codebase-design/DESIGN-IT-TWICE.md` | 3 体以上を並列、それぞれ別の設計制約 | Ousterhout の "Design It Twice"。根本的に異なる interface 案を出させて比較 |
| `improve-codebase-architecture` | 探索用サブエージェント 1 体 | コードベースを organic に歩かせ friction を記録 |
| `grilling` | 事実調査用サブエージェント | 事実はエージェントの仕事。調査中も、それに依存しない質問は先に聞く |
| `wayfinder` | research チケットごとにサブエージェントを並列 | AFK な調査チケットを一括消化（1 セッション 1 チケット規則の唯一の例外） |
| `in-progress/implement-spec`（beta） | 探索・実装者（worktree ごと）・merger サブエージェント | チケットの task graph の frontier を最大並列で消化し 1 PR にまとめる |
| `in-progress/claude-handoff`（beta） | `claude --bg` で新規 background agent | 会話を要約して別エージェントに即時引き継ぎ |

- DESIGN-IT-TWICE の制約割り当ては具体的です。Agent 1「interface 最小化（入口 1〜3）」、Agent 2「柔軟性最大化」、Agent 3「最頻出の呼び出し側を最適化」、Agent 4「ports & adapters 前提」。各エージェントは interface / 使用例 / seam の裏に隠すもの / 依存戦略 / トレードオフの 5 点を出力し、親は depth・locality・seam placement で比較したうえで**自分の推奨を強く述べる**（"Be opinionated"）。
- `implement-spec` はサブエージェントとの通信を「疎に、context pointer（spec、チケット、調査ノート、過去 commit）で」と定めています。探索サブエージェントのノートはリポジトリ外に保存して全サブエージェントで共有します。

### 5.2 異なるモデルを judge に使うか

**使いません。** リポジトリ全体を検索しても、モデル指定（Opus / Sonnet / Haiku / GPT 等）、異なるモデルによるクロスチェック、LLM-as-judge の記述は SKILL 側に 1 つもありません。モデル名が出るのは docs の利用者報告（GPT-5.6-Sol での過剰発火、Sonnet・Opus・GLM での teach の不具合）だけです。`agents/openai.yaml` は Codex の UI メタデータと暗黙起動ポリシーのためのもので、マルチモデル編成ではありません。CHANGELOG #781 では、サブエージェント指示から Claude Code 固有のツール名・agent type 名を削り、Codex 等でも従える harness 中立な記述にしています。

`code-review` の 2 軸サブエージェントも**同一モデル**で、多様性の源は「モデルの違い」ではなく「渡す文脈と問いの違い（軸の分離）」です。

### 5.3 単一エージェント vs 並列に関する立場

- 並列を使う理由は常に **コンテキストの分離** か **待ち時間の隠蔽（AFK な作業の委譲）** か **発散的設計**です。速度のための並列実装ではありません。
- `ask-matt/PHASE-BOUNDARIES.md`: フェーズ境界での 5 択（Continue / `/clear` / `/handoff` / Subagent / `/compact`）の 4 番目が「AFK でできるか → サブエージェント」で、典型例として自動レビューを挙げています（"Automated review is the standard case"）。フェーズ途中の判断は「続けるか、残りをサブエージェントに分けるか」だけ。
- 実装の並列化には慎重です。
  - `implement` docs: 「複数チケットを一括や並列で回せるか → No。1 呼び出し 1 チケット」。同一チェックアウトで複数セッションを走らせると `--amend` が他セッションの commit に乗る、stash 消失などの事故報告あり。worktree は回避策だが `refs/stash` は共有される。
  - `wayfinder` docs: 並列は blocking edge により「紙の上では安全」だが、**一度に 1 つが安全な既定**。セッション間でコンテキストが共有されず同じ質問を 2 度されるため。
  - `resolving-merge-conflicts` docs: 並列エージェント間でファイルを区画分けするのは「割に合わない」。エージェントはマージ競合に十分強い。大規模リファクタだけ先にやる。マージは書いたセッション自身がやるのが良い。
- 例外として `implement-spec`（beta）だけが「最大並列」を目標に掲げていますが、in-progress でありプラグインに同梱されていません。
- 並列の既知の失敗: `code-review` と `research` の両方で、サブエージェントがスキルを再発見して再帰的に増殖するバグ（research は issue #530、1 タスクで約 450k トークン）。逆に、グローバル指示で再委譲を禁止していると background agent が辞退して何も起きない。

---

## 6. 構造とメカニクス

### 6.1 user-invoked と model-invoked

- 定義（`.agents/invocation.md`）:
  - **User-invoked**: 人間が名前を打ったときだけ到達可能。frontmatter に `disable-model-invocation: true`、かつ `agents/openai.yaml` に `policy.allow_implicit_invocation: false`（Codex 用）。description は**人間向け**の 1 行要約で、「Use when...」のトリガー列挙は削る。役割は **orchestrate**。
  - **Model-invoked**: モデルとユーザーの両方から到達可能（既定）。description は**モデル向け**で、自動発火のためのトリガー語を豊富に含む。役割は再利用可能な **discipline** を保持すること。判定基準は「モデルが自律的に手を伸ばして有用か」（再利用性は抽出の理由であって判定基準ではない）。
- **不変条件**: user-invoked スキルは model-invoked スキルを呼べるが、**他の user-invoked スキルは決して呼べない**。前提条件が user-invoked のとき（例 `setup-matt-pocock-skills`）は Skill tool 呼び出しではなく「ユーザーに `/setup-matt-pocock-skills` を実行するよう伝えよ」と書く。
- 2 つの負荷のトレード（`SKILL-MECHANICS.md`）: model-invoked は description が常時ロードされる **context load** を払う。user-invoked は人間が存在と用途を覚える **cognitive load** を払う。user-invoked が増えすぎたら **router skill**（`ask-matt`）で 1 つだけ覚えればよい状態にする。
- 2 つの user-invoked スキルが共有する参照は、どちらのスキルにも置けない（互いに呼べないため）。スキル体系外の平文ファイルに置く。

| 分類 | スキル |
|---|---|
| User-invoked（engineering） | ask-matt, grill-with-docs, triage, improve-codebase-architecture, setup-matt-pocock-skills, to-spec, to-tickets, implement, wayfinder |
| Model-invoked（engineering） | prototype, diagnosing-bugs, research, tdd, domain-modeling, codebase-design, code-review, resolving-merge-conflicts, wizard |
| User-invoked（productivity） | grill-me, handoff, teach, to-questionnaire, wait-what |
| Model-invoked（productivity） | grilling, writing-for-agents |

### 6.2 スキル間参照の書き方

- 依存は **「Call the Skill tool with "<name>"」** と明示する。`../other-skill/FILE.md` の深い相互参照も、散文中の `/skill` も使わない。ツール名を書く方が発火率が高く、`/` を外すと harness 中立になるため。
- 1 回の Skill tool 呼び出しは 1 スキル。2 つ必要なら「Call the Skill tool twice, for "grilling" and "domain-modeling"」と書く（`grill-with-docs` の本文はこの 1 行だけ。`grill-me` は「Call the Skill tool with "grilling".」の 1 行だけ）。
- 共有参照ドキュメントは所有するスキルの中に置き、他スキルは Skill tool でそのスキルを呼んで到達する。
- router の散文（`ask-matt`、bucket README）は実行指示ではないので `/skill` 表記のラベルでよい。
- **薄いラッパー＋プリミティブ**の構造: `grilling` がインタビューの primitive で、`grill-me` / `grill-with-docs` / `triage` / `wayfinder` / `improve-codebase-architecture` がそれを内部で使います。

### 6.3 frontmatter の慣習

- 必須は `name` と `description` のみ。user-invoked は `disable-model-invocation: true` を加える。
- 任意: `argument-hint`（loop-me）、`metadata.credits`（pr、外部スキルのクレジット）。
- description にコロンを含む場合はダブルクォートで囲む（changeset `fix-yaml-frontmatter-colons`）。
- 各スキルディレクトリに `agents/openai.yaml` を置き、`interface.display_name` / `interface.short_description`、user-invoked なら `policy.allow_implicit_invocation: false`。両 harness で invocation を一致させる。
- 付属ファイルは同じフォルダに置き、SKILL.md から相対リンクで progressive disclosure（例: tdd → `tests.md` / `mocking.md`、prototype → `LOGIC.md` / `UI.md`、diagnosing-bugs → `scripts/`）。

### 6.4 CONTEXT.md と ADR

- **`CONTEXT.md`** は用語集**だけ**（実装詳細・spec・スクラッチを入れない）。形式は `**Term**:` ＋ 1〜2 文の定義＋ `_Avoid_:` の同義語リスト、必要なら `## Relationships` と `## Flagged ambiguities`（このリポジトリ自身の `CONTEXT.md` がその実例）。複数コンテキストのリポジトリは root に `CONTEXT-MAP.md`。ファイルは最初の用語が確定したときに遅延生成。
- **ADR** は `docs/adr/0001-slug.md` の連番。テンプレートは「タイトル＋1〜3 文（文脈・決定・理由）」だけ。Status / Considered Options / Consequences は価値があるときのみ。**3 条件すべて**（元に戻しにくい / 文脈なしでは意外 / 本物のトレードオフの結果）を満たすときだけ提案する。
- このリポジトリ自身も `.agents/adr/` に ADR を 2 本持ちます。
  - 0001: `/setup-matt-pocock-skills` への明示ポインタは **hard dependency**（to-tickets、to-spec、triage）だけに書き、soft dependency（diagnosing-bugs、tdd、improve-codebase-architecture）は「プロジェクトの用語集」「触る領域の ADR」と曖昧に言及するだけにする。soft 側をトークン軽量に保ち、不要な cargo-cult を避けるため。
  - 0002: Claude Code プラグインは出荷し、Codex ネイティブプラグインは延期する。Claude の `plugin.json` は `skills` に**パスの配列**を受け付けるので promoted だけを列挙できるが、Codex は単一パス文字列しか受けず、symlink はインストール時に落とされるため。
- 却下した要望は `.out-of-scope/*.md` に「概念ごとに 1 ファイル」で理由と過去 issue を記録します（例: grilling の質問数上限、setup の verify モード、非主流 issue tracker）。`triage` はこれを読んで重複要望を判定します。

### 6.5 setup スキル

- `setup-matt-pocock-skills`（user-invoked、リポジトリごとに 1 回）。決定的スクリプトではなく prompt 駆動で「探索 → 所見提示 → 1 セクション 1 回答で確認 → 書き込み」。
- 3 セクション: A. issue tracker（GitHub / GitLab / local markdown `.scratch/` / other）、B. triage ラベル（`triage` が入っているときだけ。既定 5 つ: `needs-triage` `needs-info` `ready-for-agent` `ready-for-human` `wontfix`）、C. domain docs（既定 single-context、monorepo の兆候があるときだけ multi-context を提示）。
- 出力: `CLAUDE.md`（なければ `AGENTS.md`、両方なければユーザーに聞く）に `## Agent skills` ブロック（各 1 行＋ポインタ）を追加し、実体は `docs/agents/issue-tracker.md` / `triage-labels.md` / `domain.md` に書く。**always-loaded な CLAUDE.md にはポインタだけを置く**設計です。

### 6.6 パッケージング

- バケット: `engineering/` と `productivity/` が **promoted**（出荷）、`misc/`・`in-progress/`（beta、公開だがプラグイン非同梱）・`deprecated/` は非出荷。
- promoted のスキルは必ず (1) トップ README に SKILL.md へのリンク付きで記載、(2) `.claude-plugin/plugin.json` の `skills` 配列に登録、(3) `docs/<bucket>/<name>.md` の解説ページ（What it does / When to reach for it / Common questions / It's working if / Where it fits）を持つ。非 promoted はどれも持たない。
- `.claude-plugin/plugin.json`: name `mattpocock-skills`、version は `package.json` と同期、`skills` は明示パス 25 件。`.claude-plugin/marketplace.json` は自己マーケットプレイス（公式マーケット掲載後はフォールバック扱い）。変更後は `claude plugin validate . --strict`。
- 版管理: changesets（`.changeset/*.md` に `"mattpocock-skills": patch` 等）。`npm run version` = `changeset version && node scripts/sync-plugin-version.mjs`（plugin.json の version を package.json に合わせる。`--check` で不一致なら exit 1）。`.github/workflows/release.yml` は main push で `changesets/action` が版上げ PR を作り、`npx changeset tag` でタグ付け。依存解決は `npm ci`。
- インストール経路は排他的な 2 つ: Claude Code プラグイン（読み取り専用・自動更新、「subscribe」）と skills.sh（`npx skills@latest add mattpocock/skills`、編集可能なファイルをコピー、「fork」）。両方入れると全スキルが二重になる。
- 開発者用: `scripts/link-skills.sh` が `deprecated/` と `misc/` 以外を `~/.claude/skills` と `~/.agents/skills` に symlink（`in-progress/` は意図的に含める。フィードバックループがここで回るため）。
- リポジトリ規約: 散文に em-dash を一切使わない（機械置換ではなく文を書き直す）。`ask-matt` はスキル追加・改名・フロー変更のたびに更新（"a router that lies" を防ぐ）。

### 6.7 `writing-for-agents`：SKILL.md の書き方の規則

- 対象は、スキル・`AGENTS.md`/`CLAUDE.md`・ポインタで到達される文書すべて。目標は「毎回同じ出力」ではなく「毎回同じ**プロセス**」。
- **Context pointer**: 文脈内にあって文脈外の資料を名指しし、到達条件を符号化する参照（スキルの description も AGENTS.md の 1 行も同じもの）。到達の信頼性を決めるのは target ではなく**文言**。必須資料なのに弱い文言は variance bug で、まず文言を鋭くし、駄目なら inline 化。書き方: leading word を前に置く / branch ごとにトリガー 1 つ（同義語は 1 branch の重複）/ 本文が持つ identity は削る。
- **2 つの負荷**: context load（常時ロード物のコスト）と cognitive load（人間が索引になるコスト。後者は人間の主体性の代価であって最小化対象ではない）。
- **情報階層**: (1) in-file step → (2) in-file reference → (3) disclosed reference（別ファイル、ポインタ経由）。**progressive disclosure** は「全 branch が要るものは inline、一部 branch だけが要るものはポインタの向こう」。**co-location**: 1 概念の定義・規則・注意を 1 見出しに集める。**sprawl**（長すぎ）は失敗モード。
- **Steps と completion criterion**: §2.6 のとおり（clarity と demand、premature completion、分割による後続ステップの隠蔽は本物のコンテキスト境界でのみ有効）。
- **分割の判断**: sequence で分ける（後続ステップが現ステップを急がせる場合）か、invocation で分ける（独立したトリガー語があるか、他スキルが到達する必要がある場合）。
- **Leading word**: pretrained な概念語（_lesson_、_fog of war_、_tracer bullets_、_tight_、_red_）を**トークンとして**繰り返し、文として繰り返さない。本文では実行を、ポインタでは起動を錨付けする。自作語は定義トークンを払う。
- **Negation**: 禁止で操縦すると禁止対象が活性化する（"Don't think of an elephant"）。肯定形で目標行動を書く。禁止は肯定形で書けない guardrail のときだけ、肯定形と対にする。
- **Pruning**: single source of truth（重複禁止）/ 環境（`package.json` scripts、config、`--help`）を再掲するのはキャッシュで、見つけにくいもの（暗黙の慣習、理由、gotcha）だけをキャッシュする / relevance を行ごとに確認し **sediment**（古い層の堆積）を防ぐ / **no-op**（既定で従う指示）を文単位で探し、落ちたら文ごと削除。弱すぎる leading word（_be thorough_）も no-op で、より強い語（_relentless_）に替える。
- 引用:
  > "A must-have target behind a weakly worded pointer is a variance bug"
  > "Prompt the **positive**: state the target behaviour"

---

## 7. 取り入れる価値が高いもの / 取り入れないほうがよいもの

### 7.1 取り入れる価値が高いもの

1. **「red-capable な 1 コマンドを、実行済みの出力付きで示すまで次に進まない」ゲート**（diagnosing-bugs Phase 1）。検証駆動の中核としてそのまま使えます。完了基準が「コマンド名＋実行ログ」という観測可能物なので、エージェントの自己申告に頼らずに済みます。tight の 4 条件（red-capable / deterministic / fast / agent-runnable）もチェックリストとして流用価値が高いです。
2. **feedback loop 構築手段の 10 段ラダー**。テストが書けない状況（UI、外部依存、flaky）でも「次に試す手段」が決まるので、検証の放棄を防げます。HITL スクリプトのテンプレート（人間を構造化されたループに組み込む）も、ユーザーをテスターにしない方針と両立する最終手段として有用です。
3. **事前合意した seam でのみテストする**（tdd / to-spec）。テスト対象の範囲をユーザー承認の成果物にすることで、テスト過多と実装結合テストを同時に抑えます。「理想の seam 数は 1」「interface is the test surface」とセットで採用する価値があります。
4. **tautological テストの明示的禁止**と「期待値は独立した真実の源から」。AI が書くテストで最も起きやすい失敗なので、ルールとして明文化する価値が高いです。
5. **code-review の 2 軸分離（Standards / Spec）と「再ランク付けしない」集約**。軸ごとに別コンテキストで評価し、片方の合格がもう片方の不合格を隠さない設計は、評価駆動の「評価観点の独立性」の原型として使えます。各指摘に根拠（ルール、smell＋hunk、spec の行）の引用を必須にする点も、指摘を検証可能にする仕組みとして有効です。
6. **retro の「機械的違反は決定的チェックへ、判断事項だけを文書へ」**。LLM の判定を減らして決定的な検証に置き換える方向性は、評価コストと非決定性を同時に下げます。
7. **実装エージェントとレビューエージェントの context pressure の非対称性**。規約の強制はレビュー側に寄せ、実装側の常時ロード文書を薄く保つという配分原則は、そのまま設計指針になります。
8. **3〜5 個の反証可能な仮説を先に並べる**（diagnosing-bugs Phase 3）。予測を書けない仮説を "vibe" として捨てる基準は、デバッグ以外の意思決定にも転用できます。
9. **writing-for-agents の completion criterion（clarity × demand）と premature completion の分析**。スキルの各ステップに検証可能な完了条件を付ける設計規則として、新しいスキルを書く際の基準になります。

### 7.2 取り入れないほうがよいもの（または補強が必要なもの）

1. **refactor を TDD ループから外す判断は、そのままは採用しない方がよいです**。理由は「エージェントがやらなかった」という観測に基づく実務判断であり、その受け皿の `code-review` は judgement call ベースで収束保証がないためです。取り入れるなら「refactor はレビュー段階で行い、その後に全テストを再実行して green を確認する」という検証ステップを明示的に足す必要があります。
2. **評価の仕組みがない点は参考にしないでください**。スキル自体の eval がなく、docs が「手動実行で確認」と明言しています。評価駆動を掲げるなら、この空白は自前で埋める必要があります（スキル挙動の回帰セット、code-review 指摘の再現確認など）。
3. **同一モデルのみでのレビュー**。code-review は軸を分けていますが、同じモデルの同じバイアスを共有します。docs 自身が「サブエージェントの出力は仮説であって証拠ではない」と認めているため、異なるモデルの独立レビュー、または指摘を実行で裏付ける工程を加える方が堅牢です。
4. **サブエージェント brief に再委譲禁止がない点**。code-review と research の両方で再帰増殖バグ（50 体超、450k トークン）が報告されています。取り入れる場合は、サブエージェントへの brief に「このタスクを直接実行し、スキル呼び出しや追加のエージェント起動をしない」を必ず入れてください。
5. **`implement` の「レビュー前に commit しない」順序**。`code-review` は `<fp>...HEAD` しか見ないため、中間 commit がないとレビュー対象が空になる既知の欠陥があります。採用するなら「commit → review → 修正を追加 commit」の順にするか、未コミット差分も対象にする必要があります。受け入れ基準のチェックを実装側が行わない点も、検証ループが閉じない原因です。
6. **`implement` の現在ブランチへの直接 commit**。feature ブランチと PR を経由する運用とは相容れないので、そのまま採用しないでください。
7. **「100% 遵守は求めない」という tdd の姿勢**。創造性とのトレードオフという主張には一理ありますが、検証駆動を名乗るなら「red を見たか」を trace やログで事後確認できる仕組み（テスト実行ログの提示を完了条件にするなど）を足さないと、テスト先行が形骸化します。
8. **seam 候補を名前だけで提示する UX**（issue #607）。seam を選ばせるときは、各候補が何を捕まえて何を見逃すか、実行時間はどれくらいかを併記する形に改良して取り入れる方がよいです。
9. **prototype の「テストを書かない」規則**は、prototype が throwaway ブランチに隔離され、採用時に書き直される前提でのみ成立します。この前提を持たない環境で規則だけを移植すると、テストのないコードが本流に入る経路になります。
