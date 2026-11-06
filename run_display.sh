#!/bin/sh
killall -9 modetest 2>/dev/null
killall -9 weston 2>/dev/null
killall -9 sleep 2>/dev/null
sleep 1

# Configure ESD to simulated success
echo esd_sw_sim_success > /sys/kernel/debug/qcom,mdss_dsi_o3_42_0d_0a_dsc_cmd/esd_check_mode 2>/dev/null
echo 99999999 > /sys/kernel/debug/dri/0/DSI-1/esd_status_interval 2>/dev/null

# Setup persistent stdin for modetest
rm -f /tmp/hold_stdin
mkfifo /tmp/hold_stdin
sleep 99999999 > /tmp/hold_stdin &

# Run modetest
/tmp/modetest/lib/ld-musl-aarch64.so.1 --library-path /tmp/modetest/usr/lib:/tmp/modetest/lib /tmp/modetest/usr/bin/modetest -M msm_drm -s 67@206:#0 -v < /tmp/hold_stdin > /tmp/modetest.log 2>&1 &
MODEPID=$!

# Allow modeset to complete then enable backlight
sleep 2
echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null
echo 3000 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null

echo "Modetest launched with PID $MODEPID"
