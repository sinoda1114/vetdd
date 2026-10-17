import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

describe("paymentDueDate with rollover to the next business day", () => {
  it("moves a due date that lands on a Saturday to the following Monday", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday, so the due date moves to Monday 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
  });

  it("moves a due date that lands on a Sunday to the following Monday", () => {
    // 2026-07-31 + 30 days = 2026-08-30, a Sunday, so the due date moves to Monday 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })).toBe("2026-08-31");
  });

  it("keeps a due date that lands on a weekday", () => {
    // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays as it is.
    expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
  });

  it("does not move a weekend due date when no rollover is asked for", () => {
    // Without the third argument nothing changes: 2026-04-30 + 30 days stays Saturday 2026-05-30.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
