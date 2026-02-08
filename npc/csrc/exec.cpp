#include <cstdint>
#include <cstring>
#include "state.hpp"
#include "defs.hpp"
#include "debug.hpp"
#include <iostream>
#include <nvboard.h>

#define MAX_INST_TO_PRINT 10

struct info {
    char name[16];
    uint32_t addr;
    uint32_t pc;
};

static bool g_print_step = true;
char buf[128];

inst_t cur_inst;
uint32_t func_stack_index = 0;
static struct info func_stack[128];
extern struct elf ftrace[128];


#ifdef CONFIG_ITRACE
void
trace(uint32_t pc, uint32_t inst)
{
    char str[64] = {};
    uint8_t code[4];
    // 将 uint32_t inst 使用 uint8_t 的数组转存
    for(int i = 0; i < 4; i++)
        code[i] = *((uint8_t *)&inst + i);
    
    disassemble(str, 64, (uint64_t)pc, code, 4);
    Log("%x:\t\t%02x %02x %02x %02x\t%s", pc, code[3], code[2],
        code[1], code[0], str);


    #ifdef CONFIG_FTRACE
      if (strstr(str, "jal")) {
        char *target_address = str + 8;
        char addr[16];
        for (int i = 0; i < 128; i++)
        {
          sprintf(addr, "0x%08x", ftrace[i].addr);
          if (strcmp(addr, target_address) == 0)
          {
            func_stack[func_stack_index].addr = ftrace[i].addr; // 记录当前函数的地址
            sprintf(func_stack[func_stack_index].name, "%s", ftrace[i].name); // 记录当前函数的名字
            func_stack[func_stack_index].pc = pc;
            func_stack_index++;
            break;
          }
        }
      } 
      if(strstr(str, "jalr")) {
        // 通过 inst 分析出 jalr 的目标地址
        // jalr 是 I-type 指令，所以目标地址是高12位的立即数加上 rs1 的值
        // rs1 是 inst 的 15-19 位
        int reg_index = (inst & 0x0007f000) >> 15;
        uint32_t target_address = (inst >> 20) + get_reg_val(reg_index);
        if (reg_index == 1)
        {
          for (int i = 0; i < func_stack_index; i++)
          {
            if (func_stack[i].pc == target_address - 4)
            {
              func_stack[func_stack_index].addr = 0; // 函数函数的地址位0
              sprintf(func_stack[func_stack_index].name, "%s", func_stack[i].name); // 记录当前函数的名字
              func_stack[func_stack_index].pc = pc;
              func_stack_index++;
              break;
            }
          }
        } else {
          for (int i = 0; i < 128; i++)
          {
            if (ftrace[i].addr == target_address)
            {
              func_stack[func_stack_index].addr = ftrace[i].addr; // 记录当前函数的地址
              sprintf(func_stack[func_stack_index].name, "%s", ftrace[i].name); // 记录当前函数的名字
              func_stack_index++;
              func_stack[func_stack_index].pc = pc;
              break;
            }
          }
        }
      }
    #endif // CONFIG_FTRACE
}
#endif // CONFIG_ITRACE

void
execute(uint64_t n)
{
for (int i = 0; i < n; i++) {
    if (npc_state.state != RUNNING) {
        break;
    }

    nvboard_update();
    single_cycle(&cur_inst);
    #ifdef CONFIG_TRACE_PERFORMANCE
      cycle_count();
    #endif // CONFIG_TRACE_PERFORMANCE

    #ifdef CONFIG_DIFFTEST
      extern uint32_t difftest_pc;
      if (is_difftest_cycle()) {
        difftest_step(difftest_pc);
        set_difftest_time();
      }
    #endif // CONFIG_DIFFTEST

    if (g_print_step) {
      #ifdef CONFIG_ITRACE
        trace(cur_inst.pc, cur_inst.inst);
      #endif
    }

    #ifdef CONFIG_WATCHPOINT
    extern int config_watchpoint();
    if (config_watchpoint() == 1) {
        npc_state.state = QUIT;
    }
    #endif // CONFIG_WATCHPOINT
  }
}
    
void
exec(uint64_t n)
{
    g_print_step = (n < MAX_INST_TO_PRINT);
     switch (npc_state.state) {
       case END: case ABORT:
         printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
         return;
       default: npc_state.state = RUNNING;
     }

    execute(n);

    switch (npc_state.state) {
        case RUNNING: npc_state.state = STOP; break;        
        case ABORT:
        case END:
            is_exit_state(npc_state.halt_ret);
          // fall through
        case QUIT: break;// statistic();
  }
}

int 
is_exit_status_bad() {
  int good = (npc_state.state == END && npc_state.halt_ret == 0) ||
    (npc_state.state == QUIT);
  return !good;
}

#ifdef CONFIG_FTRACE
void
print_func_stack()
{
  int nested = 0;
  for (int i = 0; i < func_stack_index; i++)
  {
    if (func_stack[i].addr == 0)
    {
      nested--;
      printf("pc:%08x:\t", func_stack[i].pc);
      for(int j = 0; j < nested; j++)
        printf("\t");

      printf("ret\t[%s]\n", func_stack[i].name);
    } else {
      printf("pc:%08x:\t", func_stack[i].pc);
      for(int j = 0; j < nested; j++)
        printf("\t");
      printf("call\t[%s@%08x]\n", func_stack[i].name, func_stack[i].addr);
      nested++;
    }
  }
}
#endif // CONFIG_FTRACE
