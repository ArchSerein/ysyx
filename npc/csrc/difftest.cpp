#include <dlfcn.h>
#include <cstdint>
#include <cassert>
#include <cstdio>
#include <cstring>
#include "pmem.hpp"
#include "difftest.hpp"
#include "debug.hpp"
#include "state.hpp"
#include "defs.hpp"
#include "reg.hpp"

#ifdef CONFIG_DIFFTEST

bool is_skip_ref = false;
bool is_raise_intr = false;
uint32_t no = 0x0;

extern uint32_t register_file[37];

static bool isa_difftest_checkregs(uint32_t *ref, vaddr_t pc, vaddr_t ref_pc)
{
    int i;
    for (i = 0; i < 37; i++) {
        if (register_file[i] != ref[i] && i != 32) {
            goto bad;
        }
    }
    if (pc != ref_pc) {
        i = 32;
        goto bad;
    }
    return true;

bad: 
    Log("Different value at pc = " ANSI_FMT("%08x", ANSI_BG_RED) ", "
              "dut %s = " ANSI_FMT("%08x", ANSI_BG_RED) ", "
              "ref %s = " ANSI_FMT("%08x", ANSI_BG_RED),
              pc, regs[i], register_file[i], regs[i], ref[i]);
    return false;
}

void (*ref_difftest_memcpy)(paddr_t addr, void *buf, size_t n, bool direction) = NULL;
void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
void (*ref_difftest_exec)(uint64_t n) = NULL;
void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;

void
init_difftest(const char *ref_so_file, long img_size, int port)
{
    assert(ref_so_file != NULL);
    assert(img_size > 0);
    
    void *handle = dlopen(ref_so_file, RTLD_LAZY);
    assert(handle != NULL);

    ref_difftest_memcpy = (void (*)(paddr_t, void *, size_t, bool))dlsym(handle, "difftest_memcpy");
    assert(ref_difftest_memcpy != NULL);

    ref_difftest_regcpy = (void (*)(void *, bool))dlsym(handle, "difftest_regcpy");
    assert(ref_difftest_regcpy != NULL);

    ref_difftest_exec = (void (*)(uint64_t))dlsym(handle, "difftest_exec");
    assert(ref_difftest_exec != NULL);

    ref_difftest_raise_intr = (void (*)(uint64_t))dlsym(handle, "difftest_raise_intr");
    assert(ref_difftest_raise_intr != NULL);

    void (*ref_difftest_init)(int) = (void (*)(int))dlsym(handle, "difftest_init");
    assert(ref_difftest_init != NULL);

    ref_difftest_init(port);
    ref_difftest_memcpy(RESET_VECTOR, flash_to_host(RESET_VECTOR-PMEM_LEFT), img_size, DIFFTEST_TO_REF);
    // init pc value
    register_file[32] = 0x30000000;
    ref_difftest_regcpy(register_file, DIFFTEST_TO_REF);

    Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
    Log("The result of every instruction will be compared with %s. "
      "This will help you a lot for debugging, but also significantly reduce the performance. "
      "If it is not necessary, you can turn it off in menuconfig.", ref_so_file);
}

static void checkregs(uint32_t *ref, vaddr_t pc, vaddr_t ref_pc) {
  if (!isa_difftest_checkregs(ref, pc, ref_pc)) {
    npc_state.state = ABORT;
    npc_state.halt_pc = pc;
    isa_reg_display();
  }
}

void difftest_skip_ref_exec();
void
difftest_step(vaddr_t pc)
{
    uint32_t ref_r[37];
    if (is_skip_ref) {
        ref_difftest_regcpy(ref_r, DIFFTEST_TO_DUT);
        uint32_t ref_pc = ref_r[32];
        memcpy(ref_r, register_file, sizeof(ref_r));
        ref_r[32] = ref_pc + 4;
        ref_difftest_regcpy(ref_r ,DIFFTEST_TO_REF); 
        is_skip_ref = false;
        return;
    } else if (is_raise_intr) {
        ref_difftest_raise_intr(no);
        ref_difftest_regcpy(ref_r, DIFFTEST_TO_DUT);
        uint32_t cur_ref_pc = ref_r[32];
        return;
    }
    ref_difftest_regcpy(ref_r, DIFFTEST_TO_DUT);
    uint32_t cur_ref_pc = ref_r[32];
    ref_difftest_exec(1);
    ref_difftest_regcpy(ref_r, DIFFTEST_TO_DUT);
    // Log("dut: ref pc 0x%08x dut pc 0x%08x", cur_ref_pc, pc);

    checkregs(ref_r, pc, cur_ref_pc);
}

extern "C" void difftest_skip_ref(int is_skip) {
    // Log("Skip the reference current instruction");

    // Skip the current instruction in the reference(nemu)
    is_skip_ref = (is_skip == 1);
}

#endif // CONFIG_DIFFTEST
