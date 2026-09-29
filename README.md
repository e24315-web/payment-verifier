To use this at a real business, you need 4 things: a computer that is always on, a WhatsApp connection, a bank SMS connection, and one missing piece that still has to be built.

Important: one part is not built yet

The app reads WhatsApp messages, but it can't send replies yet. Replies are saved in the database and never sent (the README says the same). Before a real business can use it, I need to add the part that sends replies through WhatsApp. I can do that next.

Step 1: A computer that is always on

WhatsApp (Meta's servers) and the SMS phone have to be able to reach the app over the internet at any time.

┌──────────────────────────────────────────────────────┬─────────────────────────┬───────────────────────────────┐
│                        Option                        │          Good           │              Bad              │
├──────────────────────────────────────────────────────┼─────────────────────────┼───────────────────────────────┤
│ Cloud server (for example DigitalOcean or AWS, about │ Always on, gets its own │ Small monthly cost            │
│  $6–12 a month) (recommended)                        │  web address            │                               │
├──────────────────────────────────────────────────────┼─────────────────────────┼───────────────────────────────┤
│ The business's own PC + Cloudflare Tunnel (free)     │ Free                    │ The PC must never be turned   │
│                                                      │                         │ off or go to sleep            │
└──────────────────────────────────────────────────────┴─────────────────────────┴───────────────────────────────┘

Install on that computer:
1. Python 3.11+ and Tesseract 5 (the program that reads slip images)
2. Copy the payment-verifier folder to it (you don't need venv, legacy or frontend/node_modules)
3. Run:
python -m venv venv
venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
..\venv\Scripts\python.exe run.py --host 0.0.0.0
4. Set a staff password (PV_STAFF_API_KEY). Without it, anyone who finds the web address can approve payments.

Step 2: Connect WhatsApp (WhatsApp Cloud API)

1. Create a Meta Business account at business.facebook.com.
2. At developers.facebook.com, create an app and add WhatsApp to it.
3. Add the business phone number. Note: a number used with the Cloud API can't be used in the normal WhatsApp app at the same time, so many businesses use a new number.
4. In the app's WhatsApp settings, set the webhook:
   - Callback URL: https://YOUR-ADDRESS/webhooks/whatsapp
   - Verify token: any secret word you choose
   - Subscribe to messages
5. Put the 3 values on the server as settings:
   - PV_WA_VERIFY_TOKEN: the secret word from step 4
   - PV_WA_APP_SECRET: from the Meta app settings
   - PV_WA_ACCESS_TOKEN: from the WhatsApp settings (use a permanent "system user" token)

Step 3: Connect the bank SMS

The bank sends SMS to the business owner's Android phone. That phone has to pass each SMS on to the app.

1. On that phone, install an SMS forwarder app (search "SMS forwarder webhook" on the Play Store).
2. Set it to send each SMS to https://YOUR-ADDRESS/webhooks/sms
   - Message format: {"sender": "...", "body": "...", "received_at": "..."}
   - Headers: X-Device-Id: phone-1 and X-Device-Token: <a long secret>
3. On the server, set PV_SMS_DEVICE_TOKENS=phone-1:<the same secret>.
4. In the app's Settings page, enter the bank's SMS sender names (for example COMBANK) for each account.
5. Keep the phone always on, charged and online. If it stops, payments wait for staff to check them by hand, and the app shows a "SMS feed stale" warning.

Step 4: "Build an app"

The app is already built: the staff screen opens in any web browser, including on phones. You don't need a separate app. What you still need is:
- the WhatsApp reply sender (the missing piece above)
- optionally, a one-click installer so a new PC doesn't need any typing. I can make a start.bat file that sets everything up and starts the app, and set it to start automatically when the PC turns on.
