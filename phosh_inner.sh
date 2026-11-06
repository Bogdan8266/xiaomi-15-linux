#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export XDG_RUNTIME_DIR=/tmp/xdg
export XDG_CURRENT_DESKTOP=Phosh:GNOME
export XDG_SESSION_DESKTOP=phosh
export XDG_SESSION_TYPE=wayland
export GSK_RENDERER=cairo
export GDK_BACKEND=wayland
export LIBGL_ALWAYS_SOFTWARE=1
unset LD_PRELOAD

echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null || true
echo 2200 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || true
echo 0 > /sys/class/touch/touch_dev/enable_touch_raw 2>/dev/null || true

exec dbus-run-session -- sh -c '
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/gnome/wallpaper_abstract.jpg" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/gnome/wallpaper_abstract.jpg" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options "zoom" 2>/dev/null || true
    gsettings set org.sigxcpu.feedbackd profile "full" 2>/dev/null || true
    LD_PRELOAD=/usr/lib/libfix_vibra.so /usr/libexec/feedbackd > /tmp/feedbackd.log 2>&1 &
    /usr/libexec/gsd-power > /tmp/gsd-power.log 2>&1 &
    /usr/bin/squeekboard > /tmp/squeekboard.log 2>&1 &
    exec /usr/libexec/phosh -U > /tmp/phosh.log 2>&1
'
