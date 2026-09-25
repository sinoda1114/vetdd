export type ClosingDay = number | "end";

/** Numeric closing days stop at 28 so that every month has them; use "end" for month end. */
export const MAX_NUMERIC_CLOSING_DAY = 28;

type YearMonth = { readonly year: number; readonly month: number };
type CalendarDate = YearMonth & { readonly day: number };

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

function fromUtc(ms: number): CalendarDate {
  const d = new Date(ms);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

function toUtc({ year, month, day }: CalendarDate): number {
  return Date.UTC(year, month - 1, day);
}

function pad(n: number, width: number): string {
  return String(n).padStart(width, "0");
}

function formatDate({ year, month, day }: CalendarDate): string {
  return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

function parseDate(text: string): CalendarDate {
  const match = ISO_DATE.exec(text);
  if (!match) {
    throw new RangeError(`Expected a date as YYYY-MM-DD, got "${text}"`);
  }
  const date = { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
  if (formatDate(fromUtc(toUtc(date))) !== text) {
    throw new RangeError(`No such calendar date: "${text}"`);
  }
  return date;
}

function addDays(date: CalendarDate, days: number): CalendarDate {
  return fromUtc(toUtc(date) + days * MS_PER_DAY);
}

function nextMonth({ year, month }: YearMonth): YearMonth {
  return month === 12 ? { year: year + 1, month: 1 } : { year, month: month + 1 };
}

function lastDayOfMonth({ year, month }: YearMonth): number {
  // Date.UTC rolls an out-of-range day into the next month, so probe the 31st
  // and fall back to the 30th when this month does not have one.
  const probe = fromUtc(Date.UTC(year, month - 1, 31));
  if (probe.month === month) return 31;
  return fromUtc(Date.UTC(year, month - 1, 30)).day;
}

function closingDayIn(ym: YearMonth, closingDay: ClosingDay): number {
  return closingDay === "end" ? lastDayOfMonth(ym) : closingDay;
}

function assertClosingDay(closingDay: ClosingDay): void {
  if (closingDay === "end") return;
  if (!Number.isInteger(closingDay) || closingDay < 1 || closingDay > MAX_NUMERIC_CLOSING_DAY) {
    throw new RangeError(
      `Closing day must be an integer from 1 to ${MAX_NUMERIC_CLOSING_DAY} or "end", got ${closingDay}`,
    );
  }
}

/**
 * The closing date for an invoice: the closing day of the invoice's month when the
 * invoice is dated on or before it, otherwise the closing day of the following month.
 */
export function closingDate(invoiceDate: string, closingDay: ClosingDay): string {
  assertClosingDay(closingDay);
  const invoice = parseDate(invoiceDate);
  const sameMonthCutoff = closingDayIn(invoice, closingDay);
  const closingMonth = invoice.day <= sameMonthCutoff ? invoice : nextMonth(invoice);
  return formatDate({
    year: closingMonth.year,
    month: closingMonth.month,
    day: closingDayIn(closingMonth, closingDay),
  });
}

/** The payment due date: the closing date plus `termDays` calendar days. */
export function paymentDueDate(closing: string, termDays: number): string {
  if (!Number.isInteger(termDays) || termDays < 0) {
    throw new RangeError(`Term must be a non-negative integer number of days, got ${termDays}`);
  }
  return formatDate(addDays(parseDate(closing), termDays));
}
