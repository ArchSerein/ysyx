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

word_t isa_raise_intr(word_t NO, vaddr_t epc) {
  /* TODO: Trigger an interrupt/exception with ``NO''.
   * Then return the address of the interrupt/exception vector.
   */
  
  cpu.csr[MEPC] = epc;
  cpu.csr[MCAUSE] = NO;

  word_t mtvec = cpu.csr[MTVEC]; 
  // save mie bit to mpie bit
  word_t mie = cpu.csr[MSTATUS] & MIE;
  cpu.csr[MSTATUS] = cpu.csr[MSTATUS] | (mie << 4);
  // clear mie bit
  cpu.csr[MSTATUS] &= (~MIE);
  return mtvec;
}

word_t isa_query_intr() {
  if (cpu.INTR && (cpu.csr[MSTATUS] & MIE)) {
    cpu.INTR = false;
    return INTR_TIMER;
  }
  return INTR_EMPTY;
}
