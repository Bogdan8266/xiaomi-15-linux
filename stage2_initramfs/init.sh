#!/bin/busybox sh
BB=/bin/busybox

# Essential directories
$BB mkdir -p /dev /proc /sys /config /tmp /etc /bin /run /mnt /root
$BB chmod 1777 /tmp

# Mounts
$BB mount -t proc proc /proc 2>/dev/null
$BB mount -t sysfs sysfs /sys 2>/dev/null
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null
$BB mount -t configfs none /config 2>/dev/null
$BB mount -t tmpfs -o mode=1777 none /tmp 2>/dev/null

# Essential device nodes
[ -e /dev/kmsg ] || $BB mknod -m 600 /dev/kmsg c 1 11 2>/dev/null
[ -e /dev/null ] || $BB mknod -m 666 /dev/null c 1 3 2>/dev/null
[ -e /dev/zero ] || $BB mknod -m 666 /dev/zero c 1 5 2>/dev/null
[ -e /dev/ptmx ] || $BB mknod -m 666 /dev/ptmx c 5 2 2>/dev/null
[ -e /dev/console ] || $BB mknod -m 620 /dev/console c 5 1 2>/dev/null

# Busybox installation
$BB --install -s /bin
export PATH=/bin:/system/bin

# Immediate safeguards and watchdog neutralization
echo 0 > /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null || true
echo 0 > /proc/sys/kernel/panic_on_rcu_stall 2>/dev/null || true
echo 0 > /proc/sys/kernel/panic_on_oops 2>/dev/null || true
rmmod gh_virt_wdt 2>/dev/null || true
rmmod qcom_wdt_core 2>/dev/null || true
echo 1 > /sys/bus/platform/devices/hypervisor:qcom,gh-watchdog/disable 2>/dev/null || true

log() {
    echo "<2>[STAGE2] $*" > /dev/kmsg 2>/dev/null || true
    echo "[STAGE2] $*" >> /tmp/stage2.log
}

sync_to_flash() {
    REC_DEV=""
    [ -b /dev/block/by-name/recovery_b ] && REC_DEV=/dev/block/by-name/recovery_b
    [ -b /dev/sde61 ] && REC_DEV=/dev/sde61
    if [ -z "$REC_DEV" ]; then
        mknod -m 600 /dev/sde61 b 259 65 2>/dev/null
        [ -b /dev/sde61 ] && REC_DEV=/dev/sde61
    fi
    if [ -n "$REC_DEV" ]; then
        {
            echo "=== STAGE2 BOOT DIAGNOSTIC LOG ==="
            echo "Uptime: $(cut -d' ' -f1 /proc/uptime 2>/dev/null)"
            echo "--- stage2.log ---"
            cat /tmp/stage2.log 2>/dev/null
            echo "--- sys/class/udc ---"
            ls -la /sys/class/udc 2>/dev/null
            echo "--- ssusb files ---"
            ls -la /sys/devices/platform/soc/a600000.ssusb/ 2>/dev/null
            echo "--- loaded modules count ---"
            wc -l /proc/modules 2>/dev/null
            echo "--- dmesg full ---"
            dmesg 2>/dev/null
            echo "=== END DIAGNOSTIC LOG ==="
        } > /tmp/flash_sync.log 2>&1
        dd if=/tmp/flash_sync.log of="$REC_DEV" bs=1M 2>/dev/null
        sync
    fi
}

log "init.sh started, uptime $(cut -d' ' -f1 /proc/uptime)"

# Load ordered modules
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
            err=$(cat /tmp/insmod.err 2>/dev/null)
            echo "[STAGE2] FAIL $mod: $err" >> /tmp/stage2.log
            log "FAIL $mod: $err"
        fi
    done < "$LIST"
    log "modules loaded: ok=$ok fail=$fail"
else
    log "ERROR: $LIST not found!"
fi

# Force peripheral mode on USB controller
SSUSB=/sys/devices/platform/soc/a600000.ssusb
if [ -d "$SSUSB" ]; then
    log "Configuring a600000.ssusb: forcing peripheral mode"
    echo peripheral > $SSUSB/mode 2>/tmp/mode.err || log "mode err: $(cat /tmp/mode.err 2>/dev/null)"
    echo device > $SSUSB/usb_role/a600000.ssusb-role-switch/role 2>/tmp/role.err || true
    echo 1 > $SSUSB/bus_vote 2>/dev/null || true
    log "ssusb mode is now: $(cat $SSUSB/mode 2>/dev/null)"
else
    log "ERROR: $SSUSB does not exist!"
fi

# Poll for UDC controller up to 30 seconds
UDC=""
for i in $(seq 1 30); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
    [ -n "$UDC" ] && break
    # Re-trigger peripheral mode if not yet active
    [ -f "$SSUSB/mode" ] && echo peripheral > $SSUSB/mode 2>/dev/null
    sleep 1
done
log "UDC search result: '$UDC' (found after ${i}s)"

# USB gadget setup: CDC-NCM
G=/config/usb_gadget/g1
mkdir -p $G && cd $G
echo 0x18d1 > idVendor
echo 0x4ee7 > idProduct
mkdir -p strings/0x409
echo "Xiaomi" > strings/0x409/manufacturer
echo "Xiaomi 15 Linux" > strings/0x409/product
echo "bbfeb42b" > strings/0x409/serialnumber

mkdir -p functions/ncm.0 2>/dev/null
mkdir -p configs/b.1/strings/0x409
echo "ncm" > configs/b.1/strings/0x409/configuration
ln -s functions/ncm.0 configs/b.1/f1 2>/dev/null

if [ -n "$UDC" ]; then
    echo "$UDC" > UDC 2>/tmp/udc.err
    log "UDC bound to '$UDC': $(cat /tmp/udc.err 2>/dev/null)"
else
    log "ERROR: No UDC controller found!"
fi
cd /

# Bring up network interface and services
sleep 1
IF=$(cat /config/usb_gadget/g1/functions/ncm.0/ifname 2>/dev/null)
[ -z "$IF" ] && IF=usb0

log "Configuring network interface: $IF (172.16.42.1)"
ifconfig "$IF" 172.16.42.1 netmask 255.255.255.0 up 2>/tmp/ifconfig.err || log "ifconfig err: $(cat /tmp/ifconfig.err 2>/dev/null)"

cat > /etc/udhcpd.conf << UDHCP_EOF
start 172.16.42.2
end 172.16.42.2
interface $IF
max_leases 1
lease_file /tmp/udhcpd.leases
option subnet 255.255.255.0
UDHCP_EOF
touch /tmp/udhcpd.leases
udhcpd /etc/udhcpd.conf 2>/tmp/udhcpd.err || log "udhcpd err: $(cat /tmp/udhcpd.err 2>/dev/null)"

mkdir -p /dev/pts
mount -t devpts devpts /dev/pts 2>/dev/null
telnetd -l /bin/sh -p 23 2>/tmp/telnetd.err || log "telnetd err: $(cat /tmp/telnetd.err 2>/dev/null)"
nc -ll -p 1337 -e /bin/sh &
cat /proc/kmsg | nc -u 172.16.42.2 9999 &
log "SHELL SERVICES READY: Telnet:23, NC:1337, Live Dmesg:9999 on 172.16.42.1"

# Sync complete log to flash
sync_to_flash

# Keep shell alive permanently (NO REBOOT TIMEOUT)
touch /tmp/keep
log "Keeping shell alive permanently"
while true; do
    sleep 3600
done
