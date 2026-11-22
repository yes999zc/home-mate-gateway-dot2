/* Print the exact SNDRV_CTL ioctl request codes and struct sizes from THIS
 * toolchain's kernel headers — the authoritative ABI numbers for mixer.rs,
 * generated per-arch inside the pinned NDK container (never from memory). */
#include <stdio.h>
#include <sys/ioctl.h>
#include <sound/asound.h>

#define P(x) printf("%-28s %#lx\n", #x, (unsigned long)(x))

int main(void) {
    printf("sizeof(snd_ctl_elem_list)  = %zu\n", sizeof(struct snd_ctl_elem_list));
    printf("sizeof(snd_ctl_elem_id)    = %zu\n", sizeof(struct snd_ctl_elem_id));
    printf("sizeof(snd_ctl_elem_info)  = %zu\n", sizeof(struct snd_ctl_elem_info));
    printf("sizeof(snd_ctl_elem_value) = %zu\n", sizeof(struct snd_ctl_elem_value));
    printf("offsetof elem_list.pids    = %zu\n", (size_t)__builtin_offsetof(struct snd_ctl_elem_list, pids));
    printf("offsetof elem_info.value   = %zu\n", (size_t)__builtin_offsetof(struct snd_ctl_elem_info, value));
    printf("offsetof elem_value.value  = %zu\n", (size_t)__builtin_offsetof(struct snd_ctl_elem_value, value));
    P(SNDRV_CTL_IOCTL_ELEM_LIST);
    P(SNDRV_CTL_IOCTL_ELEM_INFO);
    P(SNDRV_CTL_IOCTL_ELEM_READ);
    P(SNDRV_CTL_IOCTL_ELEM_WRITE);
    P(SNDRV_CTL_IOCTL_PVERSION);
    return 0;
}
