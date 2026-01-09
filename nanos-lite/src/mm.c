#include <memory.h>
#include <proc.h>

static void *pf = NULL;

void* new_page(size_t nr_page) {
  void *ret = pf;
  pf = (void *)((uintptr_t)(pf) + nr_page * PGSIZE);
  return ret;
}

#ifdef HAS_VME
static void* pg_alloc(int n) {
  void *ret = new_page(n / PGSIZE);
  memset(ret, 0, n);
  return ret;
}
#endif

void free_page(void *p) {
  panic("not implement yet");
}

/* The brk() system call handler. */
int mm_brk(uintptr_t brk) {
  #ifdef HAS_VME
  #define ROUNDUP(a, sz)   ((((uintptr_t)a) + (sz) - 1) & ~((sz) - 1))
  #define RW_PORT (0x6)
  uintptr_t new_brk = ROUNDUP(brk, PGSIZE);
  uintptr_t old_brk = current->max_brk;
  if (new_brk > old_brk) {
    int nr_page = (new_brk - old_brk) / PGSIZE;
    for (int i = 0; i < nr_page; i++) {
      void *page  = pg_alloc(PGSIZE);
      void *vaddr = (void *)(old_brk + i * PGSIZE);
      map(&current->as, vaddr, page, RW_PORT);
    }
    current->max_brk = new_brk;
  }
  #endif
  return 0;
}

void init_mm() {
  pf = (void *)ROUNDUP(heap.start, PGSIZE);
  Log("free physical pages starting from %p", pf);

#ifdef HAS_VME
  vme_init(pg_alloc, free_page);
#endif
}
