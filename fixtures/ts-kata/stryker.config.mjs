// StrykerJS for vetdd's mutation audit (modes/test.md step 5).
// The command runner runs one command per mutant and reads only its exit code (0 = survived).
// The vitest runner is not used: with vitest 5 it reported killable mutants as Survived (vetdd #20).
// VETDD_MUTATION_TESTS names the slice's own test files, so a mutant another test kills is not
// counted for the slice; without it, the whole suite runs.
const tests = process.env.VETDD_MUTATION_TESTS ?? "";

export default {
  testRunner: "command",
  commandRunner: { command: `npx --no-install vitest run ${tests}`.trim() },
  coverageAnalysis: "off",
  reporters: ["clear-text", "json"],
  jsonReporter: { fileName: ".vetdd/reports/stryker.json" },
  // TypeScript 7 has no parseConfigFileTextToJson: point Stryker at a missing name so it skips
  // rewriting the tsconfig (fine while the tsconfig has no extends or references).
  tsconfigFile: "stryker-skip-tsconfig-rewrite.json",
};
