#include <am.h>
#include <nemu.h>
#include <klib.h>

static AddrSpace kas = {};
static void* (*pgalloc_usr)(int) = NULL;
static void (*pgfree_usr)(void*) = NULL;
static int vme_enable = 0;

static Area segments[] = {      // Kernel memory mappings
  NEMU_PADDR_SPACE
};

#define USER_SPACE RANGE(0x40000000, 0x80000000)

static inline void set_satp(void *pdir) {
  uintptr_t mode = 1ul << (__riscv_xlen - 1);
  asm volatile("csrw satp, %0" : : "r"(mode | ((uintptr_t)pdir >> 12)));
}

static inline uintptr_t get_satp() {
  uintptr_t satp;
  asm volatile("csrr %0, satp" : "=r"(satp));
  return satp << 12;
}

bool vme_init(void* (*pgalloc_f)(int), void (*pgfree_f)(void*)) {
  pgalloc_usr = pgalloc_f;
  pgfree_usr = pgfree_f;

  kas.ptr = pgalloc_f(PGSIZE);

  int i;
  for (i = 0; i < LENGTH(segments); i ++) {
    void *va = segments[i].start;
    for (; va < segments[i].end; va += PGSIZE) {
      map(&kas, va, va, 0);
    }
  }

  set_satp(kas.ptr);
  vme_enable = 1;

  return true;
}

void protect(AddrSpace *as) {
  PTE *updir = (PTE*)(pgalloc_usr(PGSIZE));
  as->ptr = updir;
  as->area = USER_SPACE;
  as->pgsize = PGSIZE;
  // map kernel space
  memcpy(updir, kas.ptr, PGSIZE);
}

void unprotect(AddrSpace *as) {
}

void __am_get_cur_as(Context *c) {
  c->pdir = (vme_enable ? (void *)get_satp() : NULL);
}

void __am_switch(Context *c) {
  if (vme_enable && c->pdir != NULL) {
    set_satp(c->pdir);
  }
}

void map(AddrSpace *as, void *va, void *pa, int prot) {
  #define PAGEOFFSET (12)
  #define PPNOFFSET (10)
  #define IDXMASK (0x3ff)
  #define SHIFT(level) (PAGEOFFSET + (level) * 10)
  #define IDX(level, va) (((uint32_t)va >> (SHIFT(level))) & IDXMASK)
  #define PTE2PA(pte) ((uint32_t)(pte) >> PPNOFFSET << PAGEOFFSET)
  #define PA2PTE(pa) (((uint32_t)(pa) >> PAGEOFFSET) << PPNOFFSET)
  if (((uintptr_t)pa & (PGSIZE - 1)) || ((uintptr_t)va & (PGSIZE - 1))) {
    panic("map address not aligned to page size");
  }
  PTE *pte;
  PTE *updir = (PTE *)as->ptr;
  pte = &updir[IDX(1, va)];
  if (!(*pte & PTE_V)) {
    void *p = pgalloc_usr(PGSIZE);
    memset(p, 0, PGSIZE);
    *pte = PA2PTE(p) | PTE_V;
    updir = (PTE *)PTE2PA(*pte);
  } else {
    updir = (PTE *)PTE2PA(*pte);
  }
  pte = &updir[IDX(0, va)];
  if (pte == NULL)
    panic("pte is null");
  if (*pte & PTE_V)
    panic("remap a mapped virtual address");
  *pte = PA2PTE(pa) | PTE_V | prot;
}

Context *ucontext(AddrSpace *as, Area kstack, void *entry) {
  Context *c = (Context *)kstack.end - 1;
  c->mepc = (uintptr_t)entry;
  c->mstatus = 0x1800;
  return c;
}
