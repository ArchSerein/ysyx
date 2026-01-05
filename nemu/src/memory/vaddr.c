/***************************************************************************************
 * Copyright (c) 2014-2022 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan
 *PSL v2. You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
 *KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 *NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

#include <fcntl.h>
#include <isa.h>
#include <memory/paddr.h>
#include <unistd.h>

static paddr_t vaddr2paddr(vaddr_t addr, int len, int mmu_type, int mem_type) {
#define OFFSET (12)
#define MASK ((1 << OFFSET) - 1)
#define PPNCONCATEOFFSET(pg, va) ((pg & (~MASK)) | (va & MASK))
  int mem_ret_type = MEM_RET_OK;
  switch (mmu_type) {
    case MMU_DIRECT:  return addr;
    case MMU_TRANSLATE:
      mem_ret_type = isa_mmu_translate(addr, len, mem_type);
    switch (mem_ret_type) {
      case MEM_RET_FAIL:
        panic("address translation failed at vaddr = " FMT_PADDR, addr);
        return 0;
      case MEM_RET_CROSS_PAGE:
        panic("unimplemented: cross page access at vaddr = " FMT_PADDR, addr);
        return 0;
      default:
        if (mem_ret_type == MEM_RET_OK)
          return PPNCONCATEOFFSET(mem_ret_type, addr);
        else
          panic("Unknown return value from isa_mmu_translate()");
      }
    case MMU_FAIL: panic("IFETCH address translation failed at vaddr = " FMT_PADDR, addr);
    default:
      panic("Unknown memory access type %d at vaddr = " FMT_PADDR, mmu_type, addr);
  }
}

// extern int mtrace_fd;
extern uint32_t inst_cnt;
word_t vaddr_ifetch(vaddr_t addr, int len) {
  // assert(write(mtrace_fd, &addr, sizeof(addr)) > 0);
  ++inst_cnt;
  int type = isa_mmu_check(addr, len, MEM_TYPE_IFETCH);
  paddr_t paddr = vaddr2paddr(addr, len, type, MEM_TYPE_IFETCH);
  return paddr_read(paddr, len);
}

word_t vaddr_read(vaddr_t addr, int len) {
  if (addr == 0x10000005) {
    return 32;
  }
  // assert(write(mtrace_fd, &addr, sizeof(addr)) > 0);
  int type = isa_mmu_check(addr, len, MEM_TYPE_READ);
  paddr_t paddr = vaddr2paddr(addr, len, type, MEM_TYPE_READ);
  return paddr_read(paddr, len);
}

void vaddr_write(vaddr_t addr, int len, word_t data) {
  // assert(write(mtrace_fd, &addr, sizeof(addr)) > 0);
  int type = isa_mmu_check(addr, len, MEM_TYPE_WRITE);
  paddr_t paddr = vaddr2paddr(addr, len, type, MEM_TYPE_WRITE);
  paddr_write(paddr, len, data);
}
