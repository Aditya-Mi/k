#!/usr/bin/env python3
"""Fill a running emulator's k with realistic test data, as bank SMS.

    python3 tool/emulator_seed.py            # send everything
    python3 tool/emulator_seed.py --dry-run  # print the messages only

Bodies follow the real formats in packages/txn_parser/test/fixtures, with
made-up accounts (Axis XX1111 + card XX5678, Kotak X2222, BOB XXXXXX3333)
and dates relative to today, so they land in this month and the last few.
k must be installed, onboarded and allowed to read SMS. Messages are
one line each: the emulator console cuts at a newline.

Covers: salary credits, UPI spends in every amount band, card spends,
a self transfer (Axis -> Kotak), an ATM withdrawal (-> cash), an upcoming
AutoPay, a paid AutoPay, a refund-like credit, two Review items, and an
OTP + a promo that k must ignore.
"""

import argparse
import datetime as dt
import os
import subprocess
import sys
import time

ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")
today = dt.datetime.now().replace(second=0, microsecond=0)
_ref = 427900000000


def ref():
    global _ref
    _ref += 1
    return _ref


def at(days_ago, hhmm):
    h, m = map(int, hhmm.split(":"))
    return (today - dt.timedelta(days=days_ago)).replace(hour=h, minute=m, second=17)


def axis_upi(d, amt, kind, payee, credit=False):
    word = "credited" if credit else "debited"
    return ("AXISBK", f"INR {amt} {word} A/c no. XX1111 {d:%d-%m-%y, %H:%M:%S} "
            f"UPI/{kind}/{ref()}/{payee} Not you? SMS BLOCKUPI Cust ID to 919951860002 Axis Bank")


def axis_card(d, amt, merchant, avl):
    return ("AXISBK", f"Spent INR {amt} Axis Bank Card no. XX5678 {d:%d-%m-%y %H:%M:%S} IST "
            f"{merchant} Avl Limit: INR {avl} Not you? SMS BLOCK 5678 to 919951860002")


def kotak_sent(d, amt, to):
    return ("KOTAKB", f"Sent Rs.{amt} from Kotak Bank A/c X2222 to {to} on {d:%d-%m-%y}. "
            f"UPI Ref {ref()}. Not done by you? Tap https://kotak.bank.in/KBANKT/Fraud")


def bob_upi(d, amt, vpa, bal):
    return ("BOBSMS", f"Rs.{amt} Dr. from A/C XXXXXX3333 and Cr. to {vpa}. Ref:{ref()}. "
            f"AvlBal:Rs{bal}({d:%Y:%m:%d %H:%M:%S}). Not you? Call 18005700/5000-BOB")


def messages():
    m = []
    # Earlier months, so Summary has six months of history.
    for back, day in ((95, "11:20"), (64, "13:05"), (33, "19:40")):
        m.append(("AXISBK", f"INR 85000.00 credited to A/c no. XX1111 on {at(back, '10:00'):%d-%m-%y} at 10:00:17 IST. "
                  f"Info - NEFT/IN26{ref()}/ACME. Chk Bal https://ccm.axis.bank.in/AXISBK/XXXXXXXX - Axis Bank"))
        m.append(axis_upi(at(back - 2, day), "2,340.00", "P2M", "DMART"))
        m.append(axis_card(at(back - 5, "21:10"), "3,499", "FLIPKART INTERNET", "71,500.00"))
        m.append(kotak_sent(at(back - 8, "08:45"), "640.00", "SWIGGY"))
    # This month.
    first = (today.day - 1)
    m.append(("AXISBK", f"INR 85000.00 credited to A/c no. XX1111 on {at(first, '10:00'):%d-%m-%y} at 10:00:17 IST. "
              f"Info - NEFT/IN26{ref()}/ACME. Chk Bal https://ccm.axis.bank.in/AXISBK/XXXXXXXX - Axis Bank"))
    m += [
        axis_upi(at(6, "08:10"), "15.00", "P2M", "CHAI POINT"),
        axis_upi(at(6, "13:32"), "312.00", "P2M", "ZOMATO"),
        kotak_sent(at(5, "09:05"), "50.00", "DMRC"),
        axis_upi(at(5, "18:20"), "15000.00", "P2A", "RAHUL SHARMA"),
        axis_card(at(4, "20:11"), "1,299", "AMAZON PAY IN E", "85,420.50"),
        bob_upi(at(4, "10:22"), "25.00", "guptastores@ybl", "12000.50"),
        kotak_sent(at(3, "19:45"), "208.00", "ZEPTO MARKETPLACE PR"),
        axis_upi(at(3, "21:02"), "450.00", "P2M", "SWIGGY"),
        ("AXISBK", f"INR 2,000.00 withdrawn at ATM S1ANDL123 from A/c no. XX1111 on {at(2, '18:44'):%d-%m-%y} 18:44:12. "
                   "Avl Bal INR 41,345.67 - Axis Bank"),
        bob_upi(at(1, "10:18"), "199.00", "zeptonowcashfree@hdfcbank", "11801.50"),
        axis_card(at(1, "22:40"), "2,499", "MYNTRA DESIGNS", "82,921.50"),
        axis_upi(at(1, "09:30"), "1,500.00", "P2A", "RAHUL SHARMA", credit=True),
        ("KOTAKB", f"AUTOPAY of Rs.195.00 to APPLE MEDIA SERVICES on {at(1, '06:00'):%d-%b-%y} was successful. "
                   "View details: https://kotk.in/KOTAKD/XXXXXX -Kotak"),
        axis_upi(at(0, "08:55"), "120.00", "P2M", "UBER INDIA"),
        kotak_sent(at(0, "13:10"), "80.00", "chaipoint@ybl"),
        # Self transfer Axis -> Kotak. Kotak's "Received" names no time, so
        # it takes the arrival time: both sides must be "now" to link.
        axis_upi(today - dt.timedelta(minutes=2), "5000.00", "P2A", "ADITYA M"),
        ("KOTAKB", f"Received Rs.5000.00 in your Kotak Bank AC 2222 from ADITYA M on {today:%d-%m-%y}.UPI Ref:{ref()}"),
        # Upcoming AutoPay, due in 3 days.
        ("KOTAKB", f"Upcoming debit: Rs.649.00 will be debited from your Kotak Bank AC X2222 on "
                   f"{today + dt.timedelta(days=3):%d-%m-%y} towards NETFLIX for UPI-Mandate. UMN: KKBK000{ref()}"),
        # Review queue.
        ("AXISBK", f"Your a/c XX1111 has been debited for Rs 99 towards SOMETHING NEW ref no {ref()}. Axis Bank"),
        ("BOBTXN", f"Rs.500.00 credited to A/c XXXXXX3333 towards reversal of failed UPI txn Ref {ref()}. -Bank of Baroda"),
        # Must be ignored.
        ("AXISBK", "123456 is the OTP for transaction of INR 1,299.00 at AMAZON on Axis Bank card XX5678. Valid for 10 mins. Do not share it with anyone."),
        ("AXISBK", "Congratulations! You are pre-approved for a Personal Loan of up to INR 5,00,000 from Axis Bank. Apply now: https://axis.bank.in/pl"),
    ]
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--gap", type=float, default=1.5, help="seconds between messages")
    args = ap.parse_args()
    msgs = messages()
    for i, (sender, body) in enumerate(msgs, 1):
        assert "\n" not in body
        print(f"[{i:2}/{len(msgs)}] {sender}: {body[:90]}…")
        if args.dry_run:
            continue
        r = subprocess.run([ADB, "emu", "sms", "send", sender, body], capture_output=True, text=True)
        if r.returncode != 0 or "KO" in r.stdout:
            sys.exit(f"adb emu sms send failed: {r.stdout}{r.stderr}")
        time.sleep(args.gap)
    print("Sent. Open k; Review should hold 2 items, the OTP and promo none.")


if __name__ == "__main__":
    main()
