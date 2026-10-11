# Arena

N runners build the same agreed task, each its own way, in their own worktrees (lanes); only the lanes whose own oracle is green reach a judge of a different model family, who compares them and picks one; the parent merges it and grafts what was better elsewhere. Use it when `parallel/select.md` answers Q1 yes (the task must converge on one design: new types, module boundaries, data structures). "Arena, then swarm" runs this first, then splits the chosen design into units (`parallel/swarm.md`).

Workers run as the same user as the parent; what `parallel/swarm.md` "What it protects" says holds here too.

## Before any runner starts

- **Agreement** (SKILL.md step 2, Q3): the shape, the number of lanes (default 3: one per model of `scripts/models.sh arena-runner`), the shared oracle file and its command, and the **agreed changes**: the future changes the design must be ready for (`references/arena-rubric.md` criterion 4 grades each design against them). That agreement is the hearing principle 8 asks for before concurrent writes.
- **The oracle first.** The parent writes the agreed oracle (the test every lane must pass, through the public interface), checks that it fails for the agreed reason, and commits it; the existing oracles stay green. Every lane starts from that commit (the base) and no lane changes the oracle file.
- **A clean main tree**, as for swarm.

## Steps

1. **Make the lanes.** Name each lane `<slice>-<random>` with `printf '%s-%s\n' <slice> "$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"`: the id travels inside its candidate, so it must say nothing about the runner or the order (`arena-layout.sh` refuses a lane id without a random suffix). Keep which lane is which runner for the synthesis note only. For each lane: `"$VETDD/scripts/worktree.sh" add <lane> [--link node_modules] -- <the oracle command>`, then its first agreement inside the lane, as swarm step 1 does (`oracle-version.sh <lane> --version v1 --change initial --reason-file .vetdd/notes/<lane>-agreement.md`, run in the lane's worktree).
2. **Start the runners.** One subagent per lane, all in one message with `run_in_background`, each with a brief from `references/subagent-brief.md` in the role `arena runner` and its own model from `scripts/models.sh arena-runner` (one model per lane, in the listed order). The runners do not see each other's work.
3. **Bring each lane back.** When all have reported, for each lane: `"$VETDD/scripts/worktree.sh" check <lane>`, then `"$VETDD/scripts/worktree.sh" remove <lane> --keep-branch`. A lane `check` refuses is out of the arena; name it in the reply's Attention.
4. **Gate and lay out.** `"$VETDD/scripts/arena-layout.sh" --out <a new directory of your own outside the repository> --base <the oracle commit> [--allow-secrets 'c*/artifact/tests/<glob>:<kind>'] [--allow-binary <path>] <every lane>` (the allowances only as for any judge layout, for what a human confirmed). It checks each lane's evidence in a worktree it makes itself, leaves a lane that is not green out (`<out>/gate.txt`), lays out the green ones as `c1` .. `cN` in a shuffled order (`<out>/variants.json` maps label to lane), and removes the review worktrees. When only one lane is green, it prints that lane (also in `<out>/chosen`) and no judge command: it is chosen without a comparison, so skip step 5. A lane `check` refuses here stays out too (`gate.txt`). Exit 5 means no lane is green: a stall. Until the stall exits exist, end the task `blocked`, with `gate.txt` and each lane's red log.
5. **Judge.** Run the `judge.sh` command it prints (`--rubric references/arena-rubric.md --rubric-version 1`). The winner is the label with the highest total; read its lane from `variants.json`. On a tie, ask the human once (`AskUserQuestion`), with each tied lane's design note.
6. **Merge the winner**, as swarm step 4 merges a unit: `worktree.sh check <lane>`, `git -c core.hooksPath=/dev/null -c core.fsmonitor= merge --no-ff --no-edit --no-overwrite-ignore vetdd/<lane>`, `evidence.sh <lane> integrated --rerun [--test-report jest-json:<the lane's report path>]` (when the lane's runs recorded one), `check-evidence.sh --before-close <lane>`. Then `git branch -d vetdd/<lane>`.
7. **Graft** what the judge cited as better in a losing lane (its criterion 3 or 4 evidence), one part at a time, as a slice of its own in the main repository (`<slice>-graft-<n>`, run `single`): its red (a `before` that fails for the reason the part fixes, or `calibrate.sh unfix` once it is in), the part, its green. Never paste a losing lane's change without its own red and green. Delete each losing branch once its grafts are in or none is taken (`git branch -D vetdd/<lane>`).
8. **Record the synthesis** in `.vetdd/notes/<slice>-arena.md`: the lanes and their runners' models (the only place that map is kept), `gate.txt`, the label map, the winner and the judge's file, each graft and its slice id, and the parts left out with why. It stays on the machine: the reply cites it as a local file, labeled inferred, never Measured (the final judge cannot open it).
9. **Close** as the mode file says, on the integrated tree, for the winning lane's slice and every graft slice (the final judge, with the final rubric, as for any delivered change).

## Rules for runners

As for swarm workers (`parallel/swarm.md` "Rules for workers"), and: never change the agreed oracle file; add no behavior the agreement does not name (in the 2026-10-11 dogfood all three runners added a defensive error the agreement did not ask for, and the final judge failed the chosen lane on it); write the design note at `.vetdd/notes/<lane>-design.md` with the sections Design, Why, Agreed changes (for each agreed change, the file and symbol that would change), and Evidence (each claim labeled Measured, inferred, or guess).

## Weak divergence and time

If the green lanes are nearly the same design, say so in the reply's Attention: the 2026-10-11 decision is to start with Claude runners only and to discuss adding a Codex runner when the designs do not differ. Report how long each step took (the runners, the gate and layout, the judge), as swarm does.
