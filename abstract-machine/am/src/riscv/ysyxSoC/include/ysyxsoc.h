#ifndef YSYXSOC_H__
#define YSYXSOC_H__

#include <klib-macros.h>

#include ISA_H // the macro `ISA_H` is defined in CFLAGS
               // it will be expanded as "x86/x86.h", "mips/mips32.h", ...

/*
extern char _pmem_start;
#define PMEM_SIZE (128 * 1024 * 1024)
#define PMEM_END  ((uintptr_t)&_pmem_start + PMEM_SIZE)
#define NEMU_PADDR_SPACE \
  RANGE(&_pmem_start, PMEM_END), \
  RANGE(FB_ADDR, FB_ADDR + 0x200000), \
  RANGE(AUDIO_SBUF_ADDR, AUDIO_SBUF_ADDR + 0x10000), \
  RANGE(MMIO_BASE, MMIO_BASE + 0x1000)
*/

typedef uintptr_t PTE;

#define PGSIZE    4096

#endif // YSYXSOC_H__
