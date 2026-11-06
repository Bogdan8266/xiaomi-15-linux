#!/bin/bash
set -e

WORK=/home/bodya/pmos-dada
TARGET=$WORK/test_initramfs_light

rm -rf "$TARGET"
mkdir -p "$TARGET"

echo "1. Copying base initramfs structure..."
cp -a $WORK/stock_initramfs/* "$TARGET/"

echo "2. Installing busybox..."
mkdir -p "$TARGET/bin" "$TARGET/sbin" "$TARGET/usr/bin" "$TARGET/usr/sbin"
cp "$WORK/busybox" "$TARGET/bin/busybox"
chmod 755 "$TARGET/bin/busybox"

# Create symlinks
cd "$TARGET/bin"
for applet in sh ash mount umount ls cat echo dmesg ifconfig telnetd ps kill mkdir rm cp mv sleep grep sed awk mknod chmod chown sync insmod rmmod modprobe; do
    ln -sf busybox "$applet"
done
cd "$WORK"

echo "3. Creating custom test /init script..."
cat << 'INIT_EOF' > "$TARGET/init"
#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/system/bin

# Install busybox symlinks
/bin/busybox --install -s /bin 2>/dev/null || true

# Mount kernel virtual filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Direct message to kmsg and console
echo "<0>[PMOS-TEST] =========================================" > /dev/kmsg
echo "<0>[PMOS-TEST]  XIAOMI 15 LINUX DIAGNOSTIC INIT BOOTED! " > /dev/kmsg
echo "<0>[PMOS-TEST] =========================================" > /dev/kmsg
echo "Xiaomi 15 Linux Diagnostic Init Booted!" > /dev/console 2>/dev/null || true

# Load vendor modules from vendor_boot (already merged into /lib/modules)
echo "<0>[PMOS-TEST] Checking vendor modules in /lib/modules..." > /dev/kmsg
if [ -d /lib/modules ]; then
    echo "<0>[PMOS-TEST] /lib/modules found with $(ls /lib/modules | wc -l) modules" > /dev/kmsg
    
    # Load display modules
    for mod in dispcc-sun.ko drm_display_helper.ko msm_drm.ko; do
        if [ -f "/lib/modules/$mod" ]; then
            echo "<0>[PMOS-TEST] Loading $mod..." > /dev/kmsg
            insmod "/lib/modules/$mod" 2>/dev/null || true
        fi
    done
fi

# Check display device
if [ -e /dev/dri/card0 ]; then
    echo "<0>[PMOS-TEST] SUCCESS: /dev/dri/card0 exists!" > /dev/kmsg
else
    echo "<0>[PMOS-TEST] NOTE: /dev/dri/card0 not found yet" > /dev/kmsg
fi

# Configure USB Gadget (CDC-NCM Ethernet)
echo "<0>[PMOS-TEST] Setting up USB Gadget CDC-NCM..." > /dev/kmsg
mkdir -p /config
mount -t configfs none /config 2>/dev/null || true

if [ -d /config/usb_gadget ]; then
    mkdir -p /config/usb_gadget/g1
    cd /config/usb_gadget/g1
    echo "0x18d1" > idVendor
    echo "0xd002" > idProduct
    mkdir -p strings/0x409
    echo "Xiaomi" > strings/0x409/manufacturer
    echo "Xiaomi 15 Linux Test" > strings/0x409/product
    echo "dada-pmos-001" > strings/0x409/serialnumber

    mkdir -p configs/c.1/strings/0x409
    echo "Linux NCM Config" > configs/c.1/strings/0x409/configuration
    mkdir -p functions/ncm.0
    ln -sf functions/ncm.0 configs/c.1/ 2>/dev/null || true

    UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1)
    if [ -n "$UDC" ]; then
        echo "$UDC" > UDC 2>/dev/null || true
        echo "<0>[PMOS-TEST] Bound UDC: $UDC" > /dev/kmsg
    fi
    cd /
fi

# Configure network and launch Telnet server
sleep 2
ifconfig usb0 172.16.42.1 netmask 255.255.255.0 up 2>/dev/null || true
echo "<0>[PMOS-TEST] Assigned IP 172.16.42.1 to usb0" > /dev/kmsg

# Start telnetd on port 23
/bin/busybox telnetd -l /bin/sh -p 23 2>/dev/null || true
echo "<0>[PMOS-TEST] Telnet daemon running on 172.16.42.1:23" > /dev/kmsg

# Main diagnostic loop
COUNT=0
while true; do
    COUNT=$((COUNT + 1))
    echo "<0>[PMOS-TEST] Heartbeat #$COUNT (uptime: $(cat /proc/uptime 2>/dev/null | cut -d' ' -f1)s)" > /dev/kmsg
    sleep 5
done
INIT_EOF

chmod 755 "$TARGET/init"

echo "4. Packing cpio archive..."
cd "$TARGET"
find . -mindepth 1 | cpio -o -H newc > "$WORK/test_ramdisk_light.cpio"

echo "5. Compressing with gzip..."
gzip -9 -c "$WORK/test_ramdisk_light.cpio" > "$WORK/test_ramdisk_light.cpio.gz"

echo "6. Creating init_boot image with mkbootimg..."
mkbootimg \
  --header_version 4 \
  --ramdisk "$WORK/test_ramdisk_light.cpio.gz" \
  --pagesize 4096 \
  -o "$WORK/test_init_boot_light.img"

echo "Done! Image info:"
ls -lh "$WORK/test_init_boot_light.img"
