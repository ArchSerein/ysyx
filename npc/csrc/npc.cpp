#include "VysyxSoCFull.h"
#include "VysyxSoCFull___024root.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "state.hpp"
#include "defs.hpp"
#include "reg.hpp"
#include "debug.hpp"
#include <cstdio>
#include <nvboard.h>

static TOP_NAME top;
#ifdef CONFIG_TRACE_WAVE
    VerilatedContext* contextp = NULL;
    VerilatedVcdC* tfp = NULL;
#endif // CONFIG_TRACE_WAVE

uint32_t deu_inst;
uint32_t register_file[37];
int e = 0;
int64_t inst_cnt = 0;
int64_t cycle_cnt = 0;
int64_t ifu_inst_cnt = 0;
int64_t lsu_load_cnt = 0;
int64_t exu_alu_cnt = 0;
int64_t cal_inst_cnt = 0;
int64_t mem_inst_cnt = 0;
int64_t csr_inst_cnt = 0;
int64_t br_inst_cnt = 0;
int64_t jump_inst_cnt = 0;
int64_t default_inst_cnt = 0;
int64_t mem_cycle_cnt = 0;
int64_t hit_counter = 0;
int64_t miss_cnt = 0;
int64_t penalty_cnt = 0;
int64_t total_inst_cnt = 0;
int64_t stall_cnt = 0;
int64_t dcache_hit_cnt = 0;
int64_t dcache_miss_cnt = 0;
int64_t dcache_penalty_cnt = 0;
int64_t dcache_req_cnt = 0;

extern "C" void ending(int num) { e = num; }
extern "C" void putch(int ch) { putchar(ch); }
static void update_register_array();

#ifdef CONFIG_TRACE_WAVE
bool is_open_trace_wave = false;
void open_trace_wave(uint32_t pc) {
    if (!is_open_trace_wave && pc == 0xa0018180) {
        is_open_trace_wave = true;
        Log("open trace wave");
    }
}
void close_trace_wave(uint32_t pc) {
    // if (is_open_trace_wave && ()) {
    //     is_open_trace_wave = false;
    //     Log("close trace wave");
    // }
}
#endif // CONFIG_TRACE_WAVE
    
void
single_cycle(inst_i *cur_inst) {
    if (e)
    {
      if (e == 2) {
        Log("The NPC's status does not advance forward.");
        isa_reg_display();
        npc_state.halt_ret = 1;
        npc_state.state = ABORT;
      } else {
        if (get_reg_val(10) == 0)
        {
            npc_state.halt_ret = 0;
            npc_state.state = END;
        }

        else
        {
            npc_state.halt_ret = 1;
            npc_state.state = ABORT;
        }
      }
    }

    if (cur_inst != NULL)
    {
        cur_inst->pc = get_pc_reg();
        cur_inst->inst = get_inst_reg();
    }
    #ifdef CONFIG_TRACE_WAVE
        if (cur_inst != NULL) {
            open_trace_wave(get_pc_reg());
            close_trace_wave(get_pc_reg());
        }
    #endif // CONFIG_TRACE_WAVE
    top.clock = 0; // 切换时钟状态
    top.eval();
    #ifdef CONFIG_TRACE_WAVE
        if (is_open_trace_wave) {
            contextp->timeInc(1);
            tfp->dump(contextp->time());
        }
    #endif // CONFIG_TRACE_WAVE
    top.clock = 1; // 切换
    top.eval();
    #ifdef CONFIG_TRACE_WAVE
        if (is_open_trace_wave) {
            contextp->timeInc(1);
            tfp->dump(contextp->time());
        }
    #endif // CONFIG_TRACE_WAVE
    update_register_array();
}

void
reset(int n) {
    top.reset = 1;
    while (n-- > 0)
    {
        single_cycle(0);
    }
    top.reset = 0;
}

void
sim_exit(){
    single_cycle(0);
    #ifdef CONFIG_TRACE_WAVE
        tfp->close();
    #endif // CONFIG_TRACE_WAVE
    #ifdef CONFIG_TRACE_PERFORMANCE
        char path[] = "/home/serein/ysyx/ysyx-workbench/npc/performance.txt";
        FILE *fp = fopen(path, "w");
        if (fp == NULL) {
            Log("open file performance.txt failed");
            return;
        }
        fprintf(fp, "Cycle: %ld Instructions: %ld, IPC: %.04f", cycle_cnt, inst_cnt, (double)inst_cnt / cycle_cnt);
        fprintf(fp, "IFU Instructions: %ld, LSU Load/Store Instructions: %ld, EXU ALU Instructions: %ld", ifu_inst_cnt, lsu_load_cnt, exu_alu_cnt);
        fprintf(fp, "CAL Instructions: %ld, MEM Instructions: %ld, CSR Instructions: %ld, BR Instructions: %ld, JUMP Instructions: %ld, DEFAULT Instructions: %ld", cal_inst_cnt, mem_inst_cnt, csr_inst_cnt, br_inst_cnt, jump_inst_cnt, default_inst_cnt);
        double total_inst = (double)total_inst_cnt;
        fprintf(fp, "CAL Instructions Ratio: %.04f", cal_inst_cnt / total_inst);
        fprintf(fp, "MEM Instructions Ratio: %.04f", mem_inst_cnt / total_inst);
        fprintf(fp, "CSR Instructions Ratio: %.04f", csr_inst_cnt / total_inst);
        fprintf(fp, "BR Instructions Ratio: %.04f", br_inst_cnt / total_inst);
        fprintf(fp, "JUMP Instructions Ratio: %.04f", jump_inst_cnt / total_inst);
        fprintf(fp, "DEFAULT Instructions Ratio: %.04f", default_inst_cnt / total_inst);
        fprintf(fp, "Memory Access Cycle: %ld, average memory access cycle: %.04f", mem_cycle_cnt, (double)mem_cycle_cnt / lsu_load_cnt);
        fprintf(fp, "icache hit Ratio: %.04f", (double)hit_counter / ifu_inst_cnt);
        fprintf(fp, "Icache Average Memory Access Time: %.04f", (1 - (double)hit_counter / ifu_inst_cnt) * (double)penalty_cnt / miss_cnt + 1);
        fprintf(fp, "dcache hit Ratio: %.04f", (double)dcache_hit_cnt / dcache_req_cnt);
        fprintf(fp, "Dcache Average Memory Access Time: %.04f", (1 - (double)dcache_hit_cnt / dcache_req_cnt) * (double)dcache_penalty_cnt / dcache_miss_cnt + 1);
        fprintf(fp, "综合面积: 29033.900000um^2, 频率: 700MHz");
        fclose(fp);
        printf("hit: %ld, miss: %ld\n", hit_counter, miss_cnt);
        Log("not stall ipc: %.04f", (double)inst_cnt / (cycle_cnt - stall_cnt));
    #endif // CONFIG_TRACE_PERFORMANCE
}

#ifdef CONFIG_TRACE_WAVE
void 
sim_init()
{
    Verilated::traceEverOn(true);
    contextp = new VerilatedContext;
    tfp = new VerilatedVcdC;
    contextp->traceEverOn(true);
    top.trace(tfp, 0);
    tfp->open("VysyxSoCFull.vcd");
}
#endif // CONFIG_TRACE_WAVE

void
isa_reg_display()
{
    for(int i = 0; i < 37; i++)
    {
        printf("%s: %08x\n", regs[i], 
            register_file[i]);
    }
}

static void
update_register_array()
{
    for(int i = 0; i < 32; i++)
    {
        register_file[i] = get_reg_val(i);
    }

    register_file[32] = get_pc_reg();
    register_file[33] = get_csr_val(0x341);
    register_file[34] = get_csr_val(0x300);
    register_file[35] = get_csr_val(0x305);
    register_file[36] = get_csr_val(0x342);
}

uint32_t
isa_reg_str2val(const char *s) {
  const char *reg_name = s + 1;
  for(int i = 0; i < 32; i++)
  {
    if(strcmp(reg_name, regs[i]) == 0)
    {
      return get_reg_val(i);
    }
  }

  if(strcmp(reg_name, "pc") == 0)
  {
    return get_pc_reg();
  }
  return 0;
}

#ifdef CONFIG_DIFFTEST
bool    is_difftest_time = false;
uint32_t difftest_pc = 0;
extern  bool is_skip_ref;
extern  bool is_raise_intr;
extern  uint32_t  no;
extern "C" void is_difftest(char difftest, int pc, char skip){
    is_difftest_time = difftest == 1;
    is_skip_ref = skip & 0x80;
    is_raise_intr = skip & 0x40;
    no = skip & 0x3f;
    difftest_pc = (uint32_t)pc;
}
bool is_difftest_cycle() {
    return is_difftest_time;
}

void set_difftest_time() {
  is_difftest_time = false;
}
#endif

uint32_t get_pc_reg() {
    return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_ifu_module__DOT__ifu_pc;
}

uint32_t get_inst_reg() {
    return deu_inst;
}

uint32_t get_reg_val(int index) {
    return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_regfile_module__DOT__regfile[index];
}

uint32_t get_csr_val(int addr) {
    switch (addr) {
        case 0x300:
        return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_csr_module__DOT__MSTATUS;
        case 0x342:
          return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_csr_module__DOT__MCAUSE;
        case 0x305:
          return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_csr_module__DOT__MTVEC;
        case 0x341:
          return top.rootp->ysyxSoCFull__DOT__asic__DOT__cpu__DOT__cpu__DOT__core_module__DOT__ysyx_25030067_csr_module__DOT__MEPC;
        default:
            panic("get_csr_val fault addr: %x", addr);
    }
}

void nvboard_bind_all_pins(TOP_NAME *top);
void nvboard_init_warp() {
    nvboard_bind_all_pins(&top);
    nvboard_init();
}

#ifdef CONFIG_TRACE_PERFORMANCE
extern "C" void inst_count(void) {
    ++inst_cnt;
}

extern "C" void ifu_inst_count() {
    ++ifu_inst_cnt;
}

extern "C" void inst_type_count(uint8_t type) {
    switch (type) {
        case 0:
            ++cal_inst_cnt;
            break;
        case 1:
            ++mem_inst_cnt;
            break;
        case 2:
            ++csr_inst_cnt;
            break;
        case 3:
            ++br_inst_cnt;
            break;
        case 4:
            ++jump_inst_cnt;
            break;
        default:
            ++default_inst_cnt;
            break;
    }
}

extern "C" void lsu_load_store_count(void) {
    ++lsu_load_cnt;
}

extern "C" void exu_alu_count(void) {
    ++exu_alu_cnt;
}

extern "C" void mem_cycle_count(void) {
    ++mem_cycle_cnt;
}
extern "C" void hit_cnt(void) {
  ++hit_counter;
}
extern "C" void miss_count() {
  ++miss_cnt;
}
extern "C" void penalty_count() {
  ++penalty_cnt;
}
void cycle_count(void) {
  ++cycle_cnt;
}
extern "C" void total_inst_count() {
  ++total_inst_cnt;
}
extern "C" void stall_count() {
  ++stall_cnt;
}
extern "C" void dcache_hit_count() {
  ++dcache_hit_cnt;
}
extern "C" void dcache_miss_count() {
  ++dcache_miss_cnt;
}
extern "C" void dcache_penalty_count() {
  ++dcache_penalty_cnt;
}
extern "C" void dcache_req_count() {
  ++dcache_req_cnt;
}
#endif // CONFIG_TRACE_PERFORMANCE

extern "C" void get_inst(uint32_t inst) {
  deu_inst = inst;
}
