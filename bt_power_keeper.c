#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define BT_CMD_PWR_CTRL 0xbfad

int main(void) {
    int fd = open("/dev/btpower", O_RDWR);
    if (fd < 0) {
        perror("open /dev/btpower");
        return 1;
    }
    int res = ioctl(fd, BT_CMD_PWR_CTRL, 1);
    printf("BT_CMD_PWR_CTRL 1 returned: %d\n", res);
    fflush(stdout);
    while (1) {
        sleep(3600);
    }
    return 0;
}
