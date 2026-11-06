#!/bin/sh
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR

export SEATD_VTBOUND=0
export LIBSEAT_BACKEND=seatd
export LD_PRELOAD=/usr/lib/libfix_drm_formats.so

echo "Starting seatd..."
killall seatd 2>/dev/null || true
rm -f /run/seatd.sock
/usr/bin/seatd -u root -g root -l debug > /tmp/seatd.log 2>&1 &
sleep 1

# Launch weston-terminal automatically once Wayland socket is ready
(
    for i in $(seq 1 50); do
        W_SOCK=$(ls $XDG_RUNTIME_DIR/wayland-[0-9]* 2>/dev/null | grep -v "\.lock" | head -n1)
        if [ -n "$W_SOCK" ]; then
            echo "Found Wayland socket: $W_SOCK"
            export WAYLAND_DISPLAY=$(basename "$W_SOCK")
            sleep 1
            echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null || true
            echo 2048 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || true
            /usr/bin/weston-terminal &
            echo "Launched weston-terminal on $WAYLAND_DISPLAY"
            sleep 0.5
            /usr/bin/weston-flower &
            echo "Launched weston-flower animation on $WAYLAND_DISPLAY"
            break
        fi
        sleep 0.2
    done
) > /tmp/autolaunch.log 2>&1 &

echo "Starting Weston Compositor..."
exec /usr/bin/weston \
    --backend=drm \
    --renderer=pixman \
    --drm-device=card0 \
    --continue-without-input \
    --log=/tmp/weston.log
