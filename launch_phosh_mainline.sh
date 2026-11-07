#!/bin/sh
set -e

echo "=============================================="
echo " Starting Phosh Mobile Desktop on Xiaomi 15   "
echo "=============================================="

# 1. Mount tmpfs for rootfs
mkdir -p /rootfs
if [ ! -f /rootfs/usr/libexec/phosh ]; then
    echo "[1/6] Mounting 4GB tmpfs on /rootfs..."
    mount -t tmpfs -o size=4G tmpfs /rootfs 2>/dev/null || true
    echo "[1/6] Downloading & unpacking Alpine Phosh rootfs..."
    wget -q -O - http://172.16.42.2:8000/alpine-phosh-ready.tar.gz | tar -C /rootfs -xzf -
    echo "[1/6] Rootfs unpacked successfully."
else
    echo "[1/6] /rootfs already exists, skipping unpack."
fi

# 2. Mount virtual filesystems
echo "[2/6] Binding system filesystems..."
mkdir -p /rootfs/proc /rootfs/sys /rootfs/dev /rootfs/dev/pts /rootfs/dev/shm /rootfs/run /rootfs/run/dbus /rootfs/tmp/xdg
chmod 700 /rootfs/tmp/xdg

mount --bind /proc /rootfs/proc 2>/dev/null || true
mount --bind /sys /rootfs/sys 2>/dev/null || true
mount --bind /dev /rootfs/dev 2>/dev/null || true
mount -t devpts -o ptmxmode=666,mode=620 devpts /rootfs/dev/pts 2>/dev/null || true
mount -t tmpfs -o mode=1777 tmpfs /rootfs/dev/shm 2>/dev/null || true
mount -t tmpfs tmpfs /rootfs/run 2>/dev/null || true
mkdir -p /rootfs/run/dbus

echo "nameserver 1.1.1.1" > /rootfs/etc/resolv.conf

# Device permissions
chmod 666 /rootfs/dev/dri/* 2>/dev/null || true
chmod 666 /rootfs/dev/input/* 2>/dev/null || true

# Set AMOLED screen brightness
if [ -d /sys/class/backlight/ae94000.dsi.0 ]; then
    echo 2500 > /sys/class/backlight/ae94000.dsi.0/brightness 2>/dev/null || true
fi

# 3. Start udevd, dbus, elogind, seatd
echo "[3/6] Starting system daemons (udevd, dbus, elogind, seatd)..."
chroot /rootfs /sbin/udevd --daemon 2>/dev/null || true
chroot /rootfs /bin/udevadm trigger --action=add 2>/dev/null || true
chroot /rootfs /bin/udevadm settle 2>/dev/null || true

rm -f /rootfs/run/dbus/dbus.pid /rootfs/run/elogind.pid /rootfs/run/seatd.sock
chroot /rootfs /usr/bin/dbus-uuidgen --ensure 2>/dev/null || true
chroot /rootfs /usr/bin/dbus-daemon --system --fork 2>/dev/null || true
chroot /rootfs /usr/libexec/elogind --daemon 2>/dev/null || true
chroot /rootfs /usr/bin/env SEATD_VTBOUND=0 /usr/bin/seatd -u root -g root </dev/null >/rootfs/tmp/seatd.log 2>&1 &
sleep 1
chmod 666 /rootfs/run/seatd.sock 2>/dev/null || true

# 4. Phosh configuration
echo "[4/6] Setting up Phoc and Phosh configs..."
mkdir -p /rootfs/etc/phosh
cat << 'EOF' > /rootfs/etc/phosh/phoc.ini
[core]
xwayland=false

[output:DSI-1]
scale = 3
rotate = normal
EOF

# 5. Launch Phosh Session
echo "[5/6] Launching Phosh session..."
killall -9 phoc gnome-session phosh squeekboard 2>/dev/null || true
rm -rf /rootfs/tmp/xdg/*
sleep 1

chroot /rootfs /usr/bin/env \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root \
    USER=root \
    LOGNAME=root \
    XDG_RUNTIME_DIR=/tmp/xdg \
    WLR_BACKENDS=drm,libinput \
    WLR_DRM_DEVICES=/dev/dri/card0 \
    WLR_RENDERER=pixman \
    WLR_NO_HARDWARE_CURSORS=1 \
    WLR_LIBINPUT_NO_DEVICES=1 \
    LIBSEAT_BACKEND=seatd \
    SEATD_VTBOUND=0 \
    /usr/bin/dbus-run-session -- /usr/bin/phosh-session </dev/null >/rootfs/tmp/phosh_session.log 2>&1 &

echo "[6/6] Phosh process initiated. Checking status in 3 seconds..."
sleep 3
ps | grep -E "phoc|phosh|seatd|dbus|gnome" || true
echo "=============================================="
echo " Phosh launch command completed! Check screen!"
echo "=============================================="
