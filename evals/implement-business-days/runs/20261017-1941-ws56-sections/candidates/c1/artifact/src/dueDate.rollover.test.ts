import { describe, expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

const NEXT_BUSINESS_DAY = { rollover: "next-business-day" } as const;

describe("paymentDueDate with rollover: next-business-day", () => {
  it("moves a Saturday due date to the following Monday", () => {
    // 2026-04-30 + 30 days: May has 31 days, so +30 = 2026-05-30, a Saturday.
    // The following Monday is 2026-06-01.
    expect(paymentDueDate("2026-04-30", 30, NEXT_BUSINESS_DAY)).toBe("2026-06-01");
  });

  it("moves a Sunday due date to the following Monday", () => {
    // 2026-07-31 + 30 days: +1 = 2026-08-01, +29 more = 2026-08-30, a Sunday.
    // The following Monday is 2026-08-31.
    expect(paymentDueDate("2026-07-31", 30, NEXT_BUSINESS_DAY)).toBe("2026-08-31");
  });

  it("keeps a weekday due date as it is", () => {
    // 2026-05-31 + 30 days: June has 30 days, so 2026-06-30, a Tuesday.
    expect(paymentDueDate("2026-05-31", 30, NEXT_BUSINESS_DAY)).toBe("2026-06-30");
  });

  it("does not roll a Saturday due date over when the option is not given", () => {
    // Same dates as the Saturday case, without the third argument: 2026-05-30 stays.
    expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
  });
});
