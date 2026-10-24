# Reply format

The final reply of a vetdd task. Every claim carries its label in the same sentence: **Measured** (you ran it and read the result), **inferred** (derived from something measured), or **guess** (not observed). Write the reply in the user's language; keep this structure.

```
## Result
<one line: done | blocked | inconclusive, and the mode used, with its label, e.g. "done, test mode (inferred: the evidence below)">

## Oracle
Seam: <seam>, version <n> (Measured: .vetdd/evidence/<id>/meta.json).
Expected value <literal> (Measured: asserted in <oracle file>), from <source> (inferred: <why, when the judge cannot open the source>).
Covers: <what> (Measured: <oracle file>). Out of scope: <what> (inferred: the agreement). Blind spots: <what> (<label>).

## Evidence
| slice | kind | outcome | path |
|---|---|---|---|
| <id> | before | target_failure | .vetdd/evidence/<id>/runs/001-before.log |
| <id> | after | pass | .vetdd/evidence/<id>/runs/002-after.log (local log) |
Every row is Measured. check-evidence: <exact output line(s)> (Measured: artifact/check-evidence.txt; in the reply to the human add: local log <the saved output file>).

## Requirements → evidence
- <requirement 1>: <path of a red run's log, or of a record in meta.json> (Measured)
- <requirement 2>: <path of a green run's log> (Measured, local log)

## Change
<what changed and why, 3–6 sentences, each labeled: (Measured: <the changed file, e.g. src/dueDate.ts>) for what the change shows, (inferred: ...) for why>

## Judge
<in the draft the judge grades: "pending (inferred: the judge grades this draft)"; in the reply: the verdict as the judge gave it, or "not run: <reason>" with its label>

## Attention
<anything the human should look at, each item labeled: a guess, a skipped step with its reason, a blind spot that matters>
```

## Labels

The final judge counts every unlabeled statement of fact against the reply (`references/final-judge-rubric.md`, claims-match-evidence), so label as you write, not afterwards:

- **The Result line carries a label too**, though it is the conclusion and the judge's rubrics leave it out of their count: the label tells the human what the conclusion rests on, so write it as "done, test mode (inferred: the evidence below)" and put nothing else in it. The Judge section quotes the judge; when the judge did not run, that is a claim like any other ("not run: the request keeps everything on this machine (inferred: the agreement)"). Every other sentence, bullet, and table row that states a fact carries a label, in the sections the template shows without one too (Oracle, Change, Attention). A table may label all its rows at once in a line under it ("Every row is Measured"), when each row names its path.
- **Measured names a path the judge receives, or a local log it does not**: a file of the diff or an oracle file (`artifact/`), a record or a red run's log of the evidence (`evidence/`), or a log that stays on the machine, marked `(Measured, local log)`, or in a table `(local log)` after the path under a line saying every row is Measured (the final judge's layout sends only the red runs' logs; its rubric accepts a log named as local). Never a command: in the draft the judge grades, cite `check-evidence.sh` as `artifact/check-evidence.txt` from the start (the one path written as the layout names it: the draft is written before the layout, and `judge-layout.sh` always writes the output under that name); save the output under `.vetdd/` as well, and in the reply to the human add that file as `(Measured, local log: <that file>)`, which is the only citation when no layout is built. Write paths as they are in your workspace (`src/dueDate.test.ts`, `.vetdd/evidence/<slice>/runs/001-before.log`); the judge layout maps them, and it renames `.claude` itself, so never write `.agent` in the reply.
- **A source the judge does not receive is inferred**, even when you read it yourself: the README, the agreement note under `.vetdd/notes/`, a calendar or a `date` command you ran by hand, a local arena note. Cite the oracle file that asserts the value as Measured, and the source of the value as inferred.
- **The draft the judge gets is this reply only**: from `## Result` to `## Attention`, the file you pass as `--reply`. Whatever your environment asks for on top, such as a summary before the reply or a closing block of changes and to-dos for the human, goes in your message to the human, outside that file: the judge would count each of its sentences as an unlabeled claim.
- **Before sending**, read the reply once for a sentence with no label, and for a Measured label whose path the judge cannot open; fix each one.

A `blocked` or `inconclusive` result keeps the same sections and states, under Attention, what was tried and what would unblock it.

Never write "should work", "verified" without a path, or "all tests pass" without the command's output line.
