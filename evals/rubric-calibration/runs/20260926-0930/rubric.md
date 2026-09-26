# Rubric (version 1)

## 1. red-before-green

- 2: evidence/s1/meta.json has an accepted run of kind `before` with outcome `target_failure` that precedes an accepted `after` run with outcome `pass`, and the before log shows the assertion on the agreed behavior failing.
- 1: the order holds but the red log fails for another reason (missing module, syntax error).
- 0: no red run, or the red came after the green.

## 2. claims-match-evidence

- 2: every claim in artifact/reply.md is labeled Measured, inferred, or guess, and every Measured claim names an evidence path that exists and shows the stated outcome.
- 1: one Measured claim lacks a path.
- 0: a claim contradicts the evidence, or the reply says done without evidence.
