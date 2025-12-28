#ifndef __DIFFTEST_HPP__
#define __DIFFTEST_HPP__

#define CONFIG_PC_RESET_OFFSET 0x0

#define PMEM_LEFT  ((paddr_t)CONFIG_FLASH_BASE)
#define PMEM_RIGHT ((paddr_t)CONFIG_FLASH_BASE + CONFIG_FLASH_SIZE - 1)
#define RESET_VECTOR (PMEM_LEFT + CONFIG_PC_RESET_OFFSET)

enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };

#define ANSI_BG_RED     "\33[1;41m"
#define ANSI_FG_GREEN   "\33[1;32m"
#define ANSI_NONE       "\33[0m"

#define ANSI_FMT(str, fmt) fmt str ANSI_NONE

#ifdef CONFIG_DIFFTEST
    extern "C" void    difftest_skip_ref(int);
#endif // CONFIG_DIFFTEST

extern bool is_skip_ref;
#endif // __DIFFTEST_HPP__
