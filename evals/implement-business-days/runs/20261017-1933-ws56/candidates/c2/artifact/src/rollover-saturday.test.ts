import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("moves a due date that lands on a Saturday to the following Monday", () => {
  // 2026-04-30 + 30 days = 2026-05-30, a Saturday; the next Monday is 2026-06-01.
  expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
});

it("does not treat a weekday as a Saturday", () => {
  // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays.
  expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
});
