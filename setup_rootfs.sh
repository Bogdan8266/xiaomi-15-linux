#!/bin/sh
set -e

echo "=== 1. Setting up 3GB RAM Rootfs ==="
mkdir -p /rootfs
if ! mountpoint -q /rootfs; then
    mount -t tmpfs -o size=3G tmpfs /rootfs
fi

cd /tmp
if [ ! -f /tmp/alpine.tar.gz ]; then
    echo "Downloading alpine-minirootfs..."
    wget http://172.16.42.2:8000/alpine-minirootfs-aarch64.tar.gz -O /tmp/alpine.tar.gz
fi

echo "Extracting alpine minirootfs..."
tar -xzf /tmp/alpine.tar.gz -C /rootfs
sed -i 's/https:/http:/g' /rootfs/etc/apk/repositories

echo "=== 2. Setting up mounts and network in rootfs ==="
mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/dev/pts /rootfs/run /rootfs/tmp /rootfs/etc/xdg/weston /rootfs/etc/udev/rules.d

# Bind system directories
mount --bind /dev /rootfs/dev
mount -t proc none /rootfs/proc
mount -t sysfs none /rootfs/sys
mount -t devpts none /rootfs/dev/pts

# DNS
echo "nameserver 1.1.1.1" > /rootfs/etc/resolv.conf
echo "nameserver 8.8.8.8" >> /rootfs/etc/resolv.conf

# Repositories (use official v3.20 HTTP mirror)
cat << 'EOF' > /rootfs/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/v3.20/main
http://dl-cdn.alpinelinux.org/alpine/v3.20/community
EOF

echo "=== 3. Installing Weston & GUI packages via proxy ==="
chroot /rootfs /bin/sh -c '
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export http_proxy=http://172.16.42.2:8080
export https_proxy=http://172.16.42.2:8080
/sbin/apk update
/sbin/apk add --no-cache \
    weston \
    weston-backend-drm \
    weston-shell-desktop \
    weston-clients \
    weston-terminal \
    seatd \
    eudev \
    libdrm-progs \
    mesa-dri-gallium \
    font-dejavu \
    bash \
    nano \
    strace
'

echo "=== 4. Configuring udev seat rules ==="
cat << 'EOF' > /rootfs/etc/udev/rules.d/71-seat.rules
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="seat", TAG+="master-of-seat", ENV{ID_SEAT}="seat0"
SUBSYSTEM=="input", ATTR{name}=="*", TAG+="seat", ENV{ID_SEAT}="seat0"
EOF

echo "=== 5. Configuring Weston ==="
cat << 'EOF' > /rootfs/etc/xdg/weston/weston.ini
[core]
backend=drm-backend.so
shell=desktop-shell.so
idle-time=0
require-input=false

[shell]
locking=false
background-color=0xff1e1e2e
panel-color=0xdd11111b
panel-position=top
clock-format=24h

[output]
name=DSI-1
mode=1200x2670@120
transform=normal
EOF

echo "=== 6. Creating Weston Startup Script ==="
cat << 'EOF' > /rootfs/start_desktop.sh
#!/bin/sh
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR

export SEATD_VTBOUND=0
export LIBSEAT_BACKEND=seatd

echo "Starting eudev..."
/sbin/udevd --daemon 2>/dev/null || true
udevadm trigger 2>/dev/null || true
udevadm settle 2>/dev/null || true

echo "Starting seatd..."
killall seatd 2>/dev/null || true
rm -f /run/seatd.sock
/usr/bin/seatd -u root -g root -l debug > /tmp/seatd.log 2>&1 &
sleep 1

echo "Verifying DRM master..."
ls -la /dev/dri/card0

echo "Launching Weston Compositor..."
exec /usr/bin/weston \
    --backend=drm \
    --renderer=pixman \
    --drm-device=card0 \
    --continue-without-input \
    --current-mode \
    --log=/tmp/weston.log
EOF
chmod +x /rootfs/start_desktop.sh

echo "=== Rootfs setup successfully completed! ==="
