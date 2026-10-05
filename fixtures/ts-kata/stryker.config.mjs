// StrykerJS for vetdd's mutation audit (modes/test.md step 5).
import { globSync } from "node:fs";

// The command runner runs one command per mutant and reads only its exit code (0 = survived).
// The vitest runner is not used: with vitest 5 it reported killable mutants as Survived (vetdd #20).
// VETDD_MUTATION_TESTS names the slice's own test files, one per line, so a mutant another test
// kills is not counted for the slice. Unset or empty is an error: the whole suite would run silently.
// Each path is single-quoted for the shell the command runner uses (sh -c on POSIX; cmd.exe on Windows
// would keep the quotes, so this config is POSIX only), so ( ) $ [ ] and spaces stay part of the name.
const tests = (process.env.VETDD_MUTATION_TESTS ?? "").split("\n").filter((p) => p !== "");
if (tests.length === 0) {
  throw new Error("set VETDD_MUTATION_TESTS to the slice's test files, one per line (vetdd test mode, step 5)");
}
if (process.platform === "win32") {
  throw new Error("this config single-quotes test paths for POSIX sh; cmd.exe would keep the quotes (vetdd #21)");
}
const option = tests.find((p) => p.startsWith("-"));
if (option !== undefined) {
  throw new Error(`a test path in VETDD_MUTATION_TESTS starts with - and would be read as an option: ${JSON.stringify(option)}`);
}
// vitest selects every test file whose path contains a given filter: refuse a filter that would also
// select a test file other than the one named, so only the slice's own tests face the mutants.
const testFiles = globSync("**/*.{test,spec}.{ts,tsx,js,jsx,mts,cts,mjs,cjs}", {
  exclude: (p) => p.includes("node_modules") || p.includes(".stryker-tmp"),
});
for (const p of tests) {
  const selected = testFiles.filter((f) => f.includes(p.replace(/^\.\//, "")));
  if (selected.length === 0) {
    throw new Error(`VETDD_MUTATION_TESTS: ${JSON.stringify(p)} selects no test file`);
  }
  if (selected.length > 1) {
    throw new Error(`VETDD_MUTATION_TESTS: ${JSON.stringify(p)} also selects ${JSON.stringify(selected.slice(1))} besides ${JSON.stringify(selected[0])}; name the slice's test file so no other path contains it`);
  }
}
const quote = (p) => `'${p.replaceAll("'", `'\\''`)}'`;

export default {
  testRunner: "command",
  commandRunner: { command: `npx --no-install vitest run ${tests.map(quote).join(" ")}` },
  coverageAnalysis: "off",
  reporters: ["clear-text", "json"],
  jsonReporter: { fileName: ".vetdd/reports/stryker.json" },
  // TypeScript 7 has no parseConfigFileTextToJson: point Stryker at a missing name so it skips
  // rewriting the tsconfig (fine while the tsconfig has no extends or references).
  tsconfigFile: "stryker-skip-tsconfig-rewrite.json",
};
