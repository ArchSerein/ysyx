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
#include "local-include/reg.h"

const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};
const char *csr_name[] = {
  "MEPC", "MSTATUS", "MTVEC", "MCAUSE"
};

void isa_reg_display() {
  for(int i = 0; i < 32; i++)
  {
    printf("%s\t0x%x\t%d\n", regs[i], cpu.gpr[i], cpu.gpr[i]);
  }
  printf("pc\t0x%x\t0x%x\n", cpu.pc, cpu.pc);
  // csrs
  for (int i = 0; i < 4; i++) {
    printf("%s\t0x%x\t%d\n", csr_name[i], cpu.csr[i], cpu.csr[i]);
  }
}

word_t isa_reg_str2val(const char *s) {
  const char *reg_name = s + 1;
  for(int i = 0; i < 32; i++)
  {
    if(strcmp(reg_name, regs[i]) == 0)
    {
      return cpu.gpr[i];
    }
  }

  if(strcmp(reg_name, "pc") == 0)
  {
    return cpu.pc;
  }
  return 0;
}
