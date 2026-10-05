// StrykerJS for vetdd's mutation audit (modes/test.md "Audits" › "Mutation", run in Close step 2).
import { execFileSync } from "node:child_process";

// The command runner runs one command per mutant and reads only its exit code (0 = survived).
// The vitest runner is not used: with vitest 5 it reported killable mutants as Survived (vetdd #20).
// VETDD_MUTATION_TESTS names the slice's own test files, one per line, so a mutant another test
// kills is not counted for the slice. Unset or empty is an error: the whole suite would run silently.
// Each path is single-quoted for the shell the command runner uses (sh -c on POSIX; cmd.exe on Windows
// would keep the quotes, so this config is POSIX only), so ( ) $ [ ] and spaces stay part of the name.
const tests = (process.env.VETDD_MUTATION_TESTS ?? "").split("\n").filter((p) => p !== "");
if (tests.length === 0) {
  throw new Error("set VETDD_MUTATION_TESTS to the slice's test files, one per line (vetdd test mode, Audits › Mutation)");
}
if (process.platform === "win32") {
  throw new Error("this config single-quotes test paths for POSIX sh; cmd.exe would keep the quotes (vetdd #21)");
}
const option = tests.find((p) => p.startsWith("-"));
if (option !== undefined) {
  throw new Error(`a test path in VETDD_MUTATION_TESTS starts with - and would be read as an option: ${JSON.stringify(option)}`);
}
// vitest selects every test file whose path contains a filter (relative, ignoring letter case, by the
// project's own include): ask vitest itself which files each path selects, and refuse a path that does
// not select exactly one, so only the slice's own tests face the mutants.
for (const p of tests) {
  let listed;
  try {
    // The filter goes before the flags: --json takes an optional value and would read a path after it
    // as the file to write. With nothing after it, the list goes to standard output.
    listed = execFileSync("npx", ["--no-install", "vitest", "list", p, "--filesOnly", "--json"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    throw new Error(`VETDD_MUTATION_TESTS: could not list the test files ${JSON.stringify(p)} selects (vitest list failed): ${e.message}`);
  }
  let files;
  try {
    files = JSON.parse(listed).map((t) => t.file);
  } catch (e) {
    throw new Error(`VETDD_MUTATION_TESTS: could not read the list of test files ${JSON.stringify(p)} selects: ${e.message}`);
  }
  // One file once, wherever several projects list it; a sandbox an interrupted Stryker left is not the project.
  const selected = [...new Set(files)].filter((f) => !f.split(/[\\/]/).includes(".stryker-tmp"));
  if (selected.length !== 1) {
    throw new Error(`VETDD_MUTATION_TESTS: ${JSON.stringify(p)} selects ${selected.length} test files (${JSON.stringify(selected)}); name the slice's test file so it selects exactly one`);
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
