# synthesis: implement-business-days / rubric calibration (runs 1243-cal to 1432-cal4-swap)

Purpose: step 2 of eval mode before any candidate run. A hand-made known-good (test mode, red then green, labeled reply), a known-bad (one value asserted, no red, holidays, a second mode, an unrequested check, an unlabeled "Done ... All tests pass"), and an empty one (the request echoed back), collected with sanitize-candidates.sh exactly as candidates are.

| run | rubric | known-good | known-bad | empty | note |
|---|---|---|---|---|---|
| 1243-cal | v1 | fail (2,2,2,0) | fail (1,0,0,0) | fail (0,0,0,0) | the known-good's Measured claims cited the diff and test file, not evidence/; its result line was counted as an unlabeled claim |
| 1246-cal2 | v2 (result line exempt; artifact/ or evidence/ paths) | fail (1,2,2,0) | fail | fail | workspace paths (src/, .vetdd/evidence/) were not read as artifact/ and evidence/; "the latest green run" was a type check |
| 1430-cal3 | v3 (path mapping; a green run after the file's last change) | partial (2,2,2,1) | fail | fail | one unlabeled clause in the known-good's Oracle line |
| 1430-cal3-swap | v3, labels swapped | pass (2,2,2,2) | fail | fail | same winner; the known-good's verdict moved on that one clause |
| 1432-cal4 | v3, the clause labeled | pass (2,2,2,2) | fail (1,0,0,0) | fail (0,0,0,0) | confidence high |
| 1432-cal4-swap | v3, labels swapped | pass (2,2,2,2) | fail (1,0,0,0) | fail (0,0,0,0) | confidence mid; every artifact kept its verdict |

Audits: empty candidate 0 on every criterion in every run (Measured); label swap stable once the known-good's ambiguous clause was labeled (Measured, 1432-cal4 and -swap); rubric pin: v3 sha256 `31e3300cac371d8b031ecbe766bd71f8670f4f1fb84209214a9cc9adac082770`.

Rubric revisions v2 and v3 were made before any candidate ran, each agreed by the human (2026-10-17), so principle 6 (never revise after a result) is not touched: both fixed a mismatch between the rubric and vetdd's own reply format (reply-format.md opens with an unlabeled result line, and replies cite workspace paths). The known-good's reply was edited once (labeling its seam and version) between 1430 and 1432: that changes the calibration artifact, not the oracle.

Collection friction: package-lock.json holds "baseline" (baseline-browser-mapping), an origin word; sanitize-candidates.sh has no --allow-words, so every run used --strip baseline (#54). Model names and evaluation words in the placed skill, and "claude" in CLAUDE.md and the brief, were allowed in the candidate check by the human (Frame, 2026-10-17); the judge's copy holds no placed file.

## Pruned before commit

The sanitized copies kept in the repository leave out each candidate's artifact/package-lock.json (the fixture's own, which no candidate changed, with "baseline" redacted as the judge saw it), and the candidates of the superseded calibration runs 1243-cal, 1246-cal2, 1430-cal3, and 1430-cal3-swap (the same three artifacts as 1432-cal4, but for one line of the known-good reply); their judge.json, rubric.md, and variants.json stay.
