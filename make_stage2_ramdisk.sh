#!/bin/bash
# Stage 2 Minimal: Native ELF PID 1 + minimal 37 vendor modules + CDC-NCM & Serial
# Flash result ONLY to init_boot_b. Slot _a (ColorOS) is never touched.
set -e

WORK=/home/bodya/pmos-dada
TARGET=$WORK/stage2_initramfs

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -a "$WORK"/stock_initramfs/* "$TARGET/"
rm -f "$TARGET/kernelsu.ko" "$TARGET/ksu_config"

mkdir -p "$TARGET/bin" "$TARGET/tmp" "$TARGET/etc" "$TARGET/config" "$TARGET/dev" "$TARGET/proc" "$TARGET/sys"
cp "$WORK/busybox" "$TARGET/bin/busybox"
chmod 755 "$TARGET/bin/busybox"
ln -sf busybox "$TARGET/bin/sh"

# Install native ELF binary as /init
cp "$WORK/mini_init" "$TARGET/init"
chmod 755 "$TARGET/init"

# Embed minimal 37 ordered modules
cp "$WORK/modules.minimal.ordered" "$TARGET/etc/modules.ordered"

cat > "$TARGET/etc/udhcpd.conf" << 'EOF'
start 172.16.42.2
end 172.16.42.2
interface usb0
max_leases 1
lease_file /tmp/udhcpd.leases
option subnet 255.255.255.0
EOF

cat > "$TARGET/init.sh" << 'INIT_EOF'
#!/bin/busybox sh
BB=/bin/busybox

$BB mount -t configfs none /config 2>/dev/null

[ -e /dev/kmsg ] || $BB mknod -m 600 /dev/kmsg c 1 11 2>/dev/null
[ -e /dev/null ] || $BB mknod -m 666 /dev/null c 1 3 2>/dev/null
[ -e /dev/zero ] || $BB mknod -m 666 /dev/zero c 1 5 2>/dev/null
[ -e /dev/ptmx ] || $BB mknod -m 666 /dev/ptmx c 5 2 2>/dev/null
[ -e /dev/console ] || $BB mknod -m 620 /dev/console c 5 1 2>/dev/null

$BB --install -s /bin
export PATH=/bin:/system/bin

log() {
    echo "<2>[STAGE2] $*" > /dev/kmsg 2>/dev/null || true
    echo "[STAGE2] $*" >> /tmp/stage2.log
}

log "init.sh started, uptime $(cut -d' ' -f1 /proc/uptime)"

# Load 37 minimal modules (Watchdog + dwc3 USB)
M=/lib/modules
LIST=/etc/modules.ordered
if [ -f "$LIST" ]; then
    ok=0; fail=0
    while read -r mod; do
        [ -z "$mod" ] && continue
        if insmod "$M/$mod" 2>/tmp/insmod.err; then
            ok=$((ok+1))
        else
            fail=$((fail+1))
            echo "[STAGE2] FAIL $mod: $(cat /tmp/insmod.err)" >> /tmp/stage2.log
        fi
    done < "$LIST"
    log "modules loaded: ok=$ok fail=$fail"
else
    log "ERROR: $LIST not found!"
fi

log "UDC list: $(ls /sys/class/udc 2>&1 | tr '\n' ' ')"

# USB gadget setup: CDC-NCM + USB Serial
G=/config/usb_gadget/g1
mkdir -p $G && cd $G
echo 0x05c6 > idVendor
echo 0x9025 > idProduct
mkdir -p strings/0x409
echo "Xiaomi" > strings/0x409/manufacturer
echo "Xiaomi 15 stage2" > strings/0x409/product
echo "dada15-stage2" > strings/0x409/serialnumber

mkdir -p functions/ncm.0 functions/cser.dun.0
mkdir -p configs/b.1/strings/0x409
echo "ncm_serial" > configs/b.1/strings/0x409/configuration
ln -s /config/usb_gadget/g1/functions/ncm.0 /config/usb_gadget/g1/configs/b.1/f1 2>/tmp/ln1.err
ln -s /config/usb_gadget/g1/functions/cser.dun.0 /config/usb_gadget/g1/configs/b.1/f2 2>/tmp/ln2.err

UDC=""
for i in $(seq 1 15); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
    [ -n "$UDC" ] && break
    sleep 1
done

if [ -n "$UDC" ]; then
    echo "$UDC" > UDC 2>/tmp/udc.err
    log "UDC bound to '$UDC': $(cat /tmp/udc.err)"
else
    log "ERROR: No UDC controller found after 15s!"
fi
cd /

# Bring up network interface and services
sleep 2
IF=$(cat $G/functions/ncm.0/ifname 2>/dev/null)
[ -z "$IF" ] && IF=usb0

log "Configuring network interface: $IF"
ifconfig "$IF" 172.16.42.1 netmask 255.255.255.0 up 2>/tmp/ifconfig.err || log "ifconfig err: $(cat /tmp/ifconfig.err)"

sed -i "s/^interface .*/interface $IF/" /etc/udhcpd.conf
touch /tmp/udhcpd.leases
udhcpd /etc/udhcpd.conf 2>/tmp/udhcpd.err || log "udhcpd err: $(cat /tmp/udhcpd.err)"

mkdir -p /dev/pts
$BB mount -t devpts devpts /dev/pts
telnetd -l /bin/sh -p 23
log "Services running. Telnet available on 172.16.42.1:23"

# Spawn interactive shell on USB serial port if available
for tty in /dev/cser.dun.0 /dev/ttyGS0; do
    if [ -e "$tty" ]; then
        log "Spawning shell on $tty"
        /bin/sh < "$tty" > "$tty" 2>&1 &
        break
    fi
done

# Safety timeout: 600 seconds (10 min) keepalive
n=0
while [ $n -lt 600 ]; do
    [ -f /tmp/keep ] && break
    sleep 5
    n=$((n+5))
done

if [ ! -f /tmp/keep ]; then
    log "No connection (/tmp/keep) after 600s -> rebooting"
    sync
    echo 1 > /proc/sys/kernel/sysrq
    echo b > /proc/sysrq-trigger
fi

log "Keeping shell alive permanently"
while true; do
    sleep 3600
done
INIT_EOF

chmod 755 "$TARGET/init.sh"

cd "$TARGET"
find . -mindepth 1 | cpio -o -H newc -R 0:0 2>/dev/null | gzip -9 > "$WORK/stage2_ramdisk.cpio.gz"
mkbootimg --header_version 4 --ramdisk "$WORK/stage2_ramdisk.cpio.gz" \
    --pagesize 4096 -o "$WORK/stage2_init_boot.img"

# Add AVB hash footer so ABL accepts the 8MB partition
avbtool add_hash_footer \
    --image "$WORK/stage2_init_boot.img" \
    --partition_size 8388608 \
    --partition_name init_boot \
    --algorithm NONE

ls -lh "$WORK/stage2_init_boot.img"
avbtool info_image --image "$WORK/stage2_init_boot.img"
