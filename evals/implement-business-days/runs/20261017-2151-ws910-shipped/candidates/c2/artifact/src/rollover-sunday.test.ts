import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("rolls a due date that lands on a Sunday over to the following Monday", () => {
  // 2026-07-31 + 30 days = 2026-08-30, a Sunday; the next business day is Monday 2026-08-31.
  expect(paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })).toBe("2026-08-31");
});

it("does not move a weekday due date when rolling over (contrast for the Sunday rule)", () => {
  // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays as it is.
  expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
});
