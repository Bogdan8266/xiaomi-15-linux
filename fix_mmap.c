#define _GNU_SOURCE
#include <sys/mman.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap) {
        real_mmap = dlsym(RTLD_NEXT, "mmap");
    }
    if (prot & PROT_WRITE) {
        prot |= PROT_READ;
    }
    return real_mmap(addr, length, prot, flags, fd, offset);
}

int strcmp(const char *s1, const char *s2) {
    if (s1 && s2) {
        if (s2[0] == 'I' && s2[1] == 'N' && s2[2] == '_' && s2[3] == 'F' && s2[4] == 'O') {
            if (s1[0] == 'I' && s1[1] == 'N' && s1[2] == '_' && s1[3] == 'F' && s1[4] == 'O') {
                return 1;
            }
        }
        if (s1[0] == 'I' && s1[1] == 'N' && s1[2] == '_' && s1[3] == 'F' && s1[4] == 'O') {
            if (s2[0] == 'I' && s2[1] == 'N' && s2[2] == '_' && s2[3] == 'F' && s2[4] == 'O') {
                return 1;
            }
        }
    }
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
    static drmModeEncoderPtr (*real_fn)(int, uint32_t) = NULL;
    if (!real_fn) {
        real_fn = dlsym(RTLD_NEXT, "drmModeGetEncoder");
    }
    drmModeEncoderPtr enc = real_fn(fd, encoder_id);
    if (enc) {
        if (enc->encoder_id == 32 || enc->encoder_id == 63) {
            enc->possible_crtcs = 0;
        } else if (enc->encoder_id == 66) {
            enc->possible_crtcs = 1;
        }
    }
    return enc;
}

typedef struct _drmModeConnector {
    uint32_t connector_id;
    uint32_t encoder_id;
    uint32_t connector_type;
    uint32_t connector_type_id;
    uint32_t connection;
    uint32_t mmWidth, mmHeight;
    uint32_t subpixel;
    int count_modes;
    void *modes;
    int count_props;
    uint32_t *props;
    uint64_t *prop_values;
    int count_encoders;
    uint32_t *encoders;
} drmModeConnector, *drmModeConnectorPtr;

drmModeConnectorPtr drmModeGetConnector(int fd, uint32_t connector_id) {
    static drmModeConnectorPtr (*real_fn)(int, uint32_t) = NULL;
    if (!real_fn) {
        real_fn = dlsym(RTLD_NEXT, "drmModeGetConnector");
    }
    drmModeConnectorPtr conn = real_fn(fd, connector_id);
    if (conn && (conn->connector_id == 33 || conn->connector_id == 64)) {
        conn->connection = 2; /* DRM_MODE_DISCONNECTED */
    }
    return conn;
}

drmModeConnectorPtr drmModeGetConnectorCurrent(int fd, uint32_t connector_id) {
    static drmModeConnectorPtr (*real_fn)(int, uint32_t) = NULL;
    if (!real_fn) {
        real_fn = dlsym(RTLD_NEXT, "drmModeGetConnectorCurrent");
    }
    drmModeConnectorPtr conn = real_fn(fd, connector_id);
    if (conn && (conn->connector_id == 33 || conn->connector_id == 64)) {
        conn->connection = 2; /* DRM_MODE_DISCONNECTED */
    }
    return conn;
}

typedef struct _drmEventContext {
    int version;
    void (*vblank_handler)(int fd, unsigned int sequence, unsigned int tv_sec, unsigned int tv_usec, void *user_data);
    void (*page_flip_handler)(int fd, unsigned int sequence, unsigned int tv_sec, unsigned int tv_usec, void *user_data);
    void (*page_flip_handler2)(int fd, unsigned int sequence, unsigned int tv_sec, unsigned int tv_usec, unsigned int crtc_id, void *user_data);
    void (*sequence_handler)(int fd, uint64_t sequence, uint64_t ns, uint64_t user_data);
} drmEventContext, *drmEventContextPtr;

static void (*orig_pf2)(int, unsigned int, unsigned int, unsigned int, unsigned int, void *) = NULL;
static void (*orig_pf)(int, unsigned int, unsigned int, unsigned int, void *) = NULL;

static void fixed_pf2(int fd, unsigned int seq, unsigned int tv_sec, unsigned int tv_usec, unsigned int crtc_id, void *user_data) {
    if (tv_sec == 0 && tv_usec == 0) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        tv_sec = (unsigned int)ts.tv_sec;
        tv_usec = (unsigned int)(ts.tv_nsec / 1000);
    }
    if (orig_pf2) orig_pf2(fd, seq, tv_sec, tv_usec, crtc_id, user_data);
}

static void fixed_pf(int fd, unsigned int seq, unsigned int tv_sec, unsigned int tv_usec, void *user_data) {
    if (tv_sec == 0 && tv_usec == 0) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        tv_sec = (unsigned int)ts.tv_sec;
        tv_usec = (unsigned int)(ts.tv_nsec / 1000);
    }
    if (orig_pf) orig_pf(fd, seq, tv_sec, tv_usec, user_data);
}

int drmHandleEvent(int fd, drmEventContextPtr evctx) {
    static int (*real_fn)(int, drmEventContextPtr) = NULL;
    if (!real_fn) {
        real_fn = dlsym(RTLD_NEXT, "drmHandleEvent");
    }
    if (evctx) {
        drmEventContext local_ctx = *evctx;
        if (evctx->page_flip_handler) {
            orig_pf = evctx->page_flip_handler;
            local_ctx.page_flip_handler = fixed_pf;
        }
        if (evctx->version >= 3 && evctx->page_flip_handler2) {
            orig_pf2 = evctx->page_flip_handler2;
            local_ctx.page_flip_handler2 = fixed_pf2;
        }
        return real_fn(fd, &local_ctx);
    }
    return real_fn(fd, evctx);
}
