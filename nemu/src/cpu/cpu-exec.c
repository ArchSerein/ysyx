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

#include <cpu/cpu.h>
#include <cpu/decode.h>
#include <cpu/difftest.h>
#include <locale.h>
#include <regex.h>

/* The assembly code of instructions executed is only output to the screen
 * when the number of instructions executed is less than this value.
 * This is useful when you use the `si' command.
 * You can modify this value as you want.
 */
#define MAX_INST_TO_PRINT 10

CPU_state cpu = {};
uint64_t g_nr_guest_inst = 0;
static uint64_t g_timer = 0; // unit: us
static bool g_print_step = false;
#ifdef CONFIG_ITRACE
static int iringbufindex = 0;
static char iringbuf[iringlength][128];
#endif // CONFIG_ITRACE
#ifdef CONFIG_FTRACE
  extern struct elf ftrace[128];
  static struct info func_stack[512] = {};
  static int ftraceindex = 0;
  void print_func_stack();
#endif

void isa_exec_err_display();
void device_update();

static void trace_and_difftest(Decode *_this, vaddr_t dnpc) {
#ifdef CONFIG_ITRACE_COND
  if (ITRACE_COND) { log_write("%s\n", _this->logbuf); }
#endif

#ifdef CONFIG_WATCHPOINT
  extern int config_watchpoint(void);
  if(config_watchpoint())
    nemu_state.state = NEMU_STOP;
#endif

  if (g_print_step) { IFDEF(CONFIG_ITRACE, puts(_this->logbuf)); }
  IFDEF(CONFIG_DIFFTEST, difftest_step(_this->pc, dnpc));
}

static void exec_once(Decode *s, vaddr_t pc) {
  s->pc = pc;
  s->snpc = pc;
  isa_exec_once(s);
  cpu.pc = s->dnpc;
#ifdef CONFIG_ETRACE
  if (s->isa.inst.val == 0x73) {
    printf("ecall from 0x%08x\n", s->pc);
  }
#endif // CONFIG_ETRACE
#ifdef CONFIG_FTRACE
  char *addr = strtok(s->logbuf, " ");
  char *op = strtok(s->logbuf + 24, "\t");
  if(!strcmp(op, "jal"))
  {
    for(int i = 0; i < 128; i++)
    { 
      char tmp[11];
      sprintf(tmp, "0x%08x", ftrace[i].addr);
      if(!strcmp(tmp, s->logbuf + 32))
      {
        func_stack[ftraceindex].addr = ftrace[i].addr;
        strcpy(func_stack[ftraceindex].name, ftrace[i].name);
        strcpy(func_stack[ftraceindex].pc, addr);
        // printf(ANSI_FMT("call[%s@%0x08x]\n", ANSI_FG_RED), ftrace[i].name, ftrace[i].addr);
        ++ftraceindex;
        break;
      }
    }
  }
  else if(!strcmp(op, "jalr"))
  {
    regex_t reg;
    int status;
    regmatch_t pmatch[1];
    const char *pattern = "0\\([a-z0-9]+\\)";
    char *buf = s->logbuf + 32;
    
    // 编译正则表达式
    regcomp(&reg, pattern, REG_EXTENDED);
    status = regexec(&reg, buf, 1, pmatch, 0);
    if(status == -1)
      printf("match miss\n");
    int start = pmatch[0].rm_so;
    int end = pmatch[0].rm_eo;
    if(end - start)
    {
      char src1[3] = {};
      strncpy(src1, buf + start + 2, 2);
      src1[2] = '\0';
      uint32_t call = isa_reg_str2val(src1-1);
      if(!strcmp(src1, "ra"))
      {
        for(int i = 0; i < 128; i++)
        { 
          char call_addr[12] = {};
          sprintf(call_addr, "0x%08x:", call - 4);
          if(!strcmp(call_addr, func_stack[i].pc))
          {
            strcpy(func_stack[ftraceindex].name, func_stack[i].name);
            func_stack[ftraceindex].addr = 0;
            strcpy(func_stack[ftraceindex].pc, addr);
            // printf(ANSI_FMT("ret[%s]\n", ANSI_FG_RED), ftrace[i].name);
            ++ftraceindex;
            break;
          }
        }
      }
      else
      {
        for(int i = 0; i < 128; i++)
        { 
          if(ftrace[i].addr == call)
          {
            func_stack[ftraceindex].addr = ftrace[i].addr;
            strcpy(func_stack[ftraceindex].name, ftrace[i].name);
            strcpy(func_stack[ftraceindex].pc, addr);
            // printf(ANSI_FMT("call[%s@%0x08x]\n", ANSI_FG_RED), ftrace[i].name, ftrace[i].addr);
            ++ftraceindex;
            break;
          }
        }
      }
      regfree(&reg);
    }
    else
    {
      for(int i = 0; i < 128; i++)
      { 
        char tmp[11];
        sprintf(tmp, "0x%08x", ftrace[i].addr);
        if(!strcmp(tmp, s->logbuf + 32))
        {
          func_stack[ftraceindex].addr = ftrace[i].addr;
          strcpy(func_stack[ftraceindex].name, ftrace[i].name);
          strcpy(func_stack[ftraceindex].pc, addr);
          ++ftraceindex;
          break;
        }
      }
    }
  }
#endif
#ifdef CONFIG_ITRACE
  char *p = s->logbuf;
  p += snprintf(p, sizeof(s->logbuf), FMT_WORD ":", s->pc);
  int ilen = s->snpc - s->pc;
  int i;
  uint8_t *inst = (uint8_t *)&s->isa.inst.val;
  for (i = ilen - 1; i >= 0; i --) {
    p += snprintf(p, 4, " %02x", inst[i]);
  }
  int ilen_max = MUXDEF(CONFIG_ISA_x86, 8, 4);
  int space_len = ilen_max - ilen;
  if (space_len < 0) space_len = 0;
  space_len = space_len * 3 + 1;
  memset(p, ' ', space_len);
  p += space_len;

#ifndef CONFIG_ISA_loongarch32r
  void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);
  disassemble(p, s->logbuf + sizeof(s->logbuf) - p,
      MUXDEF(CONFIG_ISA_x86, s->snpc, s->pc), (uint8_t *)&s->isa.inst.val, ilen);

  int len = sprintf(iringbuf[iringbufindex%iringlength], "0x%08x: ", pc);
  len += sprintf(iringbuf[iringbufindex%iringlength] + len, "%s", p);
  sprintf(iringbuf[iringbufindex%iringlength] + len, "\t\t%08x", s->isa.inst.val);
  ++iringbufindex;
#else
  p[0] = '\0'; // the upstream llvm does not support loongarch32r
#endif
#endif
}

static void execute(uint64_t n) {
  Decode s;
  for (;n > 0; n --) {
    exec_once(&s, cpu.pc);
    g_nr_guest_inst ++;
    trace_and_difftest(&s, cpu.pc);
    if (nemu_state.state != NEMU_RUNNING) break;
    IFDEF(CONFIG_DEVICE, device_update());
    // word_t intr = isa_query_intr();
    // if (intr != INTR_EMPTY) {
    //   cpu.pc = isa_raise_intr(intr, cpu.pc);
    // }
  }
}

static void statistic() {
  IFNDEF(CONFIG_TARGET_AM, setlocale(LC_NUMERIC, ""));
#define NUMBERIC_FMT MUXDEF(CONFIG_TARGET_AM, "%", "%'") PRIu64
  Log("host time spent = " NUMBERIC_FMT " us", g_timer);
  Log("total guest instructions = " NUMBERIC_FMT, g_nr_guest_inst);
  if (g_timer > 0) Log("simulation frequency = " NUMBERIC_FMT " inst/s", g_nr_guest_inst * 1000000 / g_timer);
  else Log("Finish running in less than 1 us and can not calculate the simulation frequency");
}

void assert_fail_msg() {
  #ifdef CONFIG_ITRACE
    isa_exec_err_display();
  #endif
  isa_reg_display();
  statistic();
}

/* Simulate how the CPU works. */
void cpu_exec(uint64_t n) {
  g_print_step = (n < MAX_INST_TO_PRINT);
  switch (nemu_state.state) {
    case NEMU_END: case NEMU_ABORT:
      printf("Program execution has ended. To restart the program, exit NEMU and run again.\n");
      return;
    default: nemu_state.state = NEMU_RUNNING;
  }

  uint64_t timer_start = get_time();

  execute(n);

  uint64_t timer_end = get_time();
  g_timer += timer_end - timer_start;

  switch (nemu_state.state) {
    case NEMU_RUNNING: nemu_state.state = NEMU_STOP; break;

    case NEMU_ABORT:
    case NEMU_END:
      Log("nemu: %s at pc = " FMT_WORD,
          (nemu_state.state == NEMU_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
           (nemu_state.halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) :
            ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
          nemu_state.halt_pc);
      #ifdef CONFIG_ITRACE
        if (nemu_state.halt_ret != 0)
          isa_exec_err_display();
      #endif
      // fall through
    case NEMU_QUIT: statistic();
  }
}

#ifdef CONFIG_ITRACE
void
isa_exec_err_display()
{
  int pos = iringbufindex % iringlength;
  for (int i = 0; i < iringlength; i++) {
    int index = (i+pos)%iringlength;
    if (strlen(iringbuf[index]))
      Log("%s", iringbuf[index]);
  }
}
#endif

#ifdef CONFIG_FTRACE
void print_func_stack()
{
  int count = 0;
  for(int i = 0; i < ftraceindex; i++)
  {
    if(func_stack[i].addr)
    {
      printf("%s\t", func_stack[i].pc); 
      for(int j = 0; j < count; j++)
        printf("\t");
      printf("call[%s@%0x08x]\n", func_stack[i].name, func_stack[i].addr);
      ++count;
    }
    else
    {
      --count;
      printf("%s\t", func_stack[i].pc); 
      for(int j = 0; j < count; j++)
        printf("\t");
      printf("ret[%s]\n", func_stack[i].name);
    }
  }
}
#endif
