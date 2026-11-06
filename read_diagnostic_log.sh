#!/bin/bash
set -e
echo "Waiting for fastboot..."
while ! fastboot devices | grep -q fastboot; do
    sleep 1
done
echo "Fastboot detected!"
echo "Switching active slot to a..."
fastboot set_active a
echo "Rebooting into ColorOS..."
fastboot reboot
echo "Waiting for ColorOS ADB..."
adb wait-for-device
echo "Waiting for Android to settle..."
sleep 5
echo "Extracting diagnostic log from recovery_b..."
adb shell "su -c 'dd if=/dev/block/by-name/recovery_b bs=1M count=1 2>/dev/null | strings | head -n 150'"
