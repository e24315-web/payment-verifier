# Engineering report: Automated Bank Payment Verification

## 1. How the solution works

A customer pays by bank transfer or cash deposit and sends the slip to the business on WhatsApp. There is no bank API,
but the business phone receives a **bank SMS for every credit**. I treat that SMS as the source of truth and the slip
as the customer's *claim*. The system's job is to decide whether the claim points to exactly one real bank credit that
nobody else has used.

The pipeline:

1. **Intake.** WhatsApp message (simulator or Meta Cloud API webhook), idempotent on the message id. The customer is
   found by phone and the order by the code in the caption, or their only open order.
2. **Cheap image layer.** SHA-256 (an identical re-send costs no OCR), perceptual hash, quality metrics, EXIF check.
3. **Local OCR in tiers.** T1 Tesseract reads three renderings of the image and merges them field by field. If the
   critical fields are missing, T1b RapidOCR (a local, free ONNX model) runs, with a rotation search for sideways photos.
   Whatever is still unreadable goes to a person, who types the values; the system then re-checks them against the SMS.
   Per-bank templates turn text into fields, each with the OCR confidence of the exact characters it came from.
4. **Bank SMS ingestion.** A signed webhook from a forwarder app on the business phone (or manual paste / CSV). Per-bank
   parsers extract amount, account, time and (People's Bank) date and balance.
5. **Matching.** Amount + business account + transaction minute, with a one-minute allowance for SMS lag.
6. **Decision table.** Eleven ordered rows of plain code produce APPROVED / REJECTED / NEEDS VERIFICATION, a reason
   code, a confidence, the staff's next action and a customer-safe WhatsApp reply.
7. **Atomic claim.** Approving writes a row with `UNIQUE(sms_id)` in the same transaction, so one credit can never pay
   two orders, even under concurrent requests.
8. **Review UI.** A queue sorted by risk, and a detail page that separates *what the customer submitted* (image and
   fields) from *what the system concluded* (decision, reasons, flags, Slip / SMS / Order comparison), with staff
   actions that all require an audit note.

The business rules the owner specified are built in: a 10-minute window to pay, 10 more minutes to pay a balance,
cancellation otherwise, and refunds via a customer ID and hotline for underpaid, overpaid and late payments.

## 2. How a payment is verified as belonging to an order

Sri Lankan bank SMS usually contain **only amount, account and time** (ComBank: not even the date; that comes from when
the phone received the SMS). So the confirmation key is **amount + receiving account + time to the minute**, and a
payment is approved only if *all* of these hold:

- the slip's amount and time are read with high confidence (time ≥ 0.90, amount ≥ 0.85);
- the receiving account is one of the business's accounts (mask-aware: `065-2002****90` matches the full number);
- **exactly one unclaimed bank credit** matches: same amount and account, SMS minute equal to the slip minute or one
  later, and **no other same-amount credit within ±2 minutes** on that account;
- the transfer happened after the order was created and inside the payment window;
- the slip is not a duplicate, not already used, and raises no warning signal;
- overall confidence ≥ 0.85.

"Belongs to this order" rests on the time match plus one-to-one consumption, not on amount: two customers paying
Rs 5,000 at the same moment is sent to a person with both candidate SMS on screen. References, sender names and
narration are stored under the customer for history and fraud checks, but they are never used to confirm a payment,
because the SMS does not carry them.

## 3. How duplicate and reused payments are detected

Three independent layers:

1. **Same bytes**: SHA-256. Same order → the earlier decision is returned; another order → handled below.
2. **Same transaction, any image**: a canonical identity of *business account + amount + minute*, plus the bank
   reference folded for OCR confusion (O→0, I/L→1). This catches screenshots, photos of screens, crops that remove the
   reference, and recompressed copies. On the same order it is a duplicate; on another customer's order it is
   **REJECTED ALREADY_USED**, and the earlier approval is flagged **contested** for staff.
3. **Same bank credit**: the one-claim-per-SMS database constraint. Even if the slip is edited so that none of its
   details repeat, the SMS it points to is already claimed.

A detail that mattered: a rejected earlier submission must not "use up" a payment. Otherwise a fraudster who sends a
victim's slip first (and is rejected) would cause the real payer to be rejected too. The real payer goes to review
instead.

## 4. How suspicious or manipulated slips are handled

The strongest defence against editing is structural: **an edited slip no longer matches the bank SMS**. Change the
amount, minute, date or account and no credit agrees, so it cannot be approved. The mutation tests change each field of
an approved slip, one at a time, and assert it is never approved, including when resubmitted by another customer.

On top of that, templates cross-check fields: a receipt "generated" before its own transaction, "Payment Date"
disagreeing with the transaction date, a known reference reappearing with a different amount, a transfer status other
than Completed, a future timestamp, editing software in EXIF, a new sender account for a known customer, an
unexpected beneficiary name. These **only hold a payment for review, never approve or reject it**. Deliberately:
forensic signals are noisy (real receipts had odd kerning and mixed apostrophes), and a false signal should cost a
staff click, not a customer's money.

**Hard rejections need corroborated evidence.** OCR once read "2026" as "2028" at 0.93 confidence on a rotated cash
slip. A misread into the past would have rejected a genuine payer as an *old payment*, so OLD_PAYMENT now requires a
second date on the slip to agree. A single-date slip goes to review instead.

## 5. How bank SMS information is used

- **Source of truth** for amount, account and time. The SMS is stored raw, parsed by a per-bank parser (adding a
  bank = one class + a real sample), deduplicated by content hash + received time, and mapped to a business account by
  the SMS account mask and the sender number configured for that account.
- **Order of arrival doesn't matter.** A slip without an SMS waits; a late SMS automatically re-checks every waiting
  slip. After 2 hours still waiting, the slip escalates to staff.
- **"No SMS" vs "feed down".** If no SMS has arrived for 6 hours, the UI shows a stale-feed banner and waiting slips
  say so, because the phone forwarder may be down rather than the customer lying.
- **Security.** A forged credit SMS is the most dangerous input, so the webhook needs an HMAC signature with a 5-minute
  replay window (or a per-device token for simple forwarder apps), a registered device, and a sender on the account's
  allowlist. Manual entries are labelled and audited.
- **Balance (`Av_Bal`, People's Bank)** is used internally to spot gaps in the SMS sequence (previous balance + credit
  ≠ new balance). It is never shown to customers.

## 6. How cost is minimised

No paid API is used. Measured on the real slips, Tesseract takes about 1.2 s per screenshot and the RapidOCR fallback
about 5 s per photo, around **$0.03 of server time per 1,000 submissions**. Sending every slip to an AI model would
cost about $3.31 (Claude Haiku 4.5) to $16.53 (Claude Opus 5) per 1,000. Levers used:

- an identical re-send is caught by hash and costs nothing; results are cached per image;
- the expensive OCR tier runs only when the cheap one misses critical fields, and skips the rotation search when the
  cheap tier has already proven the orientation (this cut one case from 26 s to 4 s);
- **no fraud check needs AI.** Reuse, duplication and editing are caught by identity, the SMS match and the database.

A hook for an AI vision tier exists but is off (no API key). If enabled, it is worth it only for the ~5% of slips local
OCR cannot read (≈ $0.17 per 1,000 with Haiku, saving staff minutes), and a stronger model only for high-value slips
already flagged suspicious. AI would only extract fields; approval would still need the bank SMS, so extra spend buys
staff time, not safety.

## 7. Major limitations

- **Three real slip samples.** Templates are proven on one ComBank e-receipt, one Flash receipt and one People's
  Bank deposit slip. Test variants are derived from these, and new banks need new templates from real samples.
- **The folded cash-slip photo** matched its SMS but reached confidence 0.82, below the 0.85 auto-approve line, so
  photos of physical slips will often need one staff click.
- **Residual fraud risk:** someone who learns the exact amount, minute and account of another customer's credit and
  claims it first. The contested flag and sender history reduce this; without a bank API it cannot be closed.
- **The SMS feed is trusted.** A staff member could enter a fake SMS; this is audited, not prevented.
- **Prototype scope:** SQLite, OCR inside the request, a shared-key staff login, one business per install, the
  WhatsApp reply sender not connected, English-only replies, no moiré or pixel-level edit detection.
- **Evaluation:** 53 labelled cases give 0 false approvals, 0 false rejections and 0 wrong matches, but the case set is
  small and partly synthetic. The real-world review rate is unknown until the system runs on real traffic.

## 8. What I would change for production scale (100,000+ submissions a month)

That is about 140 an hour on average, more at peaks; see [PRODUCTION.md](PRODUCTION.md) for detail.

- **Queue and workers.** Accept the WhatsApp webhook in milliseconds, then run OCR in background workers
  (Redis/SQS + a worker pool); reply when done. Scale OCR workers horizontally; they are stateless.
- **Postgres** (the models already use SQLAlchemy) with the same unique constraint on claims; partition by business;
  indexes on (business, amount, minute). Images in object storage, not on local disk.
- **Multi-business** as a first-class tenant: per-business accounts, senders, windows, staff roles and real login.
- **Per-bank parser and template registry** with a regression suite of anonymised real SMS and slips per bank. Monitor
  the "unrecognised SMS / generic template" rate per bank, because a bank changing its format shows up there first.
- **SMS feed health per business** with alerting (phone offline, forwarder broken, balance-sequence gaps).
- **Human review as a product.** Queues per business, SLAs, reviewer statistics, and feeding corrected fields back
  into template fixes. As volume grows, reviewer time is the main cost, not compute.
- **Selective AI.** Enable the vision tier for unreadable slips once measured unreadable rates justify it. Cache by
  hash, cap spend per business per day, and always keep it extraction-only.
- **Failure handling.** When OCR or AI is unavailable, fall back to human review; if the database is unavailable,
  the webhook returns 5xx and WhatsApp retries (message-id idempotency makes retries safe). Treat an SMS forwarder
  outage as a paging alert.
- **Security.** Real staff authentication and roles, rate limits on webhooks, signed media URLs, PII retention
  rules for slip images, and the audit log shipped to append-only storage.
