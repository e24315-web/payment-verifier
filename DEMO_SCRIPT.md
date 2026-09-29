# Demo script (about 10 minutes)

Covers the brief's required cases: **valid payment, wrong amount, duplicate/reused payment, suspicious payment, unclear
slip, insufficient evidence**, plus old payment, overpayment/refund and the late-SMS auto-approval.

Everything runs through the real API with real OCR. Slips 1, 2 and 7 are the owner's **real** slips. The others are
**synthetic test slips** from `tools/make_demo_slips.py`, each watermarked "TEST SLIP - NOT A REAL RECEIPT".

## Setup (1 minute, before the audience)

```bash
cd backend
python run.py --reset --demo-start 2026-09-26T16:17:00        # terminal 1
python ../tools/demo_seed.py                                   # terminal 2, ~1 minute
```

The demo clock starts at **4:17 PM on 26/09/2026**, when the real ComBank transfer (4:18 PM) happened, and then runs
in real time. The seed configures Settings (SMS senders COMBANK / PEOPLESBANK, hotline, 10-minute windows) and plays
eight customers:

| # | Customer | What happens | Expected |
|---|---|---|---|
| 1 | Mohamed Rizan | real e-receipt, SMS arrives after the slip | Waiting → **Approved** automatically |
| 2 | Kasun Perera | forwards Rizan's receipt for his own order | **Rejected**: already used; Rizan's approval marked **contested** |
| 3 | Nimal Perera | pays 3,000 of an 8,000 order | **Approved (underpaid)**: balance 5,000 due in 10 min |
| 4 | Saman Silva | slip says 20,000; the bank credited 2,000 | **Needs verification**: SMS conflict (edited slip) |
| 5 | Dilani Fernando | blurred photo | **Needs verification**: unreadable |
| 6 | Priya Raj | good slip, no bank SMS yet | **Needs verification**: waiting for SMS |
| 7 | Athayea Rasool | real month-old People's Bank cash slip | **Rejected**: old payment |
| 8 | Ruwan Dias | pays 1,800 for a 1,500 order | **Approved (overpaid)**: Rs 300 refund due, customer ID + hotline |

Open http://127.0.0.1:8000. The header shows the demo time and a green "SMS feed" dot.

## Walkthrough

**1. The question the screen answers (30 s).** *Payments to review* shows the needs-action items first, highest risk
on top. Kasun's rejection pushed **Rizan's approval to the top as CONTESTED**: someone else tried to use his payment.

**2. Valid payment: Rizan (1 min).** Open it. Point at the split:
- *What the customer submitted*: the real receipt (zoom, rotate), each field with a confidence bar.
- *What the system concluded*: Approved; the Slip / Bank SMS / Order table with ✓ for account, amount, time.
- The bank SMS text; "Decided by system". The history shows **Waiting for SMS**, then **Approved** once the SMS
  arrived. Nobody pressed a button.
- The WhatsApp reply the customer got.

**3. Reused payment: Kasun (1 min).** Same receipt, different customer: **Rejected, already used**. The SMS box says
"already used by #1". *Related payments* lists Rizan's submission (same image, same reference, same amount & minute).
The customer message is generic ("appears to have already been used for another order"); no fraud details are
shown to the customer.

**4. Duplicate (30 s).** *WhatsApp simulator* → chat *Mohamed Rizan* → **Send: ComBank e-receipt** again. The bot
replies "We have already received this payment slip…". No OCR runs: the image hash is known.

**5. Wrong amount: Nimal (1.5 min).** Open Nimal: **Approved (underpaid)**. The order shows paid 3,000 / balance due
5,000 with a live countdown. The customer was told the balance, the 10-minute deadline, and that the order is cancelled
(with refund via customer ID) if the balance isn't paid.
- *Pay the balance:* Simulator → chat *Nimal Perera* → **Send: TEST slip Rs 5,000 at 4:24 PM (balance)**, then in
  *Bank: simulate an SMS* type `Credit for Rs. 5,000.00 to 8026328795 at 16:24 at DIGITAL BANKING DIVISION`,
  sender `COMBANK`, received `2026-09-26 16:24`, **Deliver SMS**. The order becomes **Paid**.
  (Do this once the header clock is past 4:19 PM; a 4:24 transfer is otherwise more than 5 minutes in the future and
  is correctly held as *future-dated*. If that happens, press **Re-check now** on the slip after 4:19.)
- *Or let it lapse:* after the balance deadline the order is **Cancelled** and Nimal receives a refund message with
  his customer ID and the hotline.

**6. Suspicious: Saman (1 min).** **Needs verification, SMS conflict**. The comparison shows slip Rs 20,000 vs bank
Rs 2,000 at the same minute: an edited amount. Point out that it was *not* auto-rejected: forensic signals hold a
payment for a person, they never decide alone. **Reject** with a note ("amount edited, bank shows 2,000"); the note
goes into the audit trail.

**7. Unclear slip: Dilani (1 min).** **Needs verification, unreadable**; the fields show low confidence bars. Two
options:
- **Ask for a new slip** sends the customer a WhatsApp message;
- **Correct slip details:** type amount 5,000, time 26/09/2026 16:20:00 and paid-to account 8026328795. The *system*
  re-checks against the bank: there is no Rs 5,000 credit at 4:20 (only Saman's Rs 2,000), so it stays unverified
  with an *SMS conflict*.
  **Staff typing values never bypasses the SMS check.**

**8. Insufficient evidence → auto-approval: Priya (1 min).** **Waiting for SMS**. Simulator → *Bank: simulate an
SMS* → `Credit for Rs. 4,000.00 to 8026328795 at 16:21 at DIGITAL BANKING DIVISION`, sender `COMBANK`, received
`2026-09-26 16:21` → **Deliver SMS**. The result line says it re-checked Priya's slip; the queue now shows her
**Approved**, and her chat has the confirmation.

**9. Old payment: Athayea (30 s).** The real cash-deposit photo (sideways, folded) was read by the second OCR tier:
Rs 7,500 at 28/08/2026 1:43:42 PM, one minute before its SMS (normal lag). The order is from 26/09, so it is
**Rejected, old payment**. The rejection was allowed because the slip's second date (EFF.DATE) agreed.

**10. Overpaid and refunds: Ruwan (30 s).** **Approved (overpaid)**, refund due Rs 300. *Customers & refunds* →
search his customer ID (as the hotline would) → **Record refund** with a note.

**11. Where the evidence comes from (30 s).** *Bank SMS* page: every SMS with source (webhook / manual / simulator),
which order used it, and the business balance (staff only). *Settings*: the SMS sender numbers per bank account, and
the People's Bank account still flagged "mask only".

## Talking points

- **0 false approvals in 53 labelled cases** (`docs/TEST_REPORT.md`), 229 automated tests.
- **No paid API**: local OCR costs about $0.03 of server time per 1,000 slips (`docs/COST_REPORT.md`).
- Found while preparing this demo: two Rs 2,000 credits one minute apart (Saman's real credit and a first draft of
  Ruwan's) were correctly treated as *ambiguous* and sent to a person. This is the "multiple customers with similar
  payments" rule working: amount alone never proves ownership.
