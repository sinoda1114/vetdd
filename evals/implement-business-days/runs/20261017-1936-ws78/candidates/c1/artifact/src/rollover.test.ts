import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

const NEXT_BUSINESS_DAY = { rollover: "next-business-day" } as const;

describe("paymentDueDate with rollover: next-business-day", () => {
  it("moves a due date on a Saturday to the following Monday", () => {
    // 2026-04-30 + 30 days = 2026-05-30, a Saturday; the next Monday is 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, NEXT_BUSINESS_DAY)).toBe("2026-06-01");
  });

  it("moves a due date on a Sunday to the following Monday", () => {
    // 2026-07-31 + 30 days = 2026-08-30, a Sunday; the next Monday is 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, NEXT_BUSINESS_DAY)).toBe("2026-08-31");
  });

  it("keeps a due date on a weekday", () => {
    // 2026-05-31 + 30 days = 2026-06-30, a Tuesday.
    expect(paymentDueDate("2026-05-31", 30, NEXT_BUSINESS_DAY)).toBe("2026-06-30");
  });

  it("keeps a weekend due date when the option is not given", () => {
    // Without the third argument nothing moves: 2026-04-30 + 30 days = 2026-05-30, a Saturday.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
