---
name: vetdd
description: "Verification / Eval / Test driven development. Use for any change to product code or tests (a bug with a symptom, a new behavior, a refactor, a config or wiring change), for proving that an app behaves as agreed by driving it, and for evaluating a skill or prompt change blind. Triggers: /vetdd, \"TDD で\", \"テスト駆動で\", \"検証駆動で\", \"再現してから直して\", \"eval して\", \"判定器\", \"oracle\", \"red green\". Builds the oracle first, records red and green as evidence files, and hands the final verdict to a different model family. Not for pure questions, prose, or one-line edits with no behavior."
---

# vetdd

One backbone, three modes. The backbone: agree on the oracle → build and calibrate it → measure before → change → measure after, on the integrated tree. The mode only changes what the oracle is.

## 0. Read the principles and locate the skill

Read `principles.md` in full now. Every later step assumes it. Cite a principle by its bold name only after reading it.

`$VETDD` in every file of this skill means this skill's base directory: the absolute path shown as "Base directory for this skill" when it loaded (normally `~/.claude/skills/vetdd`). It is not an environment variable. The Bash tool keeps no variables between calls, so start every command that calls a vetdd script with `VETDD='<that absolute path>' &&` (single quotes, so spaces and `$` in the path are taken literally; write a `'` in the path as `'\''`), or write the absolute path in place of `$VETDD`. A command that expands it to empty calls `/scripts/…`, which does not exist. Scripts run from the target project's root, never from the skill's directory. Relative paths such as `references/…` and `modes/…` are files inside `$VETDD` to read.

## 1. Classify the task and pick a mode

| the task is | mode | oracle | file |
|---|---|---|---|
| a defect with a symptom, a new behavior, a refactor of code that has or can have tests | **test** | a failing test at an agreed seam | `modes/test.md` |
| proving an app or CLI behaves as agreed by driving it; a change exempt from unit tests (config, wiring, glue, type annotations) | **verify** | a verify script that drives the real surface | `modes/verify.md` |
| a change to a skill, prompt, or agent instruction whose effect is on agent behavior | **eval** | a blinded judge of a different model family, scoring against a rubric | `modes/eval.md` |

Pick one. A task that needs two (a feature plus proof on the live surface) runs test first, then verify on the integrated tree. State the mode and the reason in the first line of your todo list.

If the task is none of these (a question, prose, a one-line edit with no behavior), say so and do not use vetdd.

## 2. Agree on the oracle (principle 1a)

Before any product code, present the agreement through `AskUserQuestion`: exactly four questions in one call (the tool's limit), recommended answer first in each, marked "(推奨)". Investigate first so the human only decides; never ask what you can read from the repo.

| question | covers |
|---|---|
| Q1 acceptance | the behavior as an exact assertion, with its expected value and that value's source (a hand-worked example, the spec, a known-good output) |
| Q2 seam | where the oracle sits, in the format of `references/seam-proposal.md` |
| Q3 scope and run | which existing oracles must stay green (name the command); out of scope and known blind spots; target environment and the run conditions that can change the result; budget (number of subagents, retry cap default 3, wall-clock limit if any) |
| Q4 what leaves the machine | external actions authorized in advance, naming what is sent and where (default: what `references/final-judge-rubric.md` "Layout" lists, to the judge's provider: the diff, the reply draft, the `check-evidence.sh` output, the oracle files, each slice's `meta.json` and red-run log; all other run logs stay local). `meta.json` records each command's arguments, so a secret passed on a command line would leave with it: pass secrets through the environment, never as arguments |

Q3 carries one recommended default for all four of its parts when the change is small and reversible; break it out into a second call only when the human rejects the default. Record the answers in the reply's Oracle section.

Once the slice id is decided (step 4) and before the slice's first run, record the first agreement in the evidence as well: `"$VETDD/scripts/oracle-version.sh" <slice> --version <v> --change initial --reason-file <path>` (check-evidence rule 8d then asks for a recorded reason on the final version when it is a later one). Write the text to a file under `.vetdd/notes/` with the Write tool (the tree hash leaves `.vetdd/` out, so it never counts as a change) and pass the path (`--reason-file`, `--question-file`, `--answer-file`): text that came from an issue, a page, or a file must never be typed into a shell command, where a quote in it would end the quoting and run the rest. `--reason '<text>'` is only for text you wrote yourself that holds no quote.

If the human says the task is unclear, stop vetdd and run a hearing first (`Call the Skill tool with "hearing"` when it exists; otherwise ask in chat).

## 3. Choose the parallel shape

Read `parallel/select.md` and apply its table. Most tasks are `single`. Before any shape with two or more concurrent writers (counting yourself), hold the hearing required by principle 8, then read `parallel/arena.md` or `parallel/swarm.md`.

## 4. Run the mode

Read the mode file chosen in step 1 and follow it. Every oracle run goes through `"$VETDD/scripts/evidence.sh"`; never run the oracle bare when its result matters. Every subagent gets a brief built from `references/subagent-brief.md`, with a model from `"$VETDD/scripts/models.sh" <role>`, and with `$VETDD` written out as an absolute path (a subagent has none of your context).

## 5. Close

1. Record every slice as `integrated` on the final tree (the mode file says how), then run `"$VETDD/scripts/check-evidence.sh" <slice-ids>` on that tree. Quote its output. If it fails, you are not done: fix the cause, never the evidence.
2. Obtain the separate judge's verdict when the mode calls for one (test mode: on the integrated diff; verify mode: on the evidence; eval mode: always).
3. Write the reply in the format of `references/reply-format.md`. Every claim is labeled Measured, inferred, or guess.
4. If progress became impossible (judge unavailable, environment unreachable, oracle `inconclusive` past the retry cap), end in `blocked` or `inconclusive` with the evidence so far. Never report done without evidence.

## Non-negotiables (a checklist to reread before replying)

- No oracle, no product code.
- Each slice has a red (`before`, or `calibration` for a behavior-preserving change) that ended `target_failure`, and a final `integrated` run on the delivered tree that ended `pass`, all through `evidence.sh`.
- The author did not issue the final verdict; the judge is a different model family.
- Refactoring, if any, was done by a separate subagent after the slices were green, and every test was rerun after it.
- `check-evidence.sh` output is quoted in the reply.
- Any subagent brief starts with the fixed no-redelegation text.
