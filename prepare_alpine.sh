#!/bin/sh
set -e

echo "=== 1. System Safeguards ==="
echo 0 > /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null || true
echo 0 > /proc/sys/kernel/panic_on_rcu_stall 2>/dev/null || true
echo 0 > /proc/sys/kernel/panic_on_oops 2>/dev/null || true
rmmod gh_virt_wdt 2>/dev/null || true
rmmod qcom_wdt_core 2>/dev/null || true
echo 1 > /sys/bus/platform/devices/hypervisor:qcom,gh-watchdog/disable 2>/dev/null || true
touch /tmp/keep
mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

echo "=== 2. Creating Essential Device Nodes ==="
mkdir -p /dev/dri /dev/dma_heap /dev/input
mknod /dev/dri/card0 c 226 0 2>/dev/null || true
mknod /dev/dri/renderD128 c 226 128 2>/dev/null || true
mknod /dev/dma_heap/qcom,display c 248 4 2>/dev/null || true
mknod /dev/dma_heap/system c 248 1 2>/dev/null || true
mknod /dev/input/event0 c 13 64 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7 8 9; do
    mknod /dev/gpiochip$i c 254 $i 2>/dev/null || true
    chmod 666 /dev/gpiochip$i 2>/dev/null || true
done
chmod -R 666 /dev/dri /dev/dma_heap /dev/input 2>/dev/null || true

echo "=== 3. Checking / Loading DRM Stack ==="
if [ ! -c /dev/dri/card0 ] || [ $(lsmod | grep -c msm_drm) -eq 0 ]; then
    cd /tmp
    if [ ! -d /tmp/drm ]; then
        wget -q http://172.16.42.2:8000/drm_all.tar.gz -O /tmp/drm_all.tar.gz
        mkdir -p /tmp/drm
        tar -xzf /tmp/drm_all.tar.gz -C /tmp/drm/
    fi
    wget -q http://172.16.42.2:8000/load_drm_smart.sh -O /tmp/drm/load_drm_smart.sh
    chmod +x /tmp/drm/load_drm_smart.sh
    /tmp/drm/load_drm_smart.sh
else
    echo "msm_drm already loaded and /dev/dri/card0 exists."
fi

echo "=== 4. Setting up 3GB RAM Rootfs ==="
mkdir -p /rootfs
if ! mountpoint -q /rootfs; then
    mount -t tmpfs -o size=3G tmpfs /rootfs
fi

if [ ! -f /rootfs/bin/sh ] || [ ! -f /rootfs/usr/bin/weston ]; then
    echo "Deploying Alpine minirootfs..."
    if [ ! -f /tmp/alpine.tar.gz ]; then
        wget -q http://172.16.42.2:8000/alpine-minirootfs-aarch64.tar.gz -O /tmp/alpine.tar.gz
    fi
    tar -xzf /tmp/alpine.tar.gz -C /rootfs

    sed -i 's/https:/http:/g' /rootfs/etc/apk/repositories 2>/dev/null || true

    mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/dev/pts /rootfs/run /rootfs/tmp /rootfs/etc/xdg/weston /rootfs/etc/udev/rules.d
    mountpoint -q /rootfs/dev || mount --bind /dev /rootfs/dev
    mountpoint -q /rootfs/proc || mount -t proc none /rootfs/proc
    mountpoint -q /rootfs/sys || mount -t sysfs none /rootfs/sys
    mountpoint -q /rootfs/dev/pts || mount -t devpts none /rootfs/dev/pts

    echo "nameserver 1.1.1.1" > /rootfs/etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /rootfs/etc/resolv.conf

    echo "=== 5. Installing Alpine GUI Packages via Proxy ==="
    chroot /rootfs /bin/sh -c '
    export PATH=/sbin:/usr/sbin:/bin:/usr/bin
    export http_proxy=http://172.16.42.2:8080
    /sbin/apk update
    /sbin/apk add --no-cache \
        weston \
        weston-backend-drm \
        weston-shell-desktop \
        weston-clients \
        weston-terminal \
        seatd \
        font-dejavu \
        bash \
        nano \
        gcc \
        musl-dev
    '
fi

mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/dev/pts /rootfs/run /rootfs/tmp /rootfs/etc/xdg/weston /rootfs/etc/udev/rules.d
mountpoint -q /rootfs/dev || mount --bind /dev /rootfs/dev
mountpoint -q /rootfs/proc || mount -t proc none /rootfs/proc
mountpoint -q /rootfs/sys || mount -t sysfs none /rootfs/sys
mountpoint -q /rootfs/dev/pts || mount -t devpts none /rootfs/dev/pts

echo "=== 6. Compiling Compatibility Fix Shim (libfix_drm_formats.so) ==="
cat << 'EOF' > /rootfs/tmp/fix_drm_formats.c
#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <dlfcn.h>
#include <stdio.h>

struct wl_array {
    size_t size;
    size_t alloc;
    void *data;
};

struct weston_drm_format {
    uint32_t format;
    struct wl_array modifiers;
};

struct weston_drm_format_array {
    struct wl_array arr;
};

extern void *wl_array_add(struct wl_array *array, size_t size);
extern void wl_array_init(struct wl_array *array);
extern struct weston_drm_format *weston_drm_format_array_find_format(const struct weston_drm_format_array *formats, uint32_t format);
extern bool weston_drm_format_has_modifier(const struct weston_drm_format *format, uint64_t modifier);

struct weston_drm_format *
weston_drm_format_array_add_format(struct weston_drm_format_array *formats, uint32_t format)
{
    struct weston_drm_format *fmt = weston_drm_format_array_find_format(formats, format);
    if (fmt)
        return fmt;

    fmt = (struct weston_drm_format *)wl_array_add(&formats->arr, sizeof(*fmt));
    if (!fmt)
        return NULL;

    fmt->format = format;
    wl_array_init(&fmt->modifiers);
    return fmt;
}

int
weston_drm_format_add_modifier(struct weston_drm_format *format, uint64_t modifier)
{
    uint64_t *mod;
    if (weston_drm_format_has_modifier(format, modifier))
        return 0;

    mod = (uint64_t *)wl_array_add(&format->modifiers, sizeof(*mod));
    if (!mod)
        return -1;

    *mod = modifier;
    return 0;
}

static inline const char *fix_ptr(const char *p) {
    if (((uintptr_t)p >> 32) == 0xffffffff) {
        int dummy;
        uintptr_t stack_high = (uintptr_t)&dummy & ~0xffffffffULL;
        return (const char *)(((uintptr_t)p & 0xffffffffULL) | stack_high);
    }
    return p;
}

int strcmp(const char *s1, const char *s2) {
    s1 = fix_ptr(s1);
    s2 = fix_ptr(s2);
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

typedef struct _drmModeEncoder {
    uint32_t encoder_id;
    uint32_t encoder_type;
    uint32_t crtc_id;
    uint32_t possible_crtcs;
    uint32_t possible_clones;
} drmModeEncoder, *drmModeEncoderPtr;

drmModeEncoderPtr drmModeGetEncoder(int fd, uint32_t encoder_id) {
    static drmModeEncoderPtr (*real_drmModeGetEncoder)(int, uint32_t) = NULL;
    if (!real_drmModeGetEncoder) {
        void *h = dlopen("/usr/lib/libdrm.so.2", RTLD_NOW | RTLD_GLOBAL);
        if (h) {
            real_drmModeGetEncoder = (drmModeEncoderPtr (*)(int, uint32_t))dlsym(h, "drmModeGetEncoder");
        }
    }
    if (!real_drmModeGetEncoder) {
        return NULL;
    }
    drmModeEncoderPtr enc = real_drmModeGetEncoder(fd, encoder_id);
    if (enc) {
        if (enc->encoder_id == 32 || enc->encoder_id == 63) {
            enc->possible_crtcs = 0;
        } else if (enc->encoder_id == 66) {
            enc->possible_crtcs = 0x00000001;
        }
    }
    return enc;
}
EOF

chroot /rootfs /bin/sh -c '
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
/usr/bin/gcc -O2 -fPIC -shared -o /usr/lib/libfix_drm_formats.so /tmp/fix_drm_formats.c /usr/lib/libwayland-server.so.0 /usr/lib/libweston-12.so.0 -ldl
'

echo "=== 7. Configuring weston.ini ==="
mkdir -p /rootfs/etc/xdg/weston /rootfs/root/.config
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
name=Virtual-1
mode=off

[output]
name=Virtual-2
mode=off

[output]
name=DSI-1
mode=preferred
transform=normal

[launcher]
icon=/usr/share/weston/terminal.png
path=/usr/bin/weston-terminal
EOF
cp /rootfs/etc/xdg/weston/weston.ini /rootfs/root/.config/weston.ini

echo "=== 8. Installing start_desktop.sh ==="
wget -q http://172.16.42.2:8000/start_desktop.sh -O /rootfs/start_desktop.sh
chmod +x /rootfs/start_desktop.sh

echo "=== 9. Packaging Rootfs for Instant Deployment ==="
cd /rootfs
tar -czf /tmp/alpine-desktop-ready.tar.gz \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./dev/*' \
    --exclude='./tmp/*' \
    --exclude='./run/*' \
    .
echo "Rootfs package created: $(ls -lh /tmp/alpine-desktop-ready.tar.gz)"

echo "=== BRINGUP SCRIPT SETUP COMPLETE ==="
