import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("keeps a due date that lands on a weekday when rolling over to the next business day", () => {
  // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays as it is.
  expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
});

it("keeps a due date on a weekend when no rollover is asked for", () => {
  // 2026-04-30 + 30 days = 2026-05-30, a Saturday; without the option it is not moved.
  expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
});
