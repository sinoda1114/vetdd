# Seam proposal format

Used in principle 1a when asking the human to agree on where the oracle sits. The human should be able to choose without opening the code, so every candidate states what it catches, what it misses, and what it costs.

Present 1–3 candidates, recommended first, through `AskUserQuestion`. Fewer seams are better; the ideal is one. Prefer an existing seam over a new one, and the highest seam that still reaches the defect.

For each candidate:

```
<seam name>  (<kind>: unit | integration | cli | http | ui)
  where:    <file or entry point the test calls>
  catches:  <the agreed behavior, stated as the exact assertion>
  misses:   <what a green here does NOT prove>
  cost:     <runtime of one run; setup needed>
  existing: <yes: <test file> | no: new file <path>>
```

Example (fixture ts-kata, bug: February closing date):

```
closingDate() unit  (unit)
  where:    fixtures/ts-kata/src/dueDate.test.ts calls closingDate("2026-02-15", "end")
  catches:  returns "2026-02-28"; today returns "2026-03-31"
  misses:   the CLI wiring (argument parsing, output format)
  cost:     ~100 ms, no setup
  existing: yes, dueDate.test.ts

cli due  (cli)
  where:    ./node_modules/.bin/tsx src/cli.ts due 2026-02-15
  catches:  prints "closing: 2026-02-28"
  misses:   nothing in this path, but slower and couples the test to output format
  cost:     ~1 s (tsx startup)
  existing: no, new file src/cli.test.ts
```

The agreement records the chosen seam in `evidence.sh --seam` and the expected value's source in the reply.
