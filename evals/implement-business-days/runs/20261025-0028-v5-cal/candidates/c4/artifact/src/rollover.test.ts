import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

const nextBusinessDay = { rollover: "next-business-day" } as const;

describe("paymentDueDate with next-business-day rollover", () => {
  it("moves a Saturday to the following Monday", () => {
    // 2026-04-30 + 30 days is 2026-05-30, a Saturday.
    expect(paymentDueDate("2026-04-30", 30, nextBusinessDay)).toBe("2026-06-01");
  });

  it("moves a Sunday to the following Monday", () => {
    // 2026-07-31 + 30 days is 2026-08-30, a Sunday.
    expect(paymentDueDate("2026-07-31", 30, nextBusinessDay)).toBe("2026-08-31");
  });

  it("keeps a weekday as it is", () => {
    // 2026-05-31 + 30 days is 2026-06-30, a Tuesday.
    expect(paymentDueDate("2026-05-31", 30, nextBusinessDay)).toBe("2026-06-30");
  });
});
