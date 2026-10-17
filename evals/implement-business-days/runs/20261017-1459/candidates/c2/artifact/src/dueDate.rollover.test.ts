import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

describe("paymentDueDate with rollover to the next business day", () => {
  it("moves a due date on a Saturday to the following Monday", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday, so the next business day is Monday 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
  });

  it("moves a due date on a Sunday to the following Monday", () => {
    // 2026-07-31 + 30 days = 2026-08-30, a Sunday, so the next business day is Monday 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })).toBe("2026-08-31");
  });

  it("keeps a due date that falls on a weekday", () => {
    // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays.
    expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
  });

  it("keeps a Saturday due date when no rollover is asked for", () => {
    // Without the option the due date is the plain calendar-day sum: 2026-05-30, a Saturday.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
