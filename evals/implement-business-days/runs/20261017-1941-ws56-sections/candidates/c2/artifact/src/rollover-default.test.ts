import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("keeps a weekend due date when no rollover is asked for", () => {
  // 2026-04-30 + 30 days = 2026-05-30, a Saturday; without the option it is not moved.
  expect(paymentDueDate("2026-04-30", 30)).toBe("2026-05-30");
});

it("moves the same weekend due date when the rollover is asked for", () => {
  // Same dates with the option: 2026-05-30 is a Saturday, so it moves to Monday 2026-06-01.
  expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
});
