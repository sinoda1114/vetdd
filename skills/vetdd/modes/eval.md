# eval mode

Oracle: a blinded judge of a different model family, scoring N candidates against a rubric the candidates never see. Governing principles: 1, 2, 6, 7, 10. Used for changes to skills, prompts, and agent instructions, and as the final judge in test and verify modes.

Two uses share the same scripts:

- **A/B eval** (this mode): compare variants of a skill or prompt by letting candidates work a task under each variant.
- **Final judge** (test and verify modes call it): one label, the delivered diff and evidence, verdict pass/partial/fail.

## Layout

```
evals/
  index.tsv                          append-only: ts  eval_id  run_id  labels  winner  confidence  judge_family  promoted
  <eval-id>/
    task.md                          the candidate prompt: an organic request, goal only, no meta
    rubric.md                        judge only: 3–6 criteria, each observable, each with what 0/1/2 mean
    fixture.md                       how to build a candidate workspace (which fixture, which files to place per variant)
    baseline                         run_id of the accepted baseline, or absent
    runs/<run-id>/                   run-id = YYYYMMDD-HHMM
      variants.json                  {"c1": "<variant name>", ...}; written by the parent, NEVER copied into the judge's directory
      candidates/<label>/artifact/   the candidate's output files (sanitized copy)
      candidates/<label>/evidence/   the candidate's .vetdd/evidence (sanitized copy)
      candidates/<label>/transcript.jsonl   the candidate's transcript (sanitized copy)
      blind-words.txt                variant, worktree, and branch names, one per line (judge.sh --extra-words)
      rubric.md                      copy of the rubric at this version
      judge.json                     verdict, schema schemas/verdict.schema.json
      judge.json.meta.json           judge model, effort, time, and the path of its log
      synthesis.md                   parent's reading, agreement with the judge, promote decision
```

## Blinding rules (fixed)

1. Candidates never see the words `eval`, `test`, `judge`, `experiment`, `rubric`, `score`, `compare`, `benchmark`, `candidate`, `arena`, `variant`, `baseline` in what the eval puts in front of them: the workspace name, the prompt (`task.md` and the brief), and the files the eval placed in the workspace. The project's own files are not the eval's doing and are not checked (a project with tests says `test`). `$VETDD/scripts/check-blind.sh <workspace> --placed <path> --file <prompt>` enforces the list on exactly those; it also flags model names, extra words (worktree or branch names), and any symlink in the workspace. It checks only the workspace's own name, so the directories above it must be neutral too.
2. `task.md` reads like a real user request. It states the goal, not what will be measured.
3. Candidates do not know other candidates exist. Each works in its own directory and its own worktree if it writes to a repository.
4. Chain-following is graded from what the candidate really read (its transcript) and from the shape of its output, never from its own claims.
5. The judge sees sanitized copies only, labels only, and is told nothing about which label is which variant or which one is expected to win. `variants.json` stays outside the judge's directory: `judge.sh` runs the judge in a private copy of the label directories and the rubric, so no relative path from the judge's directory reaches the run directory.
6. One judge grades every label in one pass with one rubric. Judging variants in separate calls is not a comparison.

## Procedure

1. **Frame.** Write `task.md`, `rubric.md` (version 1), and `fixture.md`. Agree on the rubric with the human (principle 1a): the rubric IS the oracle. Each criterion names an observable (a file exists, a test is red then green in evidence, a literal value appears), never an impression.
2. **Calibrate the rubric** (principle 2). Before any real run, grade one known-good and one known-bad artifact with `judge.sh` (a hand-made pair is fine). The known-bad must score lower. If not, revise the rubric (version 2) before running candidates.
3. **Prepare workspaces.** For each variant, build a candidate workspace per `fixture.md` under a project-looking name that says nothing about the eval (`~/tmp/invoice-app-<n>/` style; not the eval id, no forbidden words, neutral parent directories), and place the variant's files (for a skill: under `.claude/skills/<name>/`). Render the prompt the candidate will get (the brief from step 4 with `task.md` in it) to a file outside the workspace. Then run `$VETDD/scripts/check-blind.sh <workspace> --placed <each placed path> --file evals/<eval-id>/task.md --file <rendered prompt>`: it checks the workspace name, the placed files, and the prompt, not the fixture's own files. Fix every hit before running candidates.
4. **Run candidates** as subagents, one per workspace, in the background, same prompt (`task.md` verbatim), brief from `references/subagent-brief.md` with the Oracle section replaced by "follow the project's own instructions". Model: `$VETDD/scripts/models.sh author` for every label unless the eval is about models. Wait for all to finish; a dropout is recorded as inconclusive, not rerun silently.
5. **Collect and sanitize.** For each label, run `$VETDD/scripts/sanitize-candidates.sh --src <workspace> --label <cN> --dest runs/<run-id>/candidates --variants runs/<run-id>/variants.json --transcript <transcript file> [--strip <worktree or branch name>]...`. It copies the outputs, `.vetdd/evidence`, and the transcript into `candidates/<label>/`, and redacts, as whole words, model names, the workspace name, its branch, every variant name, and each `--strip` word (at least 4 characters; `main`, `master`, `HEAD`, and git's default branch are never stripped). It refuses a workspace that contains a symlink. Then write `runs/<run-id>/blind-words.txt`: the variant names (`jq -r '.[]' runs/<run-id>/variants.json`) and the worktree and branch names, one per line. Run `check-blind.sh runs/<run-id>/candidates --profile judge --extra-words runs/<run-id>/blind-words.txt`: the judge knows it is judging, so only origins, model names, and these words are hidden from it (the candidate profile, with the evaluation words, applies to workspaces in step 3). `judge.sh` repeats this check on its private copy.
6. **Judge.** `$VETDD/scripts/judge.sh --rubric runs/<run-id>/rubric.md --candidates runs/<run-id>/candidates --out runs/<run-id>/judge.json --eval-id <id> --run-id <run-id> --rubric-version <n> --extra-words runs/<run-id>/blind-words.txt [--conditions <file>]`. It refuses (exit 4) when the copy, the conditions, the extra layout, or the ids reveal an origin or a model. It prints the path of the judge's own log (`.vetdd/judge-logs/<eval-id>-<run-id>.log` at the git root, outside the run directory) and runs `$VETDD/scripts/check-verdict.sh` on the verdict: schema, every label scored on every criterion, every score cited, the ids and rubric version as given, and each label's verdict and the winner recomputed from the scores (exit 5 on a problem).
7. **Synthesize.** Read every candidate yourself, criterion by criterion, before opening `judge.json`. Then compare. Write `synthesis.md`: your scores, the judge's, where they differ and why, and the decision. Append one line to `index.tsv`.
8. **Decide.** Promote a variant only when: the judge's winner and your reading agree, confidence is `mid` or `high`, and no criterion regressed against the baseline run. Otherwise `inconclusive`: rerun once with fresh workspaces (max 3 runs per eval); if still inconclusive, keep the baseline and record why. A tie is inconclusive. Never revise the rubric after seeing a result to change that result (principle 6); a rubric revision is a new version, re-agreed, and regrades every run of this eval.

## Regression

When a skill or prompt under `skills/` changes, rerun every eval under `evals/` and compare each winner and each label's totals with its `baseline` run. A baseline that loses is a regression; the change does not ship until it is explained in `synthesis.md` and either fixed or accepted by the human.

## Final judge (called from test and verify modes)

One label `c1`, in the directory that `references/final-judge-rubric.md` "Layout" defines; that file is also the rubric. Verdict `pass` is required to report done; `partial` goes to Attention with the judge's citations; `fail` reopens the task.

## Persist

`transcript.jsonl` for a subagent spawned with the Agent tool is the task output file the harness reports; for a full session it is `~/.claude/projects/<project-slug>/<session>.jsonl`. Copy, never move: `sanitize-candidates.sh --transcript` copies it through the same redaction as the artifact. Transcripts are the only record of what a candidate really read.
