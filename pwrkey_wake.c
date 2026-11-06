#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

typedef char gchar;
typedef void* gpointer;
typedef struct _GVariant GVariant;
typedef struct _GVariantType GVariantType;
typedef struct _GDBusConnection GDBusConnection;
typedef struct _GCancellable GCancellable;
typedef struct _GError GError;

extern GDBusConnection *g_bus_get_sync(int bus_type, GCancellable *cancellable, GError **error);
extern GVariant *g_variant_new(const gchar *format_string, ...);
extern void g_variant_unref(GVariant *value);
extern GVariant *g_dbus_connection_call_sync(
    GDBusConnection *connection,
    const gchar *bus_name,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *method_name,
    GVariant *parameters,
    const GVariantType *reply_type,
    int flags,
    int timeout_msec,
    GCancellable *cancellable,
    GError **error);

struct input_event {
    uint64_t tv_sec;
    uint64_t tv_usec;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

static void ensure_dbus_env(void) {
    if (getenv("DBUS_SESSION_BUS_ADDRESS")) return;
    DIR *d = opendir("/proc");
    if (!d) return;
    struct dirent *de;
    while ((de = readdir(d))) {
        if (de->d_name[0] < '0' || de->d_name[0] > '9') continue;
        char cmdpath[64], cmdline[64];
        snprintf(cmdpath, sizeof(cmdpath), "/proc/%s/cmdline", de->d_name);
        FILE *f = fopen(cmdpath, "r");
        if (!f) continue;
        int len = fread(cmdline, 1, sizeof(cmdline) - 1, f);
        fclose(f);
        if (len <= 0) continue;
        cmdline[len] = '\0';
        if (strstr(cmdline, "phosh")) {
            char envpath[64], envbuf[4096];
            snprintf(envpath, sizeof(envpath), "/proc/%s/environ", de->d_name);
            f = fopen(envpath, "r");
            if (!f) continue;
            int n = fread(envbuf, 1, sizeof(envbuf) - 1, f);
            fclose(f);
            if (n <= 0) continue;
            envbuf[n] = '\0';
            for (char *p = envbuf; p < envbuf + n; p += strlen(p) + 1) {
                if (strncmp(p, "DBUS_SESSION_BUS_ADDRESS=", 25) == 0) {
                    setenv("DBUS_SESSION_BUS_ADDRESS", p + 25, 1);
                    break;
                }
            }
            break;
        }
    }
    closedir(d);
}

static int open_pwrkey_device(void) {
    char path[128], name[128];
    for (int i = 0; i < 16; i++) {
        snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
        FILE *f = fopen(path, "r");
        if (f) {
            if (fgets(name, sizeof(name), f)) {
                if (strstr(name, "pwrkey")) {
                    fclose(f);
                    snprintf(path, sizeof(path), "/dev/input/event%d", i);
                    int fd = open(path, O_RDONLY);
                    if (fd >= 0) return fd;
                }
            }
            fclose(f);
        }
    }
    return open("/dev/input/event2", O_RDONLY);
}

static int is_screen_off(void) {
    FILE *f = fopen("/sys/class/backlight/panel0-backlight/bl_power", "r");
    int bl = 0;
    if (f) {
        if (fscanf(f, "%d", &bl) != 1) bl = 0;
        fclose(f);
    }
    if (bl != 0) return 1;

    f = fopen("/sys/class/drm/card0-DSI-1/dpms", "r");
    if (f) {
        char buf[32] = {0};
        if (fgets(buf, sizeof(buf), f)) {
            if (strncmp(buf, "Off", 3) == 0) {
                fclose(f);
                return 1;
            }
        }
        fclose(f);
    }
    return 0;
}

static void enable_touch(void) {
    FILE *tf = fopen("/sys/class/touch/touch_dev/enable_touch_raw", "w");
    if (tf) {
        fprintf(tf, "0\n");
        fclose(tf);
    }
}

int main(void) {
    int fd = open_pwrkey_device();
    if (fd < 0) return 1;

    GDBusConnection *conn = NULL;
    struct input_event ev;
    int was_off_on_press = 0;

    while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == 1 && ev.code == 116) { /* EV_KEY, KEY_POWER */
            if (ev.value == 1) {
                was_off_on_press = is_screen_off();
            } else if (ev.value == 0) {
                if (was_off_on_press) {
                    usleep(50000);
                    ensure_dbus_env();
                    if (!conn) {
                        conn = g_bus_get_sync(2, NULL, NULL);
                    }
                    if (conn) {
                        GVariant *res = g_dbus_connection_call_sync(
                            conn,
                            "org.gnome.ScreenSaver",
                            "/org/gnome/ScreenSaver",
                            "org.gnome.ScreenSaver",
                            "SetActive",
                            g_variant_new("(b)", 0),
                            NULL,
                            0,
                            1000,
                            NULL,
                            NULL);
                        if (res) g_variant_unref(res);
                    }
                    usleep(250000);
                    enable_touch();
                    was_off_on_press = 0;
                }
            }
        }
    }
    return 0;
}
