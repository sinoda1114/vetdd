# Test quality

Applies whenever a test is written, changed, or kept. It grounds principle 4 in concrete checks. Sources: pstack `test-behavior-not-implementation`, mattpocock `tdd/tests.md` and `mocking.md`.

## The one question

Would this test still pass if every function it imports returned `undefined`? If yes, it observes no behavior. Rewrite the assertion or delete the test (name the replacement coverage first). `calibrate.sh stub` asks the runner this question (modes/test.md, step 5), and check-evidence rule 10 fails a slice whose answer was yes.

## Where expected values come from

An expected value is written down before the implementation runs, from a source the implementation cannot influence:

- a worked example computed by hand from the domain (the calendar, the price table, the spec's own example)
- a known-good output captured from a trusted version
- a property the spec guarantees (round-trip, element preservation, an invariant across inputs)

Never from the code under test, and never from the same formula the code uses (`expect(add(a, b)).toBe(a + b)` proves nothing).

## Five hollow shapes

Each is a signal, not a verdict. The test stays only if the shape IS the agreed behavior (an existence check on a public API that the contract requires, for example).

| shape | example | usual fix |
|---|---|---|
| weak or no assertion | only `toBeDefined`, `toBeTruthy`, `not.toThrow`, `toBeGreaterThan(0)` | assert the literal value |
| mock or absence only | only `toHaveBeenCalled`, `toEqual([])`, `toHaveLength(0)` | assert the payload the mock received, or the state after the call; pair every "absent" assertion with a "present" one on another input |
| self-referential | `expect(parse(x).url).toBe(buildUrl(x))` | expected value from an independent source |
| constant pin | `expect(LIMITS.max).toBe(8)`, `expect(PROMPT).toContain("You are")` | test the code that reads the constant, with one input |
| fixture asserts fixture | the test reads back what `beforeEach` built and never calls the subject | call the subject in the test body |

## Seams and mocks

- Tests sit on the seam agreed in principle 1a: the public boundary through which the behavior is observed. If a test wants to reach past the interface (query the DB after calling `createUser` instead of calling `getUser`), the module shape is wrong; say so instead of writing the test.
- Mock only at system boundaries: external APIs, the clock, randomness, sometimes the file system. Never mock your own modules or internal collaborators.
- Inject boundary dependencies as narrow SDK-shaped functions (`getUser`, `createOrder`), not a generic `fetch(url, opts)`, so mocks need no branching.

## Three anti-patterns of the loop

- Implementation-coupled: breaks on a refactor that preserves behavior.
- Tautological: recomputes the expected value with the implementation's own logic.
- Horizontal slicing: all tests first, then all code. Write one test, make it pass, repeat (vertical slice); each test responds to what the previous cycle taught. The one exception: when a single fix will cover several slices, their tests are written and their `before` runs recorded before the fix, because after it they can never go red (modes/test.md step 3).

## Prefer no test over a bad test

A test that cannot go red for the intended reason is deleted, and the gap is recorded in the reply under "blind spots" with the replacement oracle (a verify script, a type check) named.
