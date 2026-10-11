# Swarm

One writer per unit, each in its own worktree, each recording its own red and green; the parent integrates the units in series and closes on the integrated tree. Use it when `parallel/select.md` answers Q1 no and Q2 yes.

## Before any worker starts

- **Agreement.** The shape and the units are part of the step 2 agreement (SKILL.md, Q3 "parallel shape"): name each unit, its slice id, its oracle file, and the files it may change, and say the units touch no file in common and change no contract another depends on. That agreement is the hearing principle 8 asks for before concurrent writes. When the shape is decided only after step 2, stop once and ask it with `AskUserQuestion` before any worker starts.
- **Budget.** At most 3 concurrent workers unless Q3 says otherwise. The parent does not write while workers write.
- **One unit, one slice.** Each unit has its own slice id, its own oracle file, and a red of its own. A unit that cannot go red on its own is not a unit: merge it into another or run the task `single`.
- **The contract first.** When units meet at a shared point (a new option, a dispatch, a type), the parent writes and commits that contract before any worker starts: the signatures and stubs that do nothing yet (a function that returns its input), with the existing oracles still green. Each unit then fills in its own file behind the contract, and no worker changes the contract. Without it, units that share a file are not units.
- **A clean main tree.** Commit or set aside the parent's work first: every worktree starts at the same commit, and the merges in step 4 need a tree with no uncommitted change outside `.vetdd/`.

## Steps

1. **Make the worktrees.** From the main repository, for each unit: `"$VETDD/scripts/worktree.sh" add <slice> [--link node_modules] -- <the unit's test command>` (it prints the path: `../<repo>.vetdd-wt/<slice>`, branch `vetdd/<slice>`). The command, with paths relative to the repository root, is the one the unit's brief gives the worker; it is recorded in the main repository, where no worker writes, for the integrated runs. `--link` shares an ignored directory such as `node_modules` instead of installing it again (never a `.env` file): every worker and the parent then read and write the same directory, so a worker can change what the others run from it, so point a tool's cache elsewhere (vitest `--cacheDir`, a per-worktree `TMPDIR`) when it writes there. Then record the unit's first agreement inside its worktree, so the worker's evidence holds it: `cd <worktree> && "$VETDD/scripts/oracle-version.sh" <slice> --version <v> --change initial --reason-file .vetdd/notes/<slice>-agreement.md` (write the note there first).
2. **Start the workers.** One subagent per unit, all in one message with `run_in_background`, each with a brief built from `references/subagent-brief.md` in the role `swarm author`, its workspace the unit's worktree, and a model from `scripts/models.sh author`. Each records `before` (target_failure), makes the smallest change, records `after` (pass), runs the undefined-imports audit of test mode "Audits" (or records why it does not apply), and commits on its branch.
3. **Read each result.** When all have reported, read each worker's report. Never run git or a vetdd script inside a worker's worktree: its `.git` and `.vetdd` are the worker's and could run code as you (`worktree.sh` reaches a worktree only through the git directory the main repository keeps for it). A unit whose report shows no red, no green, or no commit goes back to a new worker in the same worktree; it does not block the others.
4. **Integrate in series.** In the main repository, for each unit in the agreed order:
   1. `git merge --no-ff --no-edit vetdd/<slice>`.
   2. `"$VETDD/scripts/worktree.sh" remove <slice> --keep-branch`: it brings back the unit's evidence, verify artifacts, and notes (refusing any link among them), and removes the worktree; the branch stays until the unit's integrated runs pass. Then check the unit's evidence in the main repository: `"$VETDD/scripts/check-evidence.sh" --before-close <slice>` (the mutation audit waits for Close).
   3. Record `integrated` for every unit merged so far, from the repository root: `"$VETDD/scripts/evidence.sh" <slice> integrated --rerun [--test-report jest-json:<the unit's report path>]` runs the command recorded in step 1, so none is typed again (`--test-report` when the unit's runs recorded one; `--rerun` stops without it).
   When every unit is in and green, delete the merged branches: `git branch -d vetdd/<slice>`.
   If `remove` stops on a file of the same name with different content (two units wrote the same artifact or note), undo the merge (`git reset --hard ORIG_HEAD`) and treat the unit as a conflict.
   If the merge conflicts (`git merge --abort`, then `worktree.sh remove <slice> --keep-branch` to take its evidence back) or an `integrated` run of any unit is red (`git reset --hard ORIG_HEAD`, which leaves `.vetdd/` alone, then record `integrated` again for the units merged before it), do not fix it by hand: the split was wrong for that unit (`parallel/select.md` Q2). Note it in the reply's Attention; its branch is kept and holds its commits (delete it with `git branch -D vetdd/<slice>` once noted). After the other units are in, run it again as a new unit with a new slice id (`<slice>-2`) from the integrated tree, through steps 1–4. Leave the abandoned slice id out of Close.
5. **Close** as the mode file says, on the integrated tree, for every merged slice id: Close step 1's `integrated` runs (each slice's own command with `--rerun [--test-report ...]`, and every coverage oracle the agreement named, such as the whole suite and the type check), the mutation audit of each slice, `check-evidence.sh <every slice>`, and one judge layout with every slice (`judge-layout.sh ... <every slice>`).

## Rules for workers

- Work only inside the unit's worktree and change only the unit's files.
- Commit on the unit's branch; never push, merge, rebase, or switch branches.
- Never touch the stash, global git config, or shared external services (a fixed port, a shared database): a unit that needs one is not independent of the others.
- Record every run through `evidence.sh` in the worktree; never edit `.vetdd/`.

## Time

Report how long each step took (the wall clock from the first `worktree.sh add` to the last `worktree.sh remove`, and each worker's time), so the swarm's cost is measured against running the units in series.
