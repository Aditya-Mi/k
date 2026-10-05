#!/usr/bin/env bash
# Smoke test a release APK on a running emulator (CI or local):
#   tool/smoke_test.sh build/app/outputs/flutter-apk/app-release.apk
#
# Catches what unit tests can't: R8 stripping something the app needs
# (1.0.0 crashed on start), native SMS capture, the headless SMS worker.
#   1. install, grant SMS + notification permissions
#   2. cold start → still running after 20 s, no crash in logcat
#   3. app killed in the background → bank SMS arrives → the worker
#      boots headless Dart and logs it ("k: background SMS drained, logged 1")
#   4. start again → still running, no crash
set -euo pipefail

APK=${1:?usage: smoke_test.sh <apk>}
PKG=dev.adityamittal.k
LOG=$(mktemp)

fail() {
  echo "SMOKE FAIL: $*"
  echo "---- logcat (k, flutter, crashes) ----"
  adb logcat -d -b crash | tail -80 || true
  adb logcat -d -s flutter:* | tail -80 || true
  exit 1
}

# Only k counts: the crash buffer (Java + native crashes) naming k, and
# k's own Dart errors / "k: … failed" lines. Other apps on the emulator
# log plenty of "failed" and crash on their own.
crashed() {
  {
    adb logcat -d -b crash | grep -F "$PKG"
    adb logcat -d -s flutter:* | grep -E " E flutter|flutter *: k: .*failed"
  } >"$LOG" || true
  if [ -s "$LOG" ]; then
    echo "---- matched ----"
    cat "$LOG"
    return 0
  fi
  return 1
}

running() { adb shell pidof "$PKG" >/dev/null 2>&1; }

adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done

echo "== install"
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -r "$APK"
for p in RECEIVE_SMS READ_SMS POST_NOTIFICATIONS; do
  adb shell pm grant "$PKG" "android.permission.$p" 2>/dev/null || true
done

echo "== cold start"
adb logcat -b all -c
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 20
running || fail "app is not running after cold start"
crashed && fail "crash on cold start"

echo "== SMS with the app in the background"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am kill "$PKG"
sleep 2
adb logcat -b all -c
# One line: the emulator console cuts an SMS at the first newline.
adb emu sms send AXISBK "INR 2,000.00 withdrawn at ATM S1ANDL123 from A/c no. XX1234 on 02-10-26 18:44:12. Avl Bal INR 10,345.67 - Axis Bank"
for _ in $(seq 1 45); do
  adb logcat -d | grep -q "k: background SMS drained" && break
  sleep 2
done
adb logcat -d | grep "k: background SMS drained" ||
  fail "background worker never drained the SMS"
adb logcat -d | grep -q "k: background SMS drained, logged 1" ||
  fail "SMS reached the worker but wasn't logged as a payment"
crashed && fail "crash in the background SMS worker"

echo "== start again"
adb logcat -b all -c
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
sleep 15
running || fail "app is not running after restart"
crashed && fail "crash on restart"

echo "SMOKE OK"
