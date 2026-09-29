# Cost report

All numbers below are either **measured** in this run (marked M) or **assumptions** (marked A) that you can change. No paid API is used by the running system: there is no API key, and the design does not need one.

## 1. Measured extraction cost per tier (M)

Tier = the most expensive tier that ran for the image (what it cost), whether or not it succeeded.

| Tier | What runs | Image cases | OCR time p50 | max | API cost |
|---|---|---|---|---|---|
| T1 | Tesseract, 3 renderings merged | 3 | 1.3 s | 1.9 s | $0 |
| T1b | Tesseract, then RapidOCR (rotation search only if the layout was not recognised upright) | 7 | 8.8 s | 14.6 s | $0 |

Decision + database time on top of OCR is a few milliseconds (see the per-case `ms` column in TEST_REPORT.md; text-only cases include setup).

## 2. What sending every slip to an AI model would cost (A)

Assumptions: image tokens ≈ width×height/750, capped at ~1,600 (our real slips: combank_ereceipt 904×1278 ≈ 1,540, combank_flash 674×1279 ≈ 1,149, peoples_deposit 720×1280 ≈ 1,228); plus ~500 prompt tokens in and ~300 JSON tokens out. List prices per 1M tokens.

| Model | $ in / out per 1M | ≈ $ per slip | ≈ $ per 1,000 slips | ≈ $ per 100,000 / month |
|---|---|---|---|---|
| Claude Haiku 4.5 | 1.00 / 5.00 | 0.0033 | 3.31 | 331 |
| Claude Sonnet 5 | 2.00 / 10.00 | 0.0066 | 6.61 | 661 |
| Claude Opus 5 | 5.00 / 25.00 | 0.0165 | 16.53 | 1,653 |

## 3. This system's cost per 1,000 submissions (A + M)

Assumed traffic mix (A): 10% exact re-sends (cache, 0 OCR), 65% clean screenshots (T1), 20% phone photos (T1b), 5% still unreadable after local OCR (go to staff; T2 disabled).

- OCR CPU time: 0.65 × 1.3 s + 0.25 × 8.8 s ≈ **51 CPU-minutes per 1,000**.
- On a 2-vCPU server at an assumed ~US$40/month (A), that is **≈ $0.02 per 1,000 submissions**; 100,000/month ≈ 85 CPU-hours, well under one small server's monthly capacity.
- API cost: **$0**.
- Human time: ~5% unreadable + the review share from TEST_REPORT.md. This is the real cost driver, not compute.

## 4. Where extra spend is justified

The T2 hook (`VisionExtractor`) is built but disabled. If an API key is added, sending **only** the ~5% of slips that local OCR could not read to Claude Haiku 4.5 would cost ≈ $0.17 per 1,000 submissions (50 slips × $0.0033), versus ≈ $3.31 for sending everything. That spend is justified because each of those slips otherwise costs staff minutes.

Paying for a stronger model (T3, e.g. Claude Sonnet 5) is justified only for **high-value slips that are flagged suspicious** (e.g. over Rs 50,000 with an edit signal), because a false approval there is a direct loss of the full amount. Even then the AI only extracts or gives a tamper *opinion*; it can never approve. Approval always needs the bank SMS match, so the AI budget buys staff time, not safety.

## 5. Why the cheap design is also the safe design

- Exact re-sends are caught by SHA-256 before any OCR (cost 0), and reused payments by transaction identity and the one-claim-per-SMS database rule. None of the fraud checks need AI.
- The expensive failure is a false approval, and approval depends on the bank SMS, not on reading quality. Better OCR (or AI) mostly reduces the manual-review rate; it does not change the false-approval rate, which is 0 in the evaluation.
