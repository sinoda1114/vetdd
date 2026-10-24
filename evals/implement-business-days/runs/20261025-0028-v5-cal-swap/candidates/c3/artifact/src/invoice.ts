import { type ClosingDay, closingDate, paymentDueDate } from "./dueDate.js";

export type InvoiceTerms = {
  readonly invoiceDate: string;
  readonly closingDay: ClosingDay;
  readonly termDays: number;
};

export type InvoiceSchedule = {
  readonly closingDate: string;
  readonly dueDate: string;
};

export function computeInvoiceSchedule({
  invoiceDate,
  closingDay,
  termDays,
}: InvoiceTerms): InvoiceSchedule {
  const closing = closingDate(invoiceDate, closingDay);
  return { closingDate: closing, dueDate: paymentDueDate(closing, termDays) };
}
