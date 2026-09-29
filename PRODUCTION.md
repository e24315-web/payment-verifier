# Production at 100,000+ submissions per month

100,000 submissions a month is about 3,300 a day, about 140 an hour on average, perhaps 1,000 an hour at evening
peaks across businesses. Compute is not the problem: measured OCR costs roughly 64 CPU-minutes per 1,000 slips, so
even the peak is a handful of CPU cores. The problems at scale are **latency spikes, many banks and formats, feed
reliability, fraud adaptation and human review load**.

## What changes

| Pressure | Change | Why |
|---|---|---|
| **Volume / latency** | Webhook only stores the message and enqueues a job (Redis Streams / SQS); stateless OCR workers pull jobs; results are pushed to WhatsApp when ready. | Today OCR runs inside the HTTP request (1–7 s). A queue absorbs peaks, makes retries safe and lets OCR scale separately. |
| | Postgres (already SQLAlchemy 2), `UNIQUE(claims.sms_id)` kept; composite indexes on (business, amount, txn_minute); images in object storage with lifecycle rules. | SQLite serialises writes. The race-safety design is the constraint, which Postgres keeps. |
| **Multiple businesses** | Tenant id on every table and query; per-business accounts, senders, windows, hotline, staff roles and real authentication (OIDC). | The prototype is one business per install with a shared staff key. |
| **Different banks / SMS formats** | Parser and template registry versioned per bank, each with a regression folder of anonymised real samples; CI fails if any sample stops parsing. Monitor the share of SMS hitting the *generic* parser and slips hitting the *generic* template, per bank per day. | Banks change formats without notice; the first sign is a jump in "unrecognised". |
| **SMS feed reliability** | Heartbeat from the forwarder app; per-business "feed stale" alert (not just a banner); balance-sequence gap alerts; optional second forwarder phone. | A dead phone makes every genuine payment look unpaid. It is the single biggest operational risk. |
| **Image quality** | Keep T1/T1b local; measure the unreadable rate per template. Enable the AI vision tier (hook exists) only for slips local OCR cannot read, with hash cache and a per-business daily spend cap. | Only the hard tail should cost money. |
| **AI/API cost** | Extraction-only prompts with structured output; the cheapest adequate model; batch non-urgent re-reads; never send an image twice (hash cache). | At 5% of 100k slips, Haiku-class extraction is roughly $15–20/month; sending everything would be ~$330/month. |
| **Fraud growth** | Cross-business reuse detection (the same transaction identity submitted to two businesses); customer and device risk scores; velocity limits (many slips from one number); feed the confirmed-fraud labels back into flags. Keep the rule: signals hold, the SMS match decides. | Fraudsters adapt to whatever is automated; the bank-evidence rule is the part they cannot edit. |
| **External failures** | OCR or AI down: fall back to human review. Database down: webhook returns 5xx, WhatsApp retries, message-id idempotency prevents doubles. SMS forwarder down: alert and pause auto-rejections that depend on missing SMS. Every external call has a timeout and a circuit breaker. | Degrade to "needs a person", never to a wrong approval. |
| **Human review load** | Per-business queues with SLAs and assignment; one-click approve for LOW_CONFIDENCE matches (SMS already held); reviewer metrics; corrected fields feed template fixes. | With good automation, reviewer time is the dominant cost; measure it and drive it down with better templates, not looser thresholds. |
| **Observability** | Metrics per decision reason, tier, bank and business; false-approval audit sampling (random approved slips re-checked against bank statements weekly); structured logs with submission ids. | The only way to prove "0 false approvals" in production is to sample and check. |
| **Security / privacy** | Secrets in a vault; signed short-lived image URLs; retention policy for slip images (they contain names and account numbers); audit log to append-only storage; rate limits on webhooks. | Slip images are personal financial data. |

## Rollout

Shadow mode first: the system decides, staff still approve everything, and every disagreement is logged. Turn on
auto-approval per business and per bank template once shadow agreement is high and false approvals are zero on a
meaningful sample.
