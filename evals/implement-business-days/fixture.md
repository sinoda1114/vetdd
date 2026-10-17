# fixture: implement-business-days

Each workspace is a copy of `fixtures/ts-kata` at the commit under evaluation, as an independent git repository with one commit, under a neutral path such as `~/tmp/invoice-app-<n>/` (no eval words or model names in the path, parents included).

1. Copy the files git tracks under `fixtures/ts-kata`, except `KATA.md` (the answer key) and `.claude/` (an earlier verify skill).
2. `git init`, `git add -A`, `git commit -m "invoice app"`, then `npm ci` (the fixture's `.npmrc` sets ignore-scripts).
3. Place the variant's skill at `.claude/skills/vetdd/`:
   - `full`: the files git tracks under `skills/vetdd` at the commit under evaluation.
   - `no-principles`: the same, without `principles.md`, and with the "Read `principles.md` in full now ..." paragraph of SKILL.md step 0 removed (step 0's heading becomes "Locate the skill").
4. Place `CLAUDE.md` at the workspace root: "For any change to this project's code, follow the skill in `.claude/skills/vetdd/SKILL.md`. Its base directory is `<absolute path of .claude/skills/vetdd>`." Commit nothing further: the placed files stay untracked, as a user's local setup would.
5. Run `<skill>/scripts/setup-project.sh` in the workspace.
6. `check-blind.sh <workspace> --placed CLAUDE.md --placed .claude/skills/vetdd --file evals/implement-business-days/task.md --file <rendered brief> --allow-words '.claude/skills/vetdd/*:<the evaluation words>'`: the skill's own text is the product under evaluation and holds those words (its modes are named test and eval); a human confirmed this exception (Frame, 2026-10-17).

## Collecting a workspace (step 5)

`sanitize-candidates.sh` copies the whole workspace, so before it runs, in each workspace:

1. Remove the placed files (`.claude/` and `CLAUDE.md`): the judge must not see which variant ran, and `principles.md` would show it.
2. Write `diff.patch`: `git add -N` the new files outside `.vetdd/`, then `git diff --no-ext-diff --binary HEAD -- . ':(exclude).vetdd' ':(exclude)diff.patch' ':(exclude)reply.md'`, then `git reset -q` (only the intent-to-add entries change, and the parent removes them).
3. Write `reply.md`: the candidate's reply as `references/reply-format.md` defines it, verbatim: the part of its final message from the `## Result` heading (or the same heading in the candidate's language) to the end of its `## Attention` section, without any summary placed before it or block placed after it (from 2026-10-17 19:40; earlier runs kept the whole message).
