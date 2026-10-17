import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("keeps a due date that lands on a weekday when rolling over to the next business day", () => {
  // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays.
  expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
});
