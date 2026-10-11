# Parallel shape selection

Answer two questions, before the agreement of SKILL.md step 2 when you can, so the agreement covers the shape (Q3). Write the result in the todo list as `parallel: <shape> because <reason>`.

- Q1. Does the deliverable have to converge on one design (new types, module boundaries, or data structures are being decided)? Additions that follow an existing shape answer **no**.
- Q2. Can the task be split into units that touch different files, change no contract another unit depends on, and each own a red test? If any unit fails one of these, answer **no**.

| Q1 | Q2 | shape |
|---|---|---|
| no | no | **single**: one writer (you or one subagent), one judge |
| yes | no | **arena**: N candidates for the same task, separate write targets, one judge picks, the parent grafts (`parallel/arena.md`) |
| no | yes | **swarm**: one writer per unit in its own worktree, each records its own red and green, the parent integrates in series (`parallel/swarm.md`) |
| yes | yes | **arena, then swarm**: pick the design in an arena, split the chosen design into units |

Rules that apply to every shape other than single:

- Hearing first (principle 8): before two or more parties write concurrently, agree on the shape and the units; ambiguity multiplies by N. When the shape is known at step 2 of SKILL.md, this is part of that agreement (Q3); otherwise stop once and ask before any worker starts.
- One writer per worktree; readers may share. The parent does not write while workers write unless it was counted in the hearing.
- Workers never touch the stash, global git config, or shared external services.
- Before removing a worker's worktree, copy `.vetdd/evidence/<slice>/` into the main repository. If this is skipped, `check-evidence.sh` on the integrated tree fails with `schema: no meta.json for this slice`, and that failure is correct.
- Completion is judged on the integrated tree with `integrated` evidence, never on a worker's slice.

`parallel/swarm.md` is available. Until `parallel/arena.md` exists, an arena (and arena, then swarm) ends the task in `blocked` with the reason "arena not yet available"; do not improvise a fan-out.
