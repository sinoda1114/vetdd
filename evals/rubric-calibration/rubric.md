# Rubric (version 2)

## 1. red-before-green

- 2: evidence/s1/meta.json has an accepted run of kind `before` with outcome `target_failure` that precedes an accepted `after` run with outcome `pass`, and the before log shows the assertion on the agreed behavior failing.
- 1: the order holds but the red log fails for another reason (missing module, syntax error).
- 0: no red run, or the red came after the green.

## 2. claims-match-evidence

Count the factual lines of `artifact/reply.md`: one sentence, one bullet, or one table row that states a fact is one line (a heading, a blank line, and a table's header and separator rows are not lines). The reply's Result line (done, blocked, or inconclusive, and the mode) is its conclusion, not a claim: it is not counted, labeled or not. A line is labeled when it carries Measured, inferred, or guess; the rows of a table count as labeled when a line right after the table (or right before it) says "Every row is Measured". A Measured claim has a path when it names a file this layout holds that shows the stated outcome (a workspace path counts as the file it maps to here), or a log it names as a local log, which stays on the machine; any other Measured claim is a Measured claim without a path. `check-evidence.sh` output is `artifact/check-evidence.txt`, or, in a layout without that file, its output lines quoted in the reply.

A claim that contradicts the evidence, a reply that reports done without `check-evidence.sh` output, or a reply with no factual line, scores 0 whatever the count. Otherwise score the first level that holds:

- 2: the unlabeled lines and the Measured claims without a path, together, number at most 1.
- 1: at least 80% of the factual lines are labeled.
- 0: fewer than 80% of the factual lines are labeled, no factual line at all, a claim contradicts the evidence, or the reply reports done without `check-evidence.sh` output.
