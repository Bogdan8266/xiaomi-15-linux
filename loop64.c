#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <string.h>

#define LOOP_SET_FD 0x4C00
#define LOOP_SET_STATUS64 0x4C04
#define LOOP_CTL_ADD 0x4C80
#define LO_FLAGS_READ_ONLY 1

struct loop_info64 {
    uint64_t lo_device;
    uint64_t lo_inode;
    uint64_t lo_rdevice;
    uint64_t lo_offset;
    uint64_t lo_sizelimit;
    uint32_t lo_number;
    uint32_t lo_encrypt_type;
    uint32_t lo_encrypt_key_size;
    uint32_t lo_flags;
    uint8_t  lo_file_name[64];
    uint8_t  lo_crypt_name[64];
    uint8_t  lo_encrypt_key[32];
    uint64_t lo_init[2];
};

int main(int argc, char **argv) {
    int cfd = open("/dev/loop-control", O_RDWR);
    if (cfd >= 0) {
        ioctl(cfd, LOOP_CTL_ADD, 1);
        ioctl(cfd, LOOP_CTL_ADD, 2);
        ioctl(cfd, LOOP_CTL_ADD, 3);
        close(cfd);
    }
    int lfd = open(argv[1], O_RDONLY);
    int bfd = open(argv[2], O_RDONLY);
    printf("lfd=%d bfd=%d\n", lfd, bfd);
    uint64_t off = strtoull(argv[3], NULL, 0);
    if (ioctl(lfd, LOOP_SET_FD, bfd) < 0) { perror("LOOP_SET_FD"); return 1; }
    struct loop_info64 li;
    memset(&li, 0, sizeof(li));
    li.lo_offset = off;
    li.lo_flags = LO_FLAGS_READ_ONLY;
    if (ioctl(lfd, LOOP_SET_STATUS64, &li) < 0) { perror("LOOP_SET_STATUS64"); return 1; }
    printf("Attached %s to %s at offset %llu\n", argv[1], argv[2], (unsigned long long)off);
    return 0;
}
