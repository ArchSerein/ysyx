/***************************************************************************************
* Copyright (c) 2014-2022 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>
#include <memory/vaddr.h>
#include <memory/paddr.h>

paddr_t isa_mmu_translate(vaddr_t vaddr, int len, int type) {
#define LEVELS  (2)
#define PAGEOFFSET (12)
#define PPNOFFSET (10)
#define IDXMASK (0x3ff)
#define PPNMASK ((0x001 << 22) - 1)
#define SHIFT(level) (PAGEOFFSET + (level) * 10)
#define IDX(level, va) (((uint32_t)va >> (SHIFT(level))) & IDXMASK)
#define PTESIZE (4)
#define PTE_V   (0x001 << 0)
#define PTE_R   (0x001 << 1)
#define PTE_W   (0x001 << 2)
#define PTE_X   (0x001 << 3)
#define PTE_A   (0x001 << 6)
#define PTE_D   (0x001 << 7)
  if (((vaddr & PAGE_MASK) + len) > PAGE_SIZE)
    return MEM_RET_CROSS_PAGE;
  uint32_t ppn = cpu.csr[SATP] & PPNMASK;
  for (int i = LEVELS-1; i >= 0; i--) {
    uint32_t a = (ppn << PAGEOFFSET) + IDX(i, vaddr) * PTESIZE;
    uint32_t pte = paddr_read(a,PTESIZE);
    if (!(pte & PTE_V) || ((pte & (PTE_R | PTE_W)) == PTE_W))
      return MEM_RET_FAIL;
    if (pte & (PTE_R | PTE_X)) {
      switch (type) {
        case MEM_TYPE_IFETCH:
          if (!(pte & PTE_X))
            return MEM_RET_FAIL;
          break;
        case MEM_TYPE_READ:
          if (!(pte & PTE_R))
            return MEM_RET_FAIL;
          break;
        case MEM_TYPE_WRITE:
          if (!(pte & PTE_W))
            return MEM_RET_FAIL;
          break;
      }
      assert(i == 0); // only 4KB page
      ppn = pte >> PPNOFFSET;
      return (ppn << PPNOFFSET) | MEM_RET_OK;
    } else {
      ppn = pte >> PPNOFFSET;
    }
  }
  return MEM_RET_FAIL;
}

int isa_mmu_check(vaddr_t vaddr, int len, int type) {
  if (cpu.csr[SATP] == 0) {
    return MMU_DIRECT;
  } else if (cpu.csr[SATP] & 0x80000000) {  // MODE = Sv32
    return MMU_TRANSLATE;
  } else {
    return MMU_FAIL;
  }
}
