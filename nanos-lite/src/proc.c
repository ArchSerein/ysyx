#include <proc.h>

#define MAX_NR_PROC 4

static PCB pcb[MAX_NR_PROC] __attribute__((used)) = {};
static PCB pcb_boot = {};
extern void naive_uload(PCB *pcb, const char *filename);
PCB *current = NULL;

void switch_boot_pcb() {
  current = &pcb_boot;
}

void hello_fun(void *arg) {
  int j = 1;
  while (1) {
    Log("Hello World from Nanos-lite with arg '%p' for the %dth time!", (uintptr_t)arg, j);
    j ++;
    yield();
  }
}

void init_proc() {
  char *envp[] = { NULL };
  char *argv_0[] = {"/bin/hello", NULL, NULL};
  char *argv_1[] = {"/bin/nterm", NULL, NULL};
  PCB *pcb = find_free_pcb();
  context_uload(pcb, "/bin/hello", argv_0, envp);
  pcb = find_free_pcb();
  context_uload(pcb, "/bin/nterm", argv_1, envp);
  // context_kload(&pcb[2], hello_fun, (void *)0x2);
  switch_boot_pcb();
  Log("Initializing processes...");
  yield();

  // const char filename[] = "/bin/nterm";
  // load program here
  // naive_uload(NULL, filename);
}

Context* schedule(Context *prev) {
  current->cp = prev;

  static int i = 0;
  int start_index = i;

  do {
    i = (i + 1) % MAX_NR_PROC;
    PCB *next = &pcb[i];

    if (next->cp != NULL) {
      current = next;
      return next->cp;
    }
  } while (i != start_index);

  return current->cp;
}

void context_kload(PCB *pcb, void *entry, void *arg) {
  Area stack = RANGE(pcb->stack, pcb->stack + STACK_SIZE);
  pcb->cp = kcontext(stack, entry, arg);
}

static uintptr_t setting(uintptr_t usp, uintptr_t sp, char *const argv[], char *const envp[]) {
  #define ALIGN(x, n) ((x) & (~(n)))
  uintptr_t envp_addr[64] = { 0 };
  uintptr_t argv_addr[64] = { 0 };
  int cnt = 3;
  if (envp != NULL) {
    for (int i = 0; envp[i] != NULL; i++) {
      size_t len = strlen(envp[i]) + 1;
      sp -= len;
      usp -= len;
      memcpy((void *)sp, envp[i], len);
      envp_addr[i] = usp;
      ++cnt;
    }
  }
  if (argv != NULL) {
    for (int i = 0; argv[i] != NULL; i++) {
      size_t len = strlen(argv[i]) + 1;
      sp -= len;
      usp -= len;
      memcpy((void *)sp, argv[i], len);
      argv_addr[i] = usp;
      ++cnt;
    }
  }
  uintptr_t base_unalign  = sp - cnt * sizeof(uintptr_t);
  uintptr_t base = ALIGN(base_unalign, 0xf);

  uintptr_t ubase_unalign = usp - cnt * sizeof(uintptr_t);
  uintptr_t ret  = base;

  base += sizeof(uintptr_t);
  // argv[i]
  for (cnt = 0; argv_addr[cnt] != 0; cnt++) {
    *(uint32_t *)base = argv_addr[cnt];
    base += sizeof(uintptr_t);
  }
  *((uint32_t *)(ret)) = cnt;  // argc
  *(uint32_t *)base = 0;
  base += sizeof(uintptr_t);
  //envp[i]
  for (int i = 0; envp_addr[i] != 0; i++) {
    *(uint32_t *)(base) = envp_addr[i];
    base += sizeof(uintptr_t);
  }
  *(uint32_t *)base = 0;
  base += sizeof(uintptr_t);
  // Unspecified
  memset((void *)base, 0, sp - base);
  return ALIGN(ubase_unalign, 0xf);
}

void context_uload(PCB *pcb, const char *filename, char *const argv[], char *const envp[]) {
  extern uintptr_t uload(PCB *pcb, const char *filename);
  #ifdef HAS_VME
  protect(&pcb->as);
  #endif
  uintptr_t entry = uload(pcb, filename);
  void *end = new_page(8);
  #ifdef HAS_VME
  #define RW_PORT (0x6)
  // map user stack
  uintptr_t ustart = (uintptr_t)pcb->as.area.end - STACK_SIZE;
  uintptr_t uend   = (uintptr_t)pcb->as.area.end;
  for (uintptr_t i = ustart; i < uend; i += PGSIZE) {
    map(&pcb->as, (void *)i, end, RW_PORT);
    end = (void *)((uintptr_t)end + PGSIZE);
  }
  #endif
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);
  uintptr_t sp = setting(uend, (uintptr_t)end, argv, envp);
  pcb->cp->GPRx = sp;
}

typedef struct PCB_List{
  PCB *pcb;
  struct PCB_List *next;
} LPCB;

static LPCB free_[MAX_NR_PROC];
static LPCB *list = &free_[0];
void init_pcb(void) {
  LPCB *p = list;
  for (int i = 1; i < MAX_NR_PROC; i++) {
    p->pcb = &pcb[i-1];
    p->next = &free_[i];
    p = p->next;
  }
  p->pcb = &pcb[MAX_NR_PROC];
  p->next = NULL;
  Log("Initializing free pcb list");
}

PCB *find_free_pcb() {
  if (list == NULL)
    return NULL;
  LPCB *p = list;
  list = p->next;
  return p->pcb;
}

void recycle_idle_pcb(PCB *pcb) {
  for (int i = 0; i < MAX_NR_PROC; i++) {
    if (free_[i].pcb == pcb) {
      pcb->cp = NULL; // mark as free, for schedule do not select it
      LPCB *p = &free_[i];
      p->next = list;
      list = p;
     }
  }
}
