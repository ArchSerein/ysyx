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
  // context_uload(&pcb[0], "/bin/hello", NULL, NULL);
  context_uload(&pcb[0], "/bin/pal", NULL, NULL);
  context_kload(&pcb[1], hello_fun, (void *)0x2);
  switch_boot_pcb();
  yield();

  Log("Initializing processes...");

  const char filename[] = "/bin/nterm";
  // load program here
  naive_uload(NULL, filename);
}

Context* schedule(Context *prev) {
  static int i = 0;
  current->cp = prev;
  for ( ; i < MAX_NR_PROC; ) {
    PCB *next = &pcb[i];
    i = (i + 1) % MAX_NR_PROC;
    if (next->cp != NULL && next->cp != prev) {
      current = next;
      return next->cp;
    }
  }
  return current->cp;
}

void context_kload(PCB *pcb, void *entry, void *arg) {
  Area stack = RANGE(pcb->stack, pcb->stack + STACK_SIZE);
  pcb->cp = kcontext(stack, entry, arg);
}

void context_uload(PCB *pcb, const char *filename, char *const argv[], char *const envp[]) {
  extern uintptr_t uload(PCB *pcb, const char *filename);
  uintptr_t entry = uload(pcb, filename);
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);
  pcb->cp->GPRx = (uintptr_t)heap.end;
}
