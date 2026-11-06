#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>

struct ff_replay { uint16_t length; uint16_t delay; };
struct ff_trigger { uint16_t button; uint16_t interval; };
struct ff_constant_effect { int16_t level; uint16_t env_attack_len, env_attack_lvl, env_fade_len, env_fade_lvl; };
struct ff_rumble_effect { uint16_t strong_magnitude; uint16_t weak_magnitude; };
struct ff_effect {
    uint16_t type;
    int16_t id;
    uint16_t direction;
    struct ff_trigger trigger;
    struct ff_replay replay;
    union {
        struct ff_constant_effect constant;
        struct ff_rumble_effect rumble;
        uint64_t pad[4];
    } u;
};

int ioctl(int fd, int request, ...) {
    static int (*real_ioctl)(int, int, void *) = NULL;
    if (!real_ioctl) {
        real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    }
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    /* EVIOCSFF on 64-bit is _IOW(0x45, 0x80, struct ff_effect) = 0x40304580 */
    if ((request & 0xffff) == 0x4580 && arg != NULL) {
        struct ff_effect *e = (struct ff_effect *)arg;
        if (e->type == 0x50 || e->type == 0x51) {
            uint16_t mag = e->u.rumble.strong_magnitude;
            if (mag == 0) mag = 0x5000;
            int16_t level = (int16_t)(mag >> 1);
            if (level < 0x3000) level = 0x4800;
            memset(&e->u, 0, sizeof(e->u));
            e->type = 0x52; /* FF_CONSTANT */
            e->u.constant.level = level;
            if (e->replay.length < 25) e->replay.length = 25;
        }
    }
    return real_ioctl(fd, request, arg);
}
