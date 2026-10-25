import { describe, expect, it } from "vitest";
import { closingDate, paymentDueDate } from "./dueDate.js";

describe("closingDate", () => {
  it("closes on the 20th of the same month when invoiced before the cutoff", () => {
    // Invoiced on 3/10, the 20th of March has not passed yet: 2026-03-20.
    expect(closingDate("2026-03-10", 20)).toBe("2026-03-20");
  });

  it("closes on the 20th of the next month when invoiced after the cutoff", () => {
    // Invoiced on 3/25, March's 20th has passed, so the next one is April 20: 2026-04-20.
    expect(closingDate("2026-03-25", 20)).toBe("2026-04-20");
  });

  it("closes on the 31st for a month-end closing in a 31-day month", () => {
    // January has 31 days: 2026-01-31.
    expect(closingDate("2026-01-10", "end")).toBe("2026-01-31");
  });

  it("closes on the 30th for a month-end closing in a 30-day month", () => {
    // April has 30 days: 2026-04-30.
    expect(closingDate("2026-04-15", "end")).toBe("2026-04-30");
  });

  it("closes on the 28th for a month-end closing in February", () => {
    // February 2026 has 28 days; invoiced on the 15th, before the cutoff: 2026-02-28.
    expect(closingDate("2026-02-15", "end")).toBe("2026-02-28");
  });

  it("closes on the 29th for a month-end closing in a leap-year February", () => {
    // 2028 is a leap year, so February has 29 days; invoiced on the 15th: 2028-02-29.
    expect(closingDate("2028-02-15", "end")).toBe("2028-02-29");
  });
});

describe("paymentDueDate", () => {
  it("counts calendar days across a month boundary", () => {
    // 2026-01-31 + 30 days: February 2026 has 28 days, so +28 = 2026-02-28, +2 more = 2026-03-02.
    expect(paymentDueDate("2026-01-31", 30)).toBe("2026-03-02");
  });

  it("counts calendar days across a year boundary", () => {
    // 2026-12-20 + 30 days: +11 = 2026-12-31, +19 more = 2027-01-19.
    expect(paymentDueDate("2026-12-20", 30)).toBe("2027-01-19");
  });

  it("counts February 29 in a leap year", () => {
    // 2028 is a leap year. 2028-02-15 + 20 days: +14 = 2028-02-29, +6 more = 2028-03-06.
    expect(paymentDueDate("2028-02-15", 20)).toBe("2028-03-06");
  });
});
