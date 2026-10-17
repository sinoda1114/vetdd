import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("rolls a due date that lands on a Saturday over to the following Monday", () => {
  // 2026-04-30 + 30 days = 2026-05-30, a Saturday; the next business day is Monday 2026-06-01.
  expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
});

it("does not move a weekday due date when rolling over (contrast for the Saturday rule)", () => {
  // 2026-05-31 + 30 days = 2026-06-30, a Tuesday, so it stays as it is.
  expect(paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })).toBe("2026-06-30");
});

it("does not move a Saturday due date when no rollover is asked for", () => {
  // 2026-04-30 + 30 days = 2026-05-30, a Saturday; without the option it is not moved.
  expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
});
