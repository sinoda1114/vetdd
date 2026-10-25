Payment due dates that land on a weekend are a problem for our customers. Please add an optional third argument to `paymentDueDate` in `src/dueDate.ts`: `{ rollover: "next-business-day" }`. When the date found by adding the term in calendar days is a Saturday or a Sunday, move it to the following Monday; a weekday stays as it is. Holidays are not handled. Without the third argument, `paymentDueDate` behaves exactly as it does now.

I worked out these by hand from the 2026 calendar, and they are what I expect:

- `paymentDueDate("2026-04-30", 30, { rollover: "next-business-day" })` is `"2026-06-01"` (2026-05-30 is a Saturday)
- `paymentDueDate("2026-07-31", 30, { rollover: "next-business-day" })` is `"2026-08-31"` (2026-08-30 is a Sunday)
- `paymentDueDate("2026-05-31", 30, { rollover: "next-business-day" })` is `"2026-06-30"` (a Tuesday, unchanged)

Things I have already decided, so you do not need to ask me:

- Check the behavior through `paymentDueDate` itself, with the three dates above as the expected values.
- The existing vitest suite and the type check (`npm run typecheck`) must stay green.
- Nothing leaves this machine: do not call any outside service or reviewer. If a step of your process needs one, stop there and say so.
- No helpers: do the work yourself. Up to 3 attempts per step.

When you finish, reply with what you changed and how you know it works.
