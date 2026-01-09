#include <common.h>
#include <proc.h>
#include "syscall.h"
#include <sys/time.h>

static int
sys_gettimeofday(void *tv, void *tz) {
  struct timeval *tp = (struct timeval *)tv;
  uint64_t us = io_read(AM_TIMER_UPTIME).us;
  tp->tv_sec = us / 1000000;
  tp->tv_usec = us % 1000000;
 
  if (tz != NULL) {
    // panic("todo: implement gettimeofday");
  }
  return 0;
}

extern int fs_open(const char *pathname, int flags, int mode);
extern size_t fs_read(int fd, void *buf, size_t len);
extern size_t fs_write(int fd, const void *buf, size_t len);
extern int fs_close(int fd);
extern size_t fs_lseek(int fd, size_t offset, int whence);

static int
sys_execve(const char *pathname, char *const argv[], char *const envp[]) {
  // extern void naive_uload(PCB *pcb, const char *filename);
  // naive_uload(NULL, pathname);
  extern void switch_boot_pcb();
  if (fs_open(pathname, 0, 0) < 0)
    return -2;
  PCB *pcb = find_free_pcb();
  context_uload(pcb, pathname, argv, envp);
  pcb = current;
  switch_boot_pcb();
  recycle_idle_pcb(pcb);
  yield();
  return 0;
}
static int sys_brk(uintptr_t brk) {
  extern int mm_brk(uintptr_t brk);
  int ret = mm_brk(brk);
  #ifdef CONFIG_STRACE
    printf("SYS_brk called: ret value=%d, new_brk: 0x%08x\n", ret, brk);
  #endif // !CONFIG_STRACE
  return ret;
}
void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1;
  char *empty[] = { NULL };

  switch (a[0]) {
    case SYS_exit:
                  halt(c->GPRx);
                  #ifdef CONFIG_STRACE
                    printf("SYS_exit called\n");
                  #endif // !CONFIG_STRACE
                  sys_execve("/bin/nterm", empty, empty);
                  break;
    case SYS_yield:
                  #ifdef CONFIG_STRACE
                    printf("sys_yield called\n");
                  #endif // !CONFIG_STRACE
                  yield();
                  c->GPRx = 0;
                  break;
    case SYS_write:
                  c->GPRx = fs_write(c->GPR2, (void *)c->GPR3, c->GPR4);
                  break;
    case SYS_brk:
                  c->GPRx = sys_brk(c->GPR2);
                  break;
    case SYS_open:
                  c->GPRx = fs_open((char *)c->GPR2, c->GPR3, c->GPR4);
                  break;
    case SYS_read:
                  c->GPRx = fs_read(c->GPR2, (void *)c->GPR3, c->GPR4);
                  break;
    case SYS_close:
                  c->GPRx = 0;
                  break;
    case SYS_lseek:
                  c->GPRx = fs_lseek(c->GPR2, c->GPR3, c->GPR4);
                  break;
    case SYS_gettimeofday:
                  #ifdef CONFIG_STRACE
                    printf("SYS_gettimeofday called: tv=%p, tz=%p, ", (void *)c->GPR2, (void *)c->GPR3);
                  #endif // !CONFIG_STRACE
                  c->GPRx = sys_gettimeofday((void *)c->GPR2, (void *)c->GPR3);
                  #ifdef CONFIG_STRACE
                    printf("ret value=%d\n", c->GPRx);
                  #endif // !CONFIG_STRACE
                  break;
    case SYS_execve:
                  #ifdef CONFIG_STRACE
                    printf("SYS_execve called: pathname=%s\n", (const char *)c->GPR2);
                  #endif // !CONFIG_STRACE
                  c->GPRx = sys_execve((const char *)c->GPR2, (char **)(c->GPR3), NULL);
                  break;
    default: panic("Unhandled syscall ID = %d", a[0]);
  }
}
