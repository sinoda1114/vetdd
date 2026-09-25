# pstack 調査メモ（検証駆動・テスト駆動・評価駆動・並列/複数モデル）

- 対象: `/Users/sinoda/dev/vetdd/.reference/cursor-plugins/pstack/`（Cursor plugin `pstack` v0.15.5、作者 Lauren Tan = poteto、MIT）
- 読んだもの: 依頼の全ファイル（poteto-mode/SKILL.md、playbook 6 本、tdd、arena、swarm、interrogate＋references 4 本、create/maintain-verification-skill＋feature-map-example 3 本、architect＋references 3 本、setup-pstack、principle-* 23 本すべて）。補助として playbook の perf-issue / refactoring / shipping / autopilot-full / autonomous-run / opening-a-pr / visual-parity / investigation / multi-phase-plan、show-me-your-work、blast-radius、how、orchestrate 冒頭、docs/guide/06、scripts 群の冒頭も確認した。
- 引用は英語原文のまま（各 25 語未満）。

---

## 1. 思想の核

pstack の自己紹介文は "if you want to go fast, go deep first. pstack helps you write less, but higher quality code." です（`.cursor-plugin/plugin.json`）。poteto の立場は「速さは深さの後に来る」というもので、3 つの信念に分けられます。

1. 完了の主張には、本物の成果物に対する証拠が要ります。証拠は再実行できるスクリプトの形が最も強く、「コンパイルが通った」「サブエージェントがそう言った」は証拠になりません（principle-prove-it-works、build-the-lever）。
2. 人間に聞く前に実験で決めます。観測で答えが出る分岐は人間に委ねず、プロトタイプか計測で決着させます（poteto-mode Non-negotiables、never-block-on-the-human）。
3. 判断の品質は、同じプロンプトを異なるモデルに投げて得る独立性で上げます。ペルソナを割り当てるやり方は採りません。書いた者と判定する者を分け、一致を高信号、不一致を「ルーブリックが曖昧か、どちらかが偏っている」合図として扱います（arena、interrogate、eval、shipping）。

これらの土台として、削除を優先し最小の差分で済ませる姿勢（laziness-protocol、subtract-before-you-add）と、指示文より構造で強制する姿勢（encode-lessons-in-structure）が全体を貫いています。

---

## 2. 検証駆動に関わる要素

### 2.1 principle-prove-it-works
- パス: `skills/principle-prove-it-works/SKILL.md`
- 規定内容:
  - 完了宣言の前に、本物を直接確認する。プロキシ（ファイル mtime、出力の新しさ、エージェントの自己申告、キャッシュされたスクリーンショット）で推論しない。
  - プロセスの生存は直接確認し、値は派生表現でなく実値を読む。
  - 検証が失敗したら、システムより先に観測方法を疑う（ユーザーの CLAUDE.md にある「計測器を先に検証する」と同じ考え）。
  - 最強の証明は、同じ比較を再実行できる決定的なスクリプトとする。出力は reviewer が再実行できる成果物として残す。コミットするのは大規模な移植・移行で監査証跡が要るときだけ（show-me-your-work へ委譲）。
- 引用:
  - "Verify every task output by checking the real thing directly. Do not infer from proxies, self-reports, or "it compiles.""
  - "When verification fails, suspect the observation method before suspecting the system"

### 2.2 principle-sequence-verifiable-units
- パス: `skills/principle-sequence-verifiable-units/SKILL.md`
- 規定内容:
  - 実行: 各 unit を「既知の正常状態 → 変更 1 つ → チェック実行 → 次へ」という before/after の括弧で囲む。開始前にクリーンな trunk へ rebase し、チェックが本当のベースラインと比べるようにする。lever（スクリプト）が編集する場合も、unit ごとのチェックは省かない。
  - 納品: commit と PR を「証明の順序」で積む。正準形は failing test → fix。ほかに subtraction → reshape、baseline capture → treatment、scaffold → feature がある。各 commit が単独で着地でき、並びそのものが論証になるようにする。
- 引用:
  - "The canonical shape is the failing test first, then the fix on top."
  - turns "trust me" into "watch it go red, then green."

### 2.3 principle-build-the-lever
- パス: `skills/principle-build-the-lever/SKILL.md`
- 規定内容:
  - 非自明な作業は手でやらず、それを「やる」か「証明する」道具（codemod、script、generator、sqlite へ落とす分析クエリ、再実行可能なチェック、subagent 用 skill）を作る。
  - 手順は、最初の 1 unit を手でやってレシピを学び、道具を作り、その unit に再適用して手作業版と diff を取って道具を証明する、の順。再実行しても安全に作る。
  - fan-out するときは、レシピ・検証契約・触ってはいけない範囲を 1 つの skill にまとめ、delegate の書き込み範囲の外に置く（契約を黙って書き換えさせないため）。
  - 決定的な lever は fan-out に勝つ。1 回で全 unit を処理できるなら自分で回す。
- 引用:
  - "If you cited it and there is no codemod, script, generator, or delegate skill in the diff, you didn't apply it."
  - "A deterministic script turns "trust me" into "run this"."

### 2.4 principle-fix-root-causes / principle-attack-the-premise
- パス: `skills/principle-fix-root-causes/SKILL.md`、`skills/principle-attack-the-premise/SKILL.md`
- fix-root-causes の規定:
  - 最初に再現する。根本原因に届くまで「なぜ」を繰り返す。guard を足さない。
  - 段落ほどのコメントが要る workaround は、コード側が間違っている。
  - 同じパターンを grep して全箇所を直す。詰まったら計測を入れ、推測しない。
  - 再起動後の不具合は、コードより先に永続状態（config、cache、lock、serialized state）を疑う。
- attack-the-premise の規定:
  - 同じ前提を共有する fix が 2 回以上同じ gate で落ちたら、次の fix を書く前に 2 つ行う。(1) すべての失敗 fix が仮定していた前提を 1 文で書く。(2) 偏りを actor ごとに数える census を再実行可能なスクリプトとして書く。
  - 偏りが特定の actor に集中していれば、その役割を割り当てている仕組みを探し、補償するのでなく非対称そのものを取り除く（role のローテーション、ランダム化、移動）。census が均等なら前提は原因ではないので、census は証拠として残す。
- 引用:
  - "Do not add guards (adding a nil check to silence a crash is a symptom fix)"
  - "When two or more fixes that share one premise have failed the same gate, suspect the premise, not the fixes."

### 2.5 principle-encode-lessons-in-structure
- パス: `skills/principle-encode-lessons-in-structure/SKILL.md`
- 規定内容:
  - 同じ指示を 2 回書きそうになったら、lint、metadata flag、runtime check、script のどれかにして指示文は消す。判断が要るものだけ文章に残し、失敗例を添える。
  - 強さの序列は、表現不能な状態（コンパイル不可）→ lint や banned API（CI で落ちる）→ canonical helper → runtime check。「agents copy whatever the surrounding code already does」ので、弱い guard は次の雛形になってしまう。
  - フィードバックループは Capture → Route（一回きりならメモ、繰り返すなら skill か lint、系統的なら principle）→ Close。
- 引用:
  - "If the fix is structural, only use the structural fix. The instruction is the symptom."

### 2.6 create-verification-skill（検証駆動の中核）
- パス: `skills/create-verification-skill/SKILL.md`、`references/feature-map-example/{README,create-note,search}.md`
- 成果物: プロジェクトローカルの `.cursor/skills/verify-<app>/SKILL.md` と `features/README.md`、機能ごとのファイル。読み手は人間ではなく、この app を初めて見るエージェントが作業途中にいきなり読む前提で書く。
- 手順:
  1. 人ではなく repo に聞く。Surface（UI/CLI/TUI/desktop/API/mobile/library）、Run（repo 自身の dev コマンド、port、env、seed、auth）、Drive（既存 harness が先。なければ web/Electron は browser/CDP、CLI/TUI は tmux/PTY、service は HTTP）、Observe（screenshot、端末 transcript、response body、log、exit code、DB 状態）、Isolate（2 インスタンスを並走できるか。できないなら共有インスタンスは操作しないと明記）。checkout がビルドできなければ先に直す。
  2. skill を生成する。frontmatter（`name: verify-<app>`、description に app・surface・使いどころ）に加えて、次の 6 節を置く。
     - Launch: 起動コマンド、ready の判定（log 行、port、prompt）、teardown。短命 CLI は 1 回ビルドして drive ごとに隔離 PTY を使う。
     - Doctor: 「このインスタンスを操作する価値があるか」を見る読み取り専用チェック 1 つ（process、version/build、自分の port か、auth）。
     - Drive: 実在する selector やコマンド。座標やタブ順より ARIA、data 属性、prompt 文字列、route を優先する。
     - Evidence: 本物のユーザー経路を通す（内部 setter や test 専用 endpoint は使わない）。行為と結果状態の両方を撮る。副作用（ファイル、行、送信）も確認する。mock は本番でも境界が外部を隔離している箇所だけ。dry-run は「名前を信じず、何を skip するか観測で確かめる」。
     - Cleanup: 自分が起動したものだけ kill する（プロセス名で kill しない）。証拠は消さない。
     - Helpers: 同梱スクリプトは実行可能にし、呼び出し方を本文に書く。
  3. feature map を置く。上位 3〜5 機能。各ファイルは H1＋1 段落のあと、H2 を 4 つ固定順で置く（`Sub-features` / `How to get to it (user POV)` / `Driving it with <harness>` / `Gotchas`）。README 側には Baseline preconditions、Driving conventions、Proof and skip reporting（UI 証拠は ARIA snapshot＋screenshot、CLI 証拠はコマンド・stdout・stderr・exit code、変更系は読み取り専用の 2 つ目の view で確認、到達不能は試したコマンドと未充足前提を添えて報告、別経路での代替検証を verified と報告しない）を書く。
  4. 引き渡す前に自分で 1 周回す。launch → doctor → mapped feature 1 つを drive → evidence → cleanup → 証拠が残っているか確認。失敗するたびに cleanup も走らせる。
  5. `/maintain-verification-skill` を案内する。
- 引用:
  - "A generated skill that was never executed is a draft, not a deliverable."
  - "a cleanup that eats the proof fails this step"

### 2.7 maintain-verification-skill
- パス: `skills/maintain-verification-skill/SKILL.md`
- 結論は 3 値: `clean`（PR なし）/ `changed`（証明済みの修正を PR 1 本）/ `blocked`（何が塞いだかを明示）。
- 編集範囲は verification skill のディレクトリだけ。product code は触らない。map と挙動がずれていたら、doc drift なら map を直し、product regression なら報告に留める。
- Pass:
  - 0. 対象を特定する（`verify-*`。複数あれば聞き、無ければ create へ誘導）。
  - 1. index を整える。
  - 2. Source wave: feature ファイルごとに read-only subagent を並列に出す。返却形は「summary / source entry points / drift or none / recipe 1 本」。子は app を操作せず、編集もしない。
  - 3. Reconcile: recipe をまとめ、drift は抜き取りで確認する。直近の変更で map に無い surface を探す（具体的な source path が必須）。
  - 4. Live pass（source が clean でも必須）: 操作するのは coordinator だけ。不変条件は 3 つ。(1) 最後に想定外が起きてから doctor していないインスタンスは操作しない。(2) 証拠はどの cleanup の後も残す。(3) drive が起動したものはその drive の役目が終わったら残さない。`verified-unreachable` を名乗るには具体的な前提と試した経路が要る。
  - 5. Triage: doc drift / harness gap / product gap。
  - 6. Ship or stop。
- 引用:
  - "Required even when source looks clean."
  - "Never edit product code during a run"

### 2.8 poteto-mode 本体の検証規律
- パス: `skills/poteto-mode/SKILL.md`
- 規定内容:
  - reply の各主張には、同じ文の中に証拠かラベル（Measured / inferred / guess）を付ける。予測と、観測していない原因は guess と書く。
  - 自分で実行できるチェックを人間に渡さない。リンクや引用はこのセッションで生成したか読んだものに限る。
  - UI/IDE/CLI を出荷するときは control skill（`control-cli` / `control-ui`、cursor-team-kit）で同じ surface を自分で操作する。
- 引用:
  - "Every claim carries its evidence or its label in the same sentence. Measured, inferred, or guess."
  - "Never hand the human a check you could run."

### 2.9 playbook 群の検証ゲート
- `playbooks/bug-fix.md`
  - 手順: (1) matching surface で自分で再現する（ユーザーに頼むのは具体的な理由があり、自分で行けるところまで操作した後だけ）。(2) 仮説を列挙し、残りの問題空間を最も削る分割で二分探索する。state が不明なら計測を入れる。(3) 関数境界をまたぐなら architect。(4) 同じ surface で元の repro が通ることを確認する。(5) failing repro を fix より前の commit に置く。
  - 反証された仮説が動機だった変更は revert する。
  - 引用: "Every shipped line traces to runtime evidence." / "Unit tests show branch behavior, not bug absence."
- `playbooks/feature.md` step 5: matching surface で検証する。引用: ""Inconclusive" or wrong-surface is not a pass."
- `playbooks/refactoring.md`
  - step 1 で behavior contract を pin する（characterization test、snapshot、equivalence harness）。
  - step 6 で本物の成果物に対し equivalence check（旧新出力の diff スクリプト、記録済み baseline の replay、smoke run）。
  - step 7 で reader load が減っていなければ revert する。
  - 引用: "Type check and lint are not a pin."
- `playbooks/perf-issue.md`: baseline trace → 仮説 → post-fix trace → artifact を JSON→sqlite で比較する。仮説の生成源は 8 系統（Elimination / Divide and conquer / Caching / Indirection / Batching / Redundancy / Lazy evaluation / Scheduling）。trace がその系統のシグナルを示したときだけ試す。
- `playbooks/visual-parity.md`: 先に baseline を撮る。harness の改変、baseline の改ざん、diff を通すための再構成を禁じる。nonzero diff は fail とし、diff 0 まで `/loop`。引用: "No baseline, no parity claim."
- `playbooks/autonomous-run.md`: 最初に exit condition を checkable predicate として書く。1 iteration ごとに最小変更 → predicate で検証 → 前進したら commit、しなければ破棄。引用: "never relax the predicate to declare victory."
- `playbooks/prototype.md`: 見た目の判断は各 variant の screenshot、振る舞いの判断はタイミングや出力の観測で決める。引用: "The observation is the test here, not an assertion."
- `playbooks/multi-phase-plan.md`＋`scripts/check-plan.mjs`
  - plan の各 PR に `Verify, unit.` / `Verify, live.` / `Verify, perf.` の 3 ブロックを必須にする。
  - live は PR head で 10 lane を swarm で回す（各 lane にシナリオ・保存する screenshot・pass predicate）。Lane 1 は「Regression lane against trunk」で、同じシナリオを trunk と head で走らせる。
  - perf は両側で測る。Metric / Probe（trunk と head を交互に）/ Baseline（trunk を先に）/ Rule（fail になる数値）。
  - `check-plan.mjs` は固定文 RULE、見出し、sub-block 順（Depends on. / Files. / Build. / You see. / Verify, unit. / Verify, live. / Verify, perf. / Review gate. / Merge.）、perf 4 項目を lint する。encode-lessons-in-structure の実装例です。
  - 引用: "Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked."
- `playbooks/shipping.md` / `autopilot-full.md`
  - PR ごとに独立の agent が parent 対 head を実 surface で検証し、`PASS` / `PASS+NOTES` / `FAIL` を返す。
  - 判定は verdict の head SHA、base SHA、`git patch-id` と一緒に記録する。rebase 後は patch-id が同じなら verdict を引き継ぎ、違えば再検証する。
  - land するのは最下段から連続して verified な範囲だけ。
  - autopilot-full の verify lane は gates 再実行、live（floor で、これが無い verdict は clean にならない）、2 本以上の diff 監査 lane（それぞれ焦点を 1 つに絞り、PR 本文は疑う）、trunk 回帰 lane。behavior finding には「同じ欠陥を持つ全箇所を覆う red test」を要求する。
  - 引用: "Safe means a verdict from an agent that did not write the code. CI green is not a verdict"

### 2.10 blast-radius（確信度の梯子）
- パス: `skills/blast-radius/SKILL.md`
- 規定内容:
  - 変更が安全である根拠の「1 つの事実」を見つけ、実コードを走らせて証明する。
  - 確信度の 5 段階: 1 自分で言っただけ（無価値）→ 2 `file:line` を指した → 3 失敗経路を辿り、そこに届かないことを示した → 4 実コードを呼ぶ script や test を走らせた → 5 動いている app で再現した。どこで止めたかを明記する。
  - 大きな変更は arena で複数モデルに聞く。
- 引用: "A blast-radius writeup that sounds right is worthless."

### 2.11 show-me-your-work（検証の監査証跡）
- パス: `skills/show-me-your-work/SKILL.md`、`references/decision-log-template.tsv`、`scripts/log.sh`
- 規定内容:
  - TSV 1 本に、列 `ts / phase / decision / why / evidence / result` で追記のみ。evidence は SHA、PR、`file:line`、artifact path などのポインタで、文章は書かない。
  - 既定ではコミットしない（`decisions.tsv` か `.audit/<slug>.tsv`）。
  - run の境界は phase `start` 行で示す。
  - 終了時に自分の transcript と行を突き合わせる。誤った行は消さず、上書きする行を追記する。
  - 最後に別のモデル系統の subagent が trail と transcript を読み、弱い証拠、証明なしの検証主張、危うい判断を指摘する。reply は "Attention" 節で締め、`reviewed by <model>` を 1 行目に書く。
  - `log.sh` は tab・改行を除去し、`= + - @` で始まるセルに `'` を前置して spreadsheet の formula injection を防ぐ。
- 引用: "Self-review is not a substitute."

---

## 3. テスト駆動に関わる要素

### 3.1 tdd skill（手順そのもの）
- パス: `skills/tdd/SKILL.md`（見出しは "TDD Bug Fix"）
- 適用範囲はかなり狭い。description によると、ユーザーが TDD、failing test、regression test を明示したとき、またはバグに安価で明白なローカルのテスト対象があるときだけ使う。テスト経路が不明瞭、高コスト、統合寄り、または依頼されていない場合は skip する。`disable-model-invocation: true` なので自動では発火しない。
- 手順（原文 6 ステップ）:
  1. Understand the bug: 意図した挙動、現在の挙動、影響経路、最小の観測可能な再現を特定する。
  2. Choose the narrowest executable check: その codepath で既に使われている最も近い unit / component / integration / regression test を選ぶ。実用的な経路が無ければ、手順を満たすためだけに新規に作らない。
  3. Write the failing test first: バグを捕まえられた最小のテストを書く。現在の実装をなぞらず、意図した挙動を encode する。
  4. Run the new test before fixing（Red の確認）: 意図した理由で落ちることを確かめる。通ってしまう、または無関係な理由で落ちるなら、実装に触る前にテストか再現を直す。
  5. Fix the bug: 周辺の契約を保ったまま、最小の production 変更を入れる。
  6. Rerun the regression test（Green の確認）。
- Refactor 段は tdd skill に無い。構造変更は Refactoring playbook（pin を green に保ったまま小さく動かす）が受け持つ。
- テストが非実用的な場合の代替: 狙いを絞った script、手動再現コマンド、browser automation、snapshot 比較、log assertion、focused integration check。
- 悪いテストの定義: 主に mock を検証している、現行実装の詳細を encode している、タイミングや無関係なグローバル状態に依存する、小さな修正に高価なインフラが要る、証明後すぐ消される。
- Guardrails:
  - 間違った実装に合わせてテストを変えない。
  - 期待挙動が本当に変わった場合以外、既存 assertion を弱めない。
  - fixture の大量変更や無関係なカバレッジ拡大をしない。
  - flaky なら決定化し、固定したシグナルを書き残す。
  - 同種の失敗が広くありそうなら、まず焦点を絞った regression を着地させ、兄弟ケースは後で追加する。
- Final Response: failing-before のテストと、それが出した失敗、passing-after の実行、周辺の検証を書く。failing-before を示せなかった場合はその理由と代替チェックを書く。
- 引用:
  - "Confirm it fails for the intended reason."
  - "Prefer no new test over a bad test."
  - "Do not change tests merely to match a wrong implementation."

### 3.2 principle-test-behavior-not-implementation（何を禁じるか）
- パス: `skills/principle-test-behavior-not-implementation/SKILL.md`
- 定義: テストは、ユーザーと同じ呼び方でコードを呼び、ユーザーが観測する結果を literal の期待値と照合する。
- 判定法（undefined テスト）: 「import したすべての関数が `undefined` を返しても通るか」。通るなら、そのテストは挙動を観測しておらず欠陥で落ちようがないので、assertion を書き直すか削除する。
- 禁止される 5 形:
  1. Weak or no assertion: `expect` 無し、または `toBeDefined` / `toBeTruthy` / `not.toThrow` / `toBeInstanceOf` / `toBeGreaterThan(0)` だけ。
  2. Mock or absence only: `toHaveBeenCalled` / `not.toHaveBeenCalled` / `toBeUndefined` / `toEqual([])` / `toHaveLength(0)` / `not.toBe(wrongValue)` だけ。
  3. Self-referential: 期待値がテスト対象から来る（`expect(f(a)).toBe(f(a))`、`expect(parsed.url).toBe(buildUrl(...))`）。
  4. Constant pin: 手で管理する定数、config の既定値、table の行、prompt 文字列をなぞる（`expect(LIMITS.maxTools).toBe(8)`、`expect(PROMPT).toContain("You are")`）。定数を編集すると落ちるので、正当な編集を妨げる害もある。
  5. Fixture asserts fixture: テストが組んだデータや `beforeEach` の値を読むだけで、本文で subject を実行しない。
- 直し方:
  - 本文で subject を具体的な入力 1 つで呼び、literal の出力か観測可能な効果を assert する（例 `expect(slugify("Hello, World!")).toBe("hello-world")`）。
  - 「無いこと」を確かめたいときは、同じテストで別入力に対して「有ること」も assert する。
  - 定数はその値をなぞらず、定数を読む仕組みを入力 1 つでテストする。
  - mock は「呼ばれたか」でなく、受け取った payload か呼び出し後の state を assert する。
- 残してよいもの: table の行をまたぐ関係のテスト（2 つの table に同じ key がある、親が存在する）と、`*.test-d.ts` の型テスト。
- 引用:
  - "ask whether it would still pass if every function it imports returned `undefined`. If yes, it observes no behavior"
  - "When no such assertion exists, delete the test."

### 3.3 他ファイルに散っている TDD 関連規定
- `playbooks/bug-fix.md` step 5: failing repro を fix より前に git 履歴へ置く。安価なローカルテストがあるときは tdd skill の cadence に従い、高価、統合寄り、不明瞭なら skip する。
- `principle-sequence-verifiable-units`: 納品順の正準形は failing test → fix（2.2 参照）。
- `principle-foundational-thinking`: "tests before fixes"。scaffold（CI、lint、test infra、shared types）を先に置く。"Test behavior and edge cases, not line counts."
- `principle-migrate-callers-then-delete-legacy-apis`: テストを新しい契約に合わせて更新し、リファクタ前の実装詳細しか守っていないテストは削除する。
- `playbooks/refactoring.md` step 1: カバレッジが無い領域では、構造に触る前に characterization test を書く。
- `playbooks/autopilot-full.md` step 4: behavior finding ごとに、同じ欠陥の全箇所を覆う red test を要求する。テストで示せない場合は repro receipt。
- `interrogate/references/rubric.md` の Verification 節: テストが挙動を見ているか実装詳細を見ているか、バグ修正にバグのテストがあるか、統合境界で全経路をテストしているか、委譲作業で自己申告でなく出力成果物を検証しているか。

---

## 4. 評価駆動に関わる要素

### 4.1 Eval playbook
- パス: `skills/poteto-mode/playbooks/eval.md`
- 用途: skill、構造、prompt の変更がエージェントの振る舞いにどう効くかを、昇格（promote）の前に試す。担当者は実験設計を所有し、Plan → blind → run → synthesize の順に進める。
- ブラインド化の必須事項:
  - candidate が見るディレクトリ、ファイル、prompt に `eval` / `test` / `judge` / `experiment` / `rubric` / `score` / `compare` / `benchmark` / `candidate` / `arena` の語を入れない。
  - candidate prompt は自然なユーザー依頼に見せ、goal だけを書く。
  - 連鎖を引き出す手がかりを与えない。どの skill、principle、file を使ったか列挙させず、design notes を一般的に求め、chain-following はコードの形から採点する。
  - ディレクトリ名や slug は、ユーザーが付けそうなプロジェクトらしい名前にする。
  - 他の candidate の存在を伝えない。
  - judge は採点役であることを知ってよいが、出力は sanitize したラベルでしか見せず、モデル名は見せない。
  - 2 つの variant を比べるときは、1 人の judge が両方の集合を 1 回の pass、1 つの尺度で採点し、どちらの集合由来かは伏せる。
- 手順:
  1. Frame: 何の variant を試すか、成功とみなす振る舞いを書く。rubric（具体的な基準 3〜6 個）は judge 専用で、candidate には渡さない。
  2. candidate ごとに sanitize した作業ディレクトリを用意し、variant を配置する。自然なタスクなら当然ある文脈（project skeleton、candidate が自然に読む skill）も置いておく。
  3. ユーザーが実際に打つような自然な prompt を 1 本書く。
  4. arena の Phase B に従い、異なるモデルで N 個の candidate を並列に起動する。同じ prompt、別々の dir。
  5. arena の Phase C に従い、別のモデル系統で blinded judge を 1 つ起動する（rubric＋sanitize ラベル）。
  6. chain は transcript で検証する。active workspace の `agent-transcripts/` にある各 candidate の transcript を読み、実際に開いたファイルを確認する。`~/.cursor/projects/*/` を glob しない（無関係なプロジェクトの private chat を読んでしまうため）。
  7. 全出力を自分で最後まで読み、judge の verdict と比べて統合する。
- judge の選び方: arena Phase C の `arena cross-judge pool`（既定 `claude-opus-5-5-max` / `gpt-5.6-sol-max` / `grok-4.7-xhigh-fast`）から、親と別の系統を優先して 1 つ選ぶ。readonly で、candidate の全員が書き終えてから起動する。
- rubric の形: 「この課題の成功とは何か」を書き、採点可能な具体的基準 3〜6 個に落とす。judge は基準ごとに採点し、picker も基準ごとに採点する（全体の印象では決めない）。
- 結果の記録: Reply に variant、rubric、candidate ごとのメモ、judge の verdict、統合所見、promote するかどうかの推奨を書く。eval.md 自体は永続的な保存形式（ファイル名、スキーマ）を定めていない。arena 経由なら synthesis note（base、grafts、rejections、dropouts、verification 結果）が残る。
- 引用:
  - "The candidate prompt looks like an organic user request. State the goal, not the meta."
  - "Grade chain-following from the files it really read plus the shape of the code, never from the candidate's own claims."
  - "Disagreement means a model is biased or the rubric is ambiguous."

### 4.2 Hillclimb playbook（指標駆動の反復）
- パス: `skills/poteto-mode/playbooks/hillclimb.md`
- 規律の核: 1 変更 → 1 計測 → keep か revert。未検証の変更を積み重ねず、コードを読んだだけで勝ちを主張しない。
- 手順:
  1. how で workload と architecture を把握し、結果を動かす次元（データ量、履歴、状態、並行度）を名指しする。ユーザーの不満を再現するケースを選ぶ（再現しなければ hillclimb ではなく repro を直す）。metric を 1 つ、良くなる方向、stop predicate を決める。stop predicate は target と試行回数の下限を組にする（例 "at least 50% better than baseline and at least 10 iterations"）。まぐれの初期勝利で止まらないようにするため。
  2. 計測 harness を作り、感度を証明してから凍結する。対照的な workload で、target ケースが症状を再現し、易しいケースが期待どおり分離することを確かめる。凍結後は 1 コマンドで metric を出し、median of N でノイズを超える。baseline と regression gate の green を変更前に記録する。
  3. show-me-your-work で `decision.tsv` を開く。列は id / hypothesis / change / before / after / delta / tests / verdict（kept か reverted）/ note。毎回の試行前に読み、gitignore しておく。
  4. 仮説は具体的なメカニズムを名指しする（"defer X off the boot path because it blocks first paint"）。
  5. ループ: 変更は subagent（hillclimb model）に渡し、自分は diff を review する。独立した仮説は worktree ごとに並列化してよい。凍結 harness で before/after を測り、regression gate を回す。metric がノイズを超えて動き、gate も green のときだけ採用し、それ以外は全部 revert する。採用 1 件につき 1 commit（`git add <files>`、`-A` は禁止）。kept でも reverted でも行を記録する。
  6. 最初の plateau を越える。reject が続いたら、カテゴリを変える、惜しかったものを組み合わせる、source を読み直す、より大胆に攻める。正しさと単純さは数字より優先する。
  7. predicate を満たすか、残りの案が費用に見合わなくなったら止める。
  8. 採用 commit を着地順に積んで PR にする。
- 引用:
  - "one change, one measurement, keep or revert."
  - "Don't relax the predicate to meet it"

### 4.3 その他の評価駆動の断片
- poteto-mode Non-negotiables は、AskQuestion を出す前に分岐を分類させます。実行して観測できる事実（"behavior, timing, layout, output, perf, even whether an eval separates"）なら人間に聞かず、prototype で決めます。つまり「eval が variant を分離できるか」自体も実験で確かめる対象です。
- arena Phase A: 成功の定義を rubric 3〜6 基準に落とします。candidate は task だけを見ます。
- architect の base 選定軸は interface depth（小さい公開面の裏に多くの複雑さを隠している方を優先）と design-red-flags（shallow module / information leakage / temporal decomposition / pass-through method）です。
- interrogate の reviewer 出力は severity（critical / warning / nit）＋ Finding / Evidence / Suggestion の構造化です。

---

## 5. 並列・複数モデルの使い方

### 5.1 共通の既定（poteto-mode Subagents 節）
- playbook 内の subagent は `subagent_type: "poteto-agent"`。ただし how / why / interrogate / reflect / swarm など、skill が自分で `subagent_type` を指定している場合はそちらに従う（モデルの多様性を保つため）。
- すべての `Task` 呼び出しの既定:
  - `run_in_background: true`
  - agent mode（readonly にすると MCP が外れる）
  - 文脈はインライン展開せずファイルポインタで渡す
  - role ごとにモデルを明示する
- モデルの既定: code は `grok-4.7-xhigh-fast`、prose と judgment は `claude-opus-5-5-max`。最難関（横断設計、込み入った並行処理、微妙なアルゴリズム）は、判断型でも手順厳守型でも `claude-opus-5-5-max`。機械的な編集は fast code model。
- 親は subagent の出力に責任を持つ。diff を自分で review し、自分の言葉で要約する。「done」の申告は信じない。割り込みで resume すると指示が落ちるので、スコープを統合した新しい subagent を起動し直す。
- 引用: "A second opinion is the same prompt against a different model. Agreement is high-signal."

### 5.2 何を並列にし、何を直列に残すか（Feature step 3 の throughput checkpoint）
- 4 項目を todo として必ず書く。該当しない項目も `n/a: <reason>` で残す。
  - Blocking first steps: fan-out の前に gate を回す。
  - Independent workstreams: ファイル、サービス、層が素なら並列にする。共有される書き込みは直列にする。
  - Shared mutable state: 既定は対象を分割する（separate-before-serializing-shared-state）。直列化は本物の不変条件があるときだけ。
  - Smallest safe decomposition: worker 1 人が最適なら、その理由を書く。
- コードが密結合な仕事（1 feature、1 migration）は owner 1 人に任せ、owner が blocking phase の後で内部 fan-out する。親レベルの fan-out は、独立した成果物を生む slice（監査、サブシステム横断の調査、競合する実験）に限る。
- principle-separate-before-serializing-shared-state: 共有書き込み先を無くすのが既定。各 actor に自分のファイル、key、branch を持たせ、読み出しや報告の境界で merge する。1 つの `state.json` に 2 worker が別フィールドを書くのも共有変更に当たる。"we need a lock" は設計の臭いとして扱う。

### 5.3 arena（ベイクオフ＋接ぎ木）
- パス: `skills/arena/SKILL.md`。フェーズは Frame → Fan out → Cross-judge → Pick → Graft → Verify で、最初に todolist を開く。
- Phase A: 成果物を定め、rubric を 3〜6 基準で作る（picker 専用）。runner は `arena runners` 行、既定は `claude-opus-5-5-max`、`gpt-5.6-sol-max`、`grok-4.7-xhigh-fast` を 1 つずつ。
  - Task が slug を拒否したら、同じ系統の既定に落とす（系統は prefix の `claude-*`、`gpt-*`、`grok-*` で判定。該当しなければ opus）。
  - 設計の方向が複数あるなら runner を増やす。判断より生成量が勝負の仕事は同じモデルを N 回。
  - 出力先は candidate ごとに分ける（git worktree、無理なら `/tmp/arena-<slug>/candidate-<n>/`）。
- Phase B: N 個を 1 メッセージでまとめて background 起動する。渡すのは task、共有 grounding の path、自分の出力 path、「成果物と、検討して退けた代替を書いた短い rationale」の指示。欠けた candidate は N-1 で続行し、記録する。
- Phase C: 全員が書き終えてから、cross-judge pool のうち親と別系統のモデルで readonly judge を 1 つ起動する。rubric と path ラベルを渡し、基準ごとの採点と base の推奨をさせる。judge は親の Phase D の読みと並行して走る。
- Phase D: 親が全 candidate を最後まで読み、基準ごとに採点して judge と照合する。base は「将来の保守者が不変条件を壊さずに拡張しやすいもの」、同点なら境界がきれいな方か API が小さい方を選ぶ。synthesis note に理由と judge の verdict を書く。
- Phase E: 負けた candidate から 1〜2 点を手作業で移植する（貼り付けでなく、1 つのメンタルモデルで一貫するよう書き直す）。grafted / rejected と理由を記録する。
- Phase F: prove-it-works で検証する。問題が出たら、Phase A が誤っていたなら reframe、graft 漏れなら Phase E に戻る。
- 引用:
  - "When N candidates wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence."
  - 一方、収束した場合は強い一致信号として扱い、graft せずにその形で出荷します。

### 5.4 swarm（カバレッジ・レース・ガントレット）
- パス: `skills/swarm/SKILL.md`。フェーズは Frame → Fan out → Aggregate → Report。
- Frame:
  - done predicate と返す成果物を決める。
  - 形を選ぶ: slice に分割（partition）、同じ brief で N 人を競わせる（race）、その混合。race を含むなら起動前に選定規則を宣言する（`first pass` / `rank all` / `best-of`）。
  - N は worker の総数で、並行上限とは別。
  - worker のモデルは `swarm workers` 行、既定 `grok-4.7-xhigh-fast`。モデル race なら各腕のモデルを先に決める。
  - 書き込む worker には専用の出力先を与える。commit を検証・計測する brief には正確な SHA を書き、計測なら方法（サンプル数、1 サンプルの定義、順序）も書く。
- Fan out: `subagent_type: generalPurpose`、`environment: "cloud"`（ユーザーのマシンが要るときだけ `local`）、`run_in_background: true`、必要なら `cloud_base_branch`。brief は単独で読んで分かるようにし、goal、scope、担当 slice か腕、検証方法、報告内容を書く。報告は `PASS` / `ISSUES` / `BLOCKED`＋証拠。`ISSUES` なら証明できる問題をすべて列挙する。
- Aggregate: brief が指定した SHA と方法を記録していない結果は捨て、その worker を 1 回だけ再実行する。2 回目も欠けたら gap として記録する。coverage は全 slice に結果が必要。race は宣言した規則で選ぶ。worker の生出力は貼らない。
- Report: 結果表、1 行ずつの issue、gap と dropout、race 規則。
- 引用: "A gap does not count as a pass."

### 5.5 interrogate（多モデル敵対レビュー）
- パス: `skills/interrogate/SKILL.md`＋`references/{reviewer-prompt,rubric,code-quality-review,lead-judgment}.md`
- 手順:
  1. Scope を決める（指定ファイル、`git diff main...HEAD` など）。
  2. Intent を 1 段落で書く（不明ならユーザーに聞く）。
  3. reviewer を 1 メッセージで一斉に起動する。`interrogate reviewers` 行の数だけ出し、既定は A=`claude-opus-5-5-max`、B=`gpt-5.6-sol-max`、C=`grok-4.7-xhigh-fast`。設定は `generalPurpose`、`readonly: true`。全員に同じ template（intent、diff、rubric、code-quality lens）を渡す。
  4. Synthesize: 2 モデル以上が独立に挙げた指摘を最高信号として扱い、単独指摘は重みを下げる。重複をまとめ、対立を記録する。
  5. Lead judgment: Act on / Consider / Noted / Dismissed に分類し、各項目に提起モデルと 1 行の理由を付ける。
- 出力: Intent / Reviewers / Act On / Consider / Noted / Dismissed / Agreement Map。自動適用はしない。
- reviewer prompt: intent 自体は疑わず、実行の出来を攻める。褒めない。指摘ゼロも正当な結果。
- rubric の観点: Correctness（冪等性、並行性を含む）/ Root Causes vs. Symptoms / Structural Integrity / Verification / Complexity Budget / Security。
- code-quality lens: "code judo"（構造の単純化）を積極的に探す。1k 行未満のファイルを 1k 超にしない。場当たりの分岐を足さない。薄い wrapper を作らない。型と境界をきれいに保つ。非原子的な更新を避ける。
- lead-judgment の濾過基準:
  - Nitpick Gravity（指摘が nit ばかりならコードは大丈夫と判断する）
  - 仮定の話か実際の経路か（呼び出し元を辿る）
  - 時期尚早な抽象化の提案
  - "I would have done it differently" 型の偽陽性
  - 文脈不足による誤指摘
  - security と正しさの指摘は、単独でも慎重に扱う
  - Dismissed の列挙は、ユーザーが判断を覆せるようにするための信頼の仕組み
- 引用:
  - "The adversarial signal comes from model diversity, not assigned personas."
  - "If your "Act On" list has more than 5 items, you're probably not filtering hard enough."

### 5.6 architect / how（arena と並列探索の応用）
- architect の流れ: Phase A で how（必要なら why）を使って grounding → Phase B で arena → Phase C は opt-in の人間チェックポイント → Phase D で sketch を契約として実装 → Phase E で scrap 判定。
- Phase B の細部:
  - runner は `architect runners` 行（既定は arena と同じ 3 モデル）。
  - runner-prompt.md を各 runner に渡す。構造的に異なる候補を最低 2 つ要求する（"Design it twice"）。
  - 候補ごとに design-red-flags を通してから比較する。
  - rationale-template の節: Problem / Usage (caller's view) を型より先に書く / Shape / Synthesis decision / Tradeoffs accepted / Alternatives considered（必須）/ Open questions and risks / Next implementation step。
- runner への指示: 他の runner に合わせて保険をかけず、自分のモデルで最良の設計を出させる。
  - 引用: "Converging on a safe-looking middle defeats the exploration."
- how の構成:
  - 複雑な問いでは 2〜4 の角度で explorer を並列起動する（`how explorer`、既定 grok、readonly）。
  - 結果を explainer 1 つが統合する（`how explainer`、既定 opus）。
  - 単純な問いでは explainer 1 つで済ませる。

### 5.7 検証・監査での複数モデル
- show-me-your-work: 作業したモデルと別系統の subagent が trail を読んで指摘する（2.11）。
- orchestrate: worker と verifier は別のモデル系統にする。どの spawn と resume にも `preferences.md`（standing orders）を逐語で貼る。worktree または branch ごとに書き手は 1 人。
- shipping と autopilot-full: 判定者は作者と別の agent。PR ごとに独立 lane を立てる（2.9）。

### 5.8 setup-pstack（role とモデルの対応）
- パス: `skills/setup-pstack/SKILL.md`。書き出す先は `~/.cursor/rules/pstack-models.mdc`（`alwaysApply: true`）。
- 手順:
  1. `Task` に渡せる slug を検出する（未確認の slug は書かない）。`inherit-parent` と `auto` は常に有効で、親チャットのモデルで動く（Task の `model` を省く）。
  2. 既存の rule を読む。退役した role の行は落とす。
  3. budget を 4 択で選ぶ。`unlimited — keep max` / `large — xhigh reasoning` / `medium — high reasoning` / `small — medium reasoning`。effort token（末尾、または末尾 `fast` の直前）を段階 `max > xhigh > high > medium > low` に沿って置き換える（例 small なら `claude-opus-5-5-max` → `claude-opus-5-5-medium`、`grok-4.7-xhigh-fast` → `grok-4.7-medium-fast`）。検出できない slug になったら、同じ系統で目標以下の最大 effort を使う。
  4. 全 role を表示して確認し、validate する。
  5. ファイル全体を上書きする（冪等）。
  6. 確定したことを伝える。
  7. verify-* skill が無ければ `/create-verification-skill` を 1 回だけ提案する。
- 既定の対応（原文どおり）:

| role | 既定モデル |
|---|---|
| feature, refactoring | grok-4.7-xhigh-fast |
| bug-fix | grok-4.7-xhigh-fast |
| perf-issue | grok-4.7-xhigh-fast |
| hillclimb | grok-4.7-xhigh-fast |
| judgment and prose | claude-opus-5-5-max |
| hardest tasks | claude-opus-5-5-max |
| how explorer | grok-4.7-xhigh-fast |
| how explainer | claude-opus-5-5-max |
| why investigators | grok-4.7-xhigh-fast |
| why synthesizer | claude-opus-5-5-max |
| reflect tooling | gpt-5.6-sol-max |
| reflect judgment, divergent, synthesizer | claude-opus-5-5-max |
| arena runners（list） | claude-opus-5-5-max, gpt-5.6-sol-max, grok-4.7-xhigh-fast |
| arena cross-judge pool（list、親と別系統を 1 つ選ぶ） | 同上 |
| swarm workers | grok-4.7-xhigh-fast |
| architect runners（list） | 同上 3 モデル |
| interrogate reviewers（list） | 同上 3 モデル |

- panel role（arena runners、architect runners、interrogate reviewers）では list の長さが fan-out 数になります。alias のエントリも 1 lane に数えます。
- 役割分担の傾向: 実装と探索は速い code model（grok）、判断・統合・文章は最強の判断モデル（opus）、敵対レビューと比較は 3 系統の混成です。

---

## 6. 構造とメカニクス

### 6.1 配布形態とディレクトリ
- `.cursor-plugin/plugin.json` が `"skills": "./skills/"` と `"agents": "./agents/"` を宣言しています。
- `agents/poteto-agent.md`（`is_background: true`）は、作業前に poteto-mode の SKILL.md を Principles index ごと全部読むよう指示する薄い wrapper です。`generalPurpose` で代用すると、この読み込みが抜けて振る舞いがずれる、と明記されています。`agents/comment-sicko.md` はコメント削除専用の persona です。
- `docs/guide/01〜10` は人間向けガイドです（06 が verify と ship）。`automations/benny/` には issue の triage と再現・修正用の自動化 skill 群があります。
- skill のレイアウトは `skills/<name>/SKILL.md` を基本とし、必要に応じて `references/`（prompt template、rubric、例）と `scripts/` を持ちます。poteto-mode だけが `playbooks/`（24 本）、`references/bugbot-triage.md`、`scripts/` を持っています。

### 6.2 frontmatter の慣習
- 大半の skill は `name`、`description`、`disable-model-invocation: true` の 3 つです。自動発火させず、明示呼び出しか poteto-mode からのルーティングで使う設計です。例外として setup-pstack にはこのフラグがありません。
- poteto-mode だけが Cursor 固有のキーを持ちます: `mode: true`、`icon: crown`、`color: yellow`、`reminder: New task? Playbook match or rigor needed -> apply /poteto-mode. ...`（毎ターン注入されるリマインダ）。
- description は「何をするか＋トリガー語句（"arena this"、"/swarm" など）＋使わない条件」の形です。principle-* の description は「Apply when ...」で始まり、適用条件が主語になっています。

### 6.3 poteto-mode のルーティング
- SKILL.md の構成は Non-negotiables（トリガー → skill の対応表）/ Principles（inline index）/ Autonomy / Subagents / Writing the reply / Comments / Playbooks（一覧）です。
- ルーティングの手順:
  1. タスクを playbook に照合し、その `playbooks/<x>.md` を開く。
  2. 手順を逐語でコピーして todolist の先頭に置く。
  3. やらない手順も消さずに `skip: <reason>` を付けて残す。
- 例外ルート: 大規模・横断的な仕事、ユーザーが離席して後で信頼したい仕事、合う playbook が無い仕事は figure-it-out skill（その場で専用 playbook を設計する）へ回します。複数日の常駐プログラムは orchestrate へ回します。
- 全 playbook は "Opening a PR" で終わり、playbook ごとに Reply の必須内容を定めています。

### 6.4 Principles index の埋め込み方
- poteto-mode 本文に、principle を 6 群（Core / Architecture / Verification / Delegation / Meta）に分けて列挙しています。各行は「名前（**leaf skill 名**）。いつ適用するか。要点 1 文」の 3 点セットです。
- 規則:
  - 適用する principle は leaf の SKILL.md を全文読む。
  - reply では、判断に効いた principle と、それが変えた具体的な選択を名指しする。
  - 引用できるのは、このセッションで leaf を読んだ principle だけ。
- index には principle-attack-the-premise と principle-test-behavior-not-implementation も載っています。この Claude Code 環境の skill 一覧（open-pstack 版）ではこの 2 本が見当たりませんでした（7.2 の 6 参照）。

### 6.5 skill 間の参照
- 本文中の参照は太字の skill 名（"the **arena** skill's Phase B"、"the **prove-it-works** principle skill"）と、相対パスのリンク（`../principle-laziness-protocol/SKILL.md`、`references/runner-prompt.md`）で書かれています。
- 他の skill を再定義せず委譲します。例えば eval は arena の Phase B/C を、architect は arena を、hillclimb は show-me-your-work を、arena は separate-before-serializing と redesign-from-first-principles を参照します。authoring-a-skill には "Delegate to other skills by path. Don't restate." とあります。
- 外部 plugin への依存もあります。cursor-team-kit の `deslop`、`control-ui`、`control-cli` と、Cursor 組み込みの `create-skill`、babysit です。

### 6.6 scripts
- `poteto-mode/scripts/check-plan.mjs`（186 行）: multi-phase plan の lint です。固定文、見出し順、sub-block、perf 4 項目、checkbox 形式を検査し、`file:line: message` の形で出力します。
- `poteto-mode/scripts/orch/`（orch.ts、store.ts、orch.test.ts）: orchestrate の状態台帳を扱う bun 製 CLI です。unit、verdict、frontier、gate を TSV と JSON で保持します。spawn や wait はしません（エージェントの操作はすべて Task tool で行う）。
- `poteto-mode/scripts/watch-pr/`（github.ts、policy.ts、render.ts、types.ts、テスト 3 本）: PR の状態を監視し、イベントで起こす watcher です（babysit と shipping で使う）。
- `poteto-mode/scripts/bootstrap.ts`: `package.json` と `bun.lock` の sha256 を install key にして、依存（commander 14.0.0、固定版）を必要なときだけ入れます。
- `poteto-mode/scripts/worktree-audit.sh`: worktree を読み取り専用で棚卸しします。削除は人間の判断に委ねます。
- `show-me-your-work/scripts/log.sh`: TSV に 1 行追記する helper です（2.11）。
- 検証系の skill（create/maintain-verification-skill、tdd、eval）は script を持たず、手順の文章だけで成り立っています。検証の道具は、対象プロジェクト側に生成させる方針です。

---

## 7. 取り入れる価値が高いもの / 取り入れないほうがよいもの

### 7.1 取り入れる価値が高いもの
1. **undefined テストと、禁止される 5 形（test-behavior-not-implementation）。** 判定が機械的なので、vetdd のテスト規約にそのまま使えます。さらに encode-lessons-in-structure に従えば、lint か review チェックリストに落とせます（例 `toHaveBeenCalled` だけの assertion を検出する）。ユーザーの「80% カバレッジ」規約は数字だけで中身を測れないので、この品質基準で補う価値が高いです。
2. **証拠ラベルと「Inconclusive/wrong-surface は pass ではない」。** reply の各主張に Measured / inferred / guess を付ける規則と、blast-radius の確信度 5 段階は、ユーザーの「検証は Claude 自身が行う」「計測器を先に検証する」方針とよく噛み合います。低コストで導入できます。
3. **create-verification-skill の生成テンプレート。** Launch / Doctor / Drive / Evidence / Cleanup の 5 節＋ Helpers と、4 つの H2 を持つ feature map は、Claude Code の `.claude/skills/verify-<app>/` へほぼそのまま移せます。「生成した skill を 1 周回して証拠が cleanup 後も残るか確かめる」ゲートと、maintain 側の 3 値の結論（clean / changed / blocked）も一緒に取り込むのがよいです。
4. **Eval のブラインド化規則。** 禁止語リスト、自然なユーザー prompt、自己申告でなく transcript と成果物で chain を採点する、judge にはモデル名を伏せる、2 variant は 1 人の judge が 1 回の pass で採点する、という規則です。skill や prompt の改変を評価するときの最小セットとして完成度が高いです。Claude Code では transcript が `~/.claude/projects/<slug>/*.jsonl` にあるので、パスだけ置き換えれば使えます。
5. **Hillclimb の計測規律。** harness の感度を証明してから凍結する、median of N、試行回数の下限付き stop predicate、1 変更 1 計測で keep か revert、`decision.tsv` の列定義。eval 駆動の反復ループの骨格としてそのまま流用できます。
6. **書いた者と判定する者の分離、別系統モデルでの判定、patch-id による verdict の有効性管理。** 「CI green は verdict ではない」という考えは、ユーザーの `/ai-review` ゲート（own-review と Codex の並列ブラインド）と同じ方向で、これを補強します。とくに patch-id で rebase 後も verdict を再利用できるかを判定する規則は、`.review-reports/latest.json` の `head_sha` 一致検査より精密で、導入の余地があります。
7. **failing repro を fix より前の commit に置く納品順（sequence-verifiable-units）。** reviewer が「red から green へ」を再生できます。コストはほぼゼロです。
8. **interrogate の lead-judgment。** Act on / Consider / Noted / Dismissed の 4 分類、Act On を 5 件以下に抑える目安、Dismissed を信頼の仕組みとして示す方法です。多モデルレビューを突き合わせる工程にそのまま使えます。
9. **show-me-your-work の `log.sh`。** formula injection への対策が入っていて安全で、transcript との照合と別系統モデルによるレビューも手順化されています。
10. **attack-the-premise。** 同じ前提の fix が 2 回落ちたら止まって census を取る、という停止規則です。デバッグの空回りを防ぐ具体的なトリガーになります。

### 7.2 取り入れないほうがよいもの・注意点
1. **tdd skill の適用範囲。** pstack の tdd は「バグ修正で、安価なテスト経路があるときだけ」で、Refactor 段がなく、feature 開発の TDD を扱っていません。ユーザーの CLAUDE.md は「原則 TDD」「検証を先に用意する」なので、vetdd では tdd skill を土台にせず、手順 4（意図した理由で落ちることを確認）と Guardrails と「悪いテストより無いテスト」だけを部品として取るのが妥当です。ただし「Prefer no new test over a bad test」はユーザーの 80% カバレッジ規約と緊張関係にあるので、どちらを優先するか明文化が要ります。
2. **multi-phase-plan の「PR ごとに 10 live lane＋perf＋2 以上の監査 lane」。** Cursor のクラウド VM（`environment: "cloud"`）が前提で、コストが非常に大きいです。個人規模の運用では lane 数を可変にし、trunk 回帰 lane を 1 本だけ必須にする程度が現実的です。
3. **Autonomy の "Just do it"。** team chat や ticket の更新などの外部アクションも確認なしで進める方針は、ユーザー環境の安全規則（メッセージ送信は明示許可が必要）と衝突するので、そのまま持ち込まないでください。irreversible 操作の「Always pause」リストは取り入れてよいです。
4. **prose の書式規則**（long dash 禁止、文中コロン禁止、unslop）は英語向けです。日本語の出力規約はユーザーの `output-format.md` が正本なので、取り込みません。
5. **Cursor 固有で Claude Code に移らないもの:**
   - `~/.cursor/rules/pstack-models.mdc`（`alwaysApply`）による role → モデル設定。Claude Code では CLAUDE.md の `@include` か agent 定義で代替します。
   - Task tool の `readonly`、`environment: "cloud"`、`cloud_base_branch`、`subagent_type: generalPurpose` と、`grok-*` / `gpt-*` の slug を `model` に直接渡すこと。Claude Code の Agent tool で native に選べるのは Claude 系モデルだけで、他系統は `codex exec` などの外部 CLI 経由になります。
   - frontmatter の `mode: true` / `reminder` / `icon` / `color`、Cursor 組み込みの `create-skill` と babysit、`AskQuestion`（Claude Code では `AskUserQuestion`）、`/goal`、Bugbot、Origin forge。
   - cursor-team-kit の `control-ui`、`control-cli`、`deslop` への依存。Claude Code では Playwright MCP、Browser pane、自作 verify skill で置き換える必要があります。
   - `agent-transcripts/` のパス（Claude Code では `~/.claude/projects/<slug>/`）。
   - `disable-model-invocation: true` は Claude Code にもあるので、そのまま移せます。
6. **既存の移植版との重複。** この環境には `~/.claude/plugins/marketplaces/open-pstack/plugins/pstack`（open-pstack v1.2.0、"Ported from cursor/plugins/pstack for Claude Code and Codex"）が既に入っています。setup-pstack は `~/.claude/pstack-models.md` を CLAUDE.md から `@include` する方式で、role を `claude:claude-fable-5@max`、`codex:gpt-5.6-sol@max`、`grok:grok-4.6@xhigh` のような provider 付き記述で指定し、Claude lane は `pstack-<model>-<effort>` agent で動きます。vetdd で多モデルの仕組みを一から作る前に、この移植版の dispatch 部分を再利用できないか確認する価値があります。また、ユーザーの既存 skill `/ai-review`（Opus と Codex の並列ブラインド）と `/3rd-review`（Fable と GPT）は interrogate と機能が重なるので、役割の線引きが必要です。
7. **principle の数（23 本）と、playbook の細かな規定（shipping / autopilot / orchestrate）。** 常駐オーケストレーションと大量スタック PR を前提にした部分は、vetdd の 3 つの駆動（検証・テスト・評価）の範囲を超えます。取り込む対象は、上の 7.1 の部品と、prove-it-works、sequence-verifiable-units、build-the-lever、test-behavior-not-implementation、fix-root-causes、attack-the-premise、encode-lessons-in-structure の 7 本に絞るのが妥当です。
