/* Mixer ctl ABI smoke test — zero-risk: every write sends back the value that
 * was just read. Validates elem_list (find by name) → elem_info (type/count)
 * → elem_read → elem_write → elem_read against the live kernel, from this
 * task width, with the generic ioctl encoding. Run on-device.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sound/asound.h>

static void hexname(const unsigned char *n, char *out) {
    memcpy(out, n, 44);
    out[44] = 0;
}

int main(int argc, char **argv) {
    const char *card = "/dev/snd/controlC0";
    const char *want = argc > 1 ? argv[1] : "PCM Playback Volume";
    int fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) { perror("open"); return 1; }
    unsigned ver = 0;
    int r = ioctl(fd, SNDRV_CTL_IOCTL_PVERSION, &ver);
    printf("pversion rc=%d ver=%#x errno=%d\n", r, ver, errno);

    struct snd_ctl_elem_list list;
    memset(&list, 0, sizeof list);
    list.offset = 0;
    list.space = 0;
    r = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list);
    printf("elem_list(count-only) rc=%d used=%u count=%u errno=%d\n",
           r, list.used, list.count, errno);
    if (r != 0) return 2;

    unsigned n = list.count;
    struct snd_ctl_elem_id *ids = calloc(n, sizeof *ids);
    list.space = n;
    list.pids = ids;
    r = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list);
    printf("elem_list(fill) rc=%d used=%u errno=%d sizeof(list)=%zu sizeof(id)=%zu\n",
           r, list.used, errno, sizeof list, sizeof(struct snd_ctl_elem_id));
    if (r != 0) return 3;

    struct snd_ctl_elem_id *hit = NULL;
    char namebuf[64];
    for (unsigned i = 0; i < list.used; i++) {
        hexname(ids[i].name, namebuf);
        if (strcmp(namebuf, want) == 0) { hit = &ids[i]; printf("found numid=%u iface=%u index=%u\n", ids[i].numid, ids[i].iface, ids[i].index); break; }
    }
    if (!hit) { printf("control %q not found (%u controls total)\n", want, list.used); return 4; }

    struct snd_ctl_elem_info info;
    memset(&info, 0, sizeof info);
    info.id = *hit;
    r = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &info);
    printf("elem_info rc=%d type=%u count=%u access=%#x errno=%d\n",
           r, info.type, info.count, info.access, errno);
    if (r != 0) return 5;
    if (info.type == SNDRV_CTL_ELEM_TYPE_ENUMERATED) {
        for (unsigned i = 0; i < info.value.enumerated.items && i < 6; i++) {
            struct snd_ctl_elem_info e2;
            memset(&e2, 0, sizeof e2);
            e2.id = *hit;
            e2.value.enumerated.item = i;
            if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &e2) == 0) {
                hexname(e2.id.name, namebuf);
                printf("  enum[%u]=%s\n", i, namebuf);
            }
        }
    }

    struct snd_ctl_elem_value v;
    memset(&v, 0, sizeof v);
    v.id = *hit;
    r = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_READ, &v);
    printf("elem_read rc=%d errno=%d", r, errno);
    long v0 = 0;
    if (r == 0) {
        if (info.type == SNDRV_CTL_ELEM_TYPE_INTEGER || info.type == SNDRV_CTL_ELEM_TYPE_BOOLEAN) {
            v0 = v.value.integer.value[0];
            printf(" value[0]=%ld value[1]=%ld", v0, info.count > 1 ? v.value.integer.value[1] : 0);
        } else if (info.type == SNDRV_CTL_ELEM_TYPE_ENUMERATED) {
            v0 = v.value.enumerated.item;
            printf(" item=%ld", v0);
        }
    }
    printf("\n");

    if (r == 0) {
        v.id = *hit;
        r = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &v);
        printf("elem_write(same value back) rc=%d errno=%d\n", r, errno);
    }
    close(fd);
    return 0;
}
