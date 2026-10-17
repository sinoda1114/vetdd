import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

describe("paymentDueDate with rollover: next-business-day", () => {
  it("moves a Saturday due date to the following Monday", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday; the next Monday is 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
  });

  it("moves a Sunday due date to the following Monday", () => {
    // 2026-07-31 + 30 days = 2026-08-30, a Sunday; the next Monday is 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })).toBe("2026-08-31");
  });

  it("keeps a weekday due date as it is", () => {
    // 2026-05-31 + 30 days = 2026-06-30, a Tuesday.
    expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
  });

  it("keeps a weekend due date when no rollover is given", () => {
    // Without the option the result is the plain calendar-day sum: 2026-05-30, a Saturday.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
