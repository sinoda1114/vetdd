#!/usr/bin/env bats
# Ladder rung 11 (types): a `// @ts-expect-error` line is an oracle whose verdict is tsc's exit code.
# Recorded through evidence.sh: clean types -> pass, a widened type -> target_failure,
# tsc missing -> infrastructure_error.

load test_helper
bats_require_minimum_version 1.5.0

APP="$VETDD_ROOT/fixtures/ts-kata"
LADDER="$VETDD_ROOT/skills/vetdd/references/feedback-loop-ladder.md"

needs_tsc() {
  command -v node >/dev/null || skip "node not installed"
  [ -x "$APP/node_modules/.bin/tsc" ] || skip "fixture dependencies not installed (npm ci in fixtures/ts-kata)"
}

# Copy the fixture into a fresh git repository (node_modules linked, ignored) with a type-level test:
# ClosingDay is `number | "end"`, so any other string must stay a type error.
make_kata_repo() {
  isolate_git
  REPO="$BATS_TEST_TMPDIR/kata"
  mkdir -p "$REPO"
  ( cd "$APP" && tar cf - --exclude ./node_modules --exclude ./.vetdd . ) | ( cd "$REPO" && tar xf - )
  ln -s "$APP/node_modules" "$REPO/node_modules"
  cd "$REPO"
  printf 'node_modules\n.vetdd/\n' > .gitignore
  cat > src/closingDay.typetest.ts <<'EOF'
import type { ClosingDay } from "./dueDate.js";

export const fifth: ClosingDay = 5;
export const monthEnd: ClosingDay = "end";
// @ts-expect-error a closing day is a number or "end", never another string
export const start: ClosingDay = "start";
EOF
  git init -q
  git add -A
  git commit -q -m init
}

@test "rung 11: tsc --noEmit with the correct types records pass" {
  needs_tsc
  make_kata_repo
  run ev types calibration -- node_modules/.bin/tsc --noEmit
  [ "$status" -eq 0 ]
  [ "$(mq types '.runs[0].exit_code')" = "0" ]
  [ "$(mq types '.runs[0].outcome')" = "pass" ]
}

@test "rung 11: a planted defect that widens ClosingDay leaves the @ts-expect-error unused: target_failure" {
  needs_tsc
  make_kata_repo
  sed -i.bak 's/^export type ClosingDay = number | "end";$/export type ClosingDay = number | string;/' src/dueDate.ts
  run cmp -s src/dueDate.ts src/dueDate.ts.bak
  [ "$status" -ne 0 ]
  run ev types calibration -- node_modules/.bin/tsc --noEmit
  [ "$status" -eq 0 ]
  [ "$(mq types '.runs[0].exit_code')" != "0" ]
  [ "$(mq types '.runs[0].outcome')" = "target_failure" ]
  grep -q "Unused '@ts-expect-error' directive" "$REPO/.vetdd/evidence/types/runs/001-calibration.log"
}

@test "rung 11: tsc missing (exit 127) records infrastructure_error, never red" {
  make_kata_repo
  run ev types calibration -- node_modules/.bin/tsc-not-installed --noEmit
  [ "$status" -eq 0 ]
  [ "$(mq types '.runs[0].exit_code')" = "127" ]
  [ "$(mq types '.runs[0].outcome')" = "infrastructure_error" ]
}

@test "ladder doc has rung 11 and says a formal result alone is never the final record" {
  grep -qE '^\| 11 \| types, proofs, model checking' "$LADDER"
  grep -q 'ts-expect-error' "$LADDER"
  grep -qi 'a formal result alone is never the final record' "$LADDER"
}

@test "rung 11: under noUnusedLocals an unexported local satisfies @ts-expect-error by itself; an exported one still goes red (A1)" {
  needs_tsc
  make_kata_repo
  sed -i.bak 's/"strict": true,/"strict": true, "noUnusedLocals": true,/' tsconfig.json
  sed -i.bak 's/^export type ClosingDay = number | "end";$/export type ClosingDay = number | string;/' src/dueDate.ts
  printf '// @ts-expect-error\nconst local: import("./dueDate.js").ClosingDay = "start";\n' > src/local.typetest.ts
  run node_modules/.bin/tsc --noEmit -p tsconfig.json
  # The exported directive is unused (red); the local one is satisfied by TS6133 (never red).
  [ "$status" -ne 0 ]
  [[ "$output" == *"closingDay.typetest.ts"*"Unused '@ts-expect-error' directive"* ]]
  [[ "$output" != *"local.typetest.ts"* ]]
}

@test "ladder doc: the type test exports its value, is calibrated, and only the property's exit code is red (A1, A2)" {
  grep -q 'export const d: ClosingDay = "start";' "$LADDER"
  grep -q "Unused '@ts-expect-error' directive" "$LADDER"
  grep -q 'noUnusedLocals' "$LADDER"
  run ! grep -qE '^\| violation, type error, failed proof \| != 0 \|' "$LADDER"
}


@test "rung 11 plain tsc: a project that cannot be checked (a syntax error elsewhere) is never a green (E1)" {
  needs_tsc
  make_kata_repo
  printf 'export const broken = ;\n' > src/broken.ts
  run ev types after -- node_modules/.bin/tsc --noEmit
  [ "$status" -eq 1 ]
  [ "$(mq types '.runs[0] | [.outcome, .accepted] | join(",")')" = "target_failure,false" ]
  [ -s "$REPO/.vetdd/evidence/types/runs/001-after.log" ]
  run ! grep -q 'TS2578' "$REPO/.vetdd/evidence/types/runs/001-after.log"
}

@test "ladder doc: plain tsc on a type-clean project, no wrapper, the red's reason read in its log (E1-E3)" {
  grep -q 'type-clean' "$LADDER"
  grep -q 'modes/test.md' "$LADDER"
  grep -q 'misspelled type name' "$LADDER"
  run ! grep -qF 'sh -c '"'"'out=$(' "$LADDER"
}

@test "ladder doc: the calibration uses calibrate.sh, tsconfig is an oracle file, a red for another reason needs a new version (G1, I1, I2)" {
  grep -q 'calibrate.sh plant' "$LADDER"
  grep -q -- '--oracle-file tsconfig.json' "$LADDER"
  grep -q 'stays in the record' "$LADDER"
  grep -q 'bump `--oracle-version` and record a red for the intended reason' "$LADDER"
  run ! grep -q 'record the same command again with `--outcome inconclusive`' "$LADDER"
}

@test "rung 11 calibration through calibrate.sh: plant, widen, planted is red with TS2578, and the type is restored (K1)" {
  needs_tsc
  make_kata_repo
  cp src/dueDate.ts "$BATS_TEST_TMPDIR/dueDate.orig"
  run "$SCRIPTS/calibrate.sh" plant types --file src/dueDate.ts --oracle-file src/closingDay.typetest.ts --oracle-file tsconfig.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  sed 's/^export type ClosingDay = number | "end";$/export type ClosingDay = number | string;/' "$BATS_TEST_TMPDIR/dueDate.orig" > src/dueDate.ts
  run cmp -s src/dueDate.ts "$BATS_TEST_TMPDIR/dueDate.orig"
  [ "$status" -ne 0 ]
  run "$SCRIPTS/calibrate.sh" planted types --oracle-file src/closingDay.typetest.ts --oracle-file tsconfig.json -- node_modules/.bin/tsc --noEmit
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(mq types '.runs[0] | [.kind, .outcome] | join(",")')" = "calibration,target_failure" ]
  grep -q "TS2578" "$REPO/.vetdd/evidence/types/runs/001-calibration.log"
  cmp -s src/dueDate.ts "$BATS_TEST_TMPDIR/dueDate.orig"
}

@test "ladder doc: calibrate.sh takes neither --infra-exit nor --outcome; the example uses the project's tsc (K1)" {
  grep -q 'calibrate.sh takes neither `--infra-exit` nor `--outcome`' "$LADDER"
  grep -q -- '-- ./node_modules/.bin/tsc --noEmit' "$LADDER"
  run ! grep -q -- '-- npx tsc' "$LADDER"
  grep -q 'every tsconfig it `extends`' "$LADDER"
}
