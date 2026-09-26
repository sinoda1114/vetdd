import { describe, expect, it } from "vitest";
import { computeInvoiceSchedule } from "./invoice.js";

describe("computeInvoiceSchedule", () => {
  it("closes at month end and pays 30 days later", () => {
    // May has 31 days, so closing is 2026-05-31.
    // 2026-05-31 + 30 days: June has 30 days, so the due date is 2026-06-30.
    expect(
      computeInvoiceSchedule({ invoiceDate: "2026-05-12", closingDay: "end", termDays: 30 }),
    ).toEqual({ closingDate: "2026-05-31", dueDate: "2026-06-30" });
  });

  it("rolls the closing into the next month and the due date into the next year", () => {
    // Invoiced on 10/25, after October's 20th, so closing is 2026-11-20.
    // 2026-11-20 + 45 days: +10 = 2026-11-30, +31 = 2026-12-31, +4 = 2027-01-04.
    expect(
      computeInvoiceSchedule({ invoiceDate: "2026-10-25", closingDay: 20, termDays: 45 }),
    ).toEqual({ closingDate: "2026-11-20", dueDate: "2027-01-04" });
  });
});
