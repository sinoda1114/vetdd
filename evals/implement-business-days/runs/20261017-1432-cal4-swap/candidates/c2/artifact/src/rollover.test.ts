import { expect, it } from "vitest";
import { paymentDueDate } from "./dueDate.js";

it("rolls over", () => {
  expect(paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })).toBe("2026-06-01");
});
