import { type ClosingDay } from "./dueDate.js";
import { computeInvoiceSchedule } from "./invoice.js";

const USAGE = "usage: tsx src/cli.ts due <YYYY-MM-DD> [--closing <1-28|end>] [--term <days>]";
const EXIT_USAGE = 2;
const DEFAULT_CLOSING: ClosingDay = "end";
const DEFAULT_TERM_DAYS = 30;
const INTEGER = /^\d+$/;

class UsageError extends Error {}

type DueArgs = { invoiceDate: string; closingDay: ClosingDay; termDays: number };

function parseClosing(value: string): ClosingDay {
  if (value === "end") return "end";
  if (!INTEGER.test(value)) throw new UsageError(`--closing must be a day number or "end", got "${value}"`);
  return Number(value);
}

function parseTerm(value: string): number {
  if (!INTEGER.test(value)) throw new UsageError(`--term must be a whole number of days, got "${value}"`);
  return Number(value);
}

function parseDueArgs(args: readonly string[]): DueArgs {
  const [command, invoiceDate, ...rest] = args;
  if (command !== "due" || invoiceDate === undefined || invoiceDate.startsWith("--")) {
    throw new UsageError("expected: due <invoiceDate>");
  }
  let closingDay = DEFAULT_CLOSING;
  let termDays = DEFAULT_TERM_DAYS;
  for (let i = 0; i < rest.length; i += 2) {
    const flag = rest[i];
    const value = rest[i + 1];
    if (value === undefined) throw new UsageError(`missing value for ${flag}`);
    if (flag === "--closing") closingDay = parseClosing(value);
    else if (flag === "--term") termDays = parseTerm(value);
    else throw new UsageError(`unknown option ${flag}`);
  }
  return { invoiceDate, closingDay, termDays };
}

function main(args: readonly string[]): number {
  try {
    const schedule = computeInvoiceSchedule(parseDueArgs(args));
    process.stdout.write(`closing: ${schedule.closingDate}\ndue: ${schedule.dueDate}\n`);
    return 0;
  } catch (error) {
    if (error instanceof UsageError || error instanceof RangeError) {
      process.stderr.write(`error: ${error.message}\n${USAGE}\n`);
      return EXIT_USAGE;
    }
    throw error;
  }
}

process.exitCode = main(process.argv.slice(2));
