import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

describe("paymentDueDate with rollover: next-business-day", () => {
  it("moves a due date that lands on a Saturday to the following Monday", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday; the following Monday is 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
  });

  it("moves a due date that lands on a Sunday to the following Monday", () => {
    // 2026-07-31 + 30 days = 2026-08-30, a Sunday; the following Monday is 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })).toBe("2026-08-31");
  });

  it("keeps a due date that lands on a weekday", () => {
    // 2026-05-31 + 30 days = 2026-06-30, a Tuesday: unchanged.
    expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
  });
});

describe("paymentDueDate without the rollover option", () => {
  it("keeps a due date that lands on a weekend", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday: without the option it stays as it is today.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
