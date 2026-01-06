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

#include "local-include/reg.h"
#include <cpu/cpu.h>
#include <cpu/ifetch.h>
#include <cpu/decode.h>

#define R(i) gpr(i)
#define Mr vaddr_read
#define Mw vaddr_write

enum {
  TYPE_I, TYPE_U, TYPE_S, TYPE_J, TYPE_R, TYPE_B,
  TYPE_N, // none
};

#define CSRW() \
                do { \
                       switch (imm) { \
                          case 0x300: cpu.csr[MSTATUS] = src1; break; \
                          case 0x342: cpu.csr[MCAUSE] = src1; break; \
                          case 0x341: cpu.csr[MEPC] = src1; break; \
                          case 0x305: cpu.csr[MTVEC] = src1; break; \
                          case 0x180: cpu.csr[SATP] = src1; break; \
                          default: ;break; \
                      } \
                    } while (0)
#define CSRR() \
                 do { \
                      switch (imm&0xfff) { \
                          case 0x300: t = cpu.csr[MSTATUS]; break; \
                          case 0x342: t = cpu.csr[MCAUSE]; break; \
                          case 0x341: t = cpu.csr[MEPC]; break; \
                          case 0x305: t = cpu.csr[MTVEC]; break; \
                          case 0xf11: t = 0x78797379; break;  \
                          case 0xf12: t = 0x017dc6a3;  break;  \
                          case 0x180: t = cpu.csr[SATP]; break; \
                          default: ; break; \
                      } \
                    } while(0)
#define src1R() do { *src1 = R(rs1); } while (0)
#define src2R() do { *src2 = R(rs2); } while (0)
#define immI() do { *imm = SEXT(BITS(i, 31, 20), 12); } while(0)
#define immU() do { *imm = SEXT(BITS(i, 31, 12), 20) << 12; } while(0)
#define immS() do { *imm = (SEXT(BITS(i, 31, 25), 7) << 5) | BITS(i, 11, 7); } while(0)
#define immJ() do { *imm = (SEXT((BITS(i, 31, 31) << 20) | \
                                 (BITS(i, 19, 12) << 12) | \
                                 (BITS(i, 20, 20) << 11) | \
                                 (BITS(i, 30, 21) << 1 ), 21)); } while(0)
#define immB() do { *imm = (SEXT((BITS(i, 31, 31) << 12) | \
                                 (BITS(i, 7 , 7 ) << 11) | \
                                 (BITS(i, 30, 25) << 5 ) | \
                                 (BITS(i, 11, 8 ) << 1 ), 13)); } while(0)

static void decode_operand(Decode *s, int *rd, word_t *src1, word_t *src2, word_t *imm, int type) {
  uint32_t i = s->isa.inst.val;
  int rs1 = BITS(i, 19, 15);
  int rs2 = BITS(i, 24, 20);
  *rd     = BITS(i, 11, 7);
  switch (type) {
    case TYPE_I: src1R();          immI(); break;
    case TYPE_U:                   immU(); break;
    case TYPE_S: src1R(); src2R(); immS(); break;
    case TYPE_J:                   immJ(); break;
    case TYPE_R: src1R(); src2R();         break;
    case TYPE_B: src1R(); src2R(); immB(); break;
  }
}

static int decode_exec(Decode *s) {
  int rd = 0;
  word_t src1 = 0, src2 = 0, imm = 0, t = 0;
  s->dnpc = s->snpc;

#define INSTPAT_INST(s) ((s)->isa.inst.val)
#define INSTPAT_MATCH(s, name, type, ... /* execute body */ ) { \
  decode_operand(s, &rd, &src1, &src2, &imm, concat(TYPE_, type)); \
  __VA_ARGS__ ; \
}


  INSTPAT_START();
  INSTPAT("??????? ????? ????? 001 ????? 11100 11", csrrw  , I, CSRR(); R(rd) = t; CSRW());
  INSTPAT("??????? ????? ????? 010 ????? 11100 11", csrrs  , I, CSRR(); R(rd) = t; src1 = t | src1; CSRW());
  INSTPAT("0000000 00000 00000 000 00000 11100 11", ecall  , N, s->dnpc = isa_raise_intr(0xb, s->pc));
  INSTPAT("0011000 00010 00000 000 00000 11100 11", mret   , N, s->dnpc = cpu.csr[MEPC]);
  INSTPAT("??????? ????? ????? 010 ????? 01000 11", sw     , S, Mw(src1 + imm, 4, src2));
  INSTPAT("??????? ????? ????? 010 ????? 00000 11", lw     , I, R(rd) = Mr(src1 + imm, 4));
  INSTPAT("??????? ????? ????? ??? ????? 01101 11", lui    , U, R(rd) = imm);
  INSTPAT("??????? ????? ????? 000 ????? 00100 11", addi   , I, R(rd) = src1 + imm);
  INSTPAT("0000001 ????? ????? 000 ????? 01100 11", mul    , R, R(rd) = src1 * src2);
  INSTPAT("0000001 ????? ????? 001 ????? 01100 11", mulh   , R, R(rd) = (SEXT(src1, 32) * SEXT(src2, 32)) >> 32);
  INSTPAT("0000000 ????? ????? 000 ????? 01100 11", add    , R, R(rd) = (src1 + src2));
  INSTPAT("0100000 ????? ????? 000 ????? 01100 11", sub    , R, R(rd) = (src1 - src2));
  INSTPAT("0000001 ????? ????? 100 ????? 01100 11", div    , R, R(rd) = (int32_t)src1 / (int32_t)src2);
  INSTPAT("0000001 ????? ????? 101 ????? 01100 11", divu   , R, R(rd) = src1 / src2);
  INSTPAT("0000001 ????? ????? 110 ????? 01100 11", rem    , R, R(rd) = (int32_t)src1 % (int32_t)src2);
  INSTPAT("0000001 ????? ????? 111 ????? 01100 11", remu   , R, R(rd) = src1 % src2);
  INSTPAT("??????? ????? ????? 001 ????? 11000 11", bne    , B, s->dnpc = (src1 == src2 ? s->pc + 4 : s->pc + imm));
  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal    , J, R(rd) = s->pc + 4, s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr   , I, R(rd) = s->pc + 4, s->dnpc = src1 + imm);
  INSTPAT("??????? ????? ????? 011 ????? 00100 11", sltiu  , I, if(src1 < imm) R(rd) = 1; else R(rd) = 0;);
  INSTPAT("??????? ????? ????? 010 ????? 00100 11", slti   , I, if((int32_t)src1 < (int32_t)imm) R(rd) = 1; else R(rd) = 0;);
  INSTPAT("0000000 ????? ????? 011 ????? 01100 11", sltu   , R, R(rd) = (src1 < src2 ? 1 : 0));
  INSTPAT("0000000 ????? ????? 010 ????? 01100 11", slt    , R, R(rd) = ((int32_t)src1 < (int32_t)src2 ? 1 : 0));
  INSTPAT("??????? ????? ????? 100 ????? 11000 11", blt    , B, s->dnpc = (int32_t)src1 < (int32_t)src2 ? s->pc + imm : s->pc + 4);
  INSTPAT("??????? ????? ????? 110 ????? 11000 11", bltu   , B, s->dnpc = src1 < src2 ? s->pc + imm : s->pc + 4);
  INSTPAT("??????? ????? ????? 000 ????? 11000 11", beq    , B, s->dnpc = (src1 == src2 ? s->pc + imm : s->pc + 4));
  INSTPAT("??????? ????? ????? 101 ????? 11000 11", bge    , B, s->dnpc = ((int32_t)src1 >= (int32_t)src2 ? s->pc + imm : s->pc + 4));
  INSTPAT("??????? ????? ????? 111 ????? 11000 11", bgeu   , B, s->dnpc = (src1 >= src2 ? s->pc + imm : s->pc + 4));
  INSTPAT("??????? ????? ????? ??? ????? 00101 11", auipc  , U, R(rd) = s->pc + imm);
  INSTPAT("??????? ????? ????? 100 ????? 00000 11", lbu    , I, R(rd) = Mr(src1 + imm, 1));
  INSTPAT("??????? ????? ????? 000 ????? 00000 11", lb     , I, R(rd) = SEXT(Mr(src1 + imm, 1), 8));
  INSTPAT("0000000 ????? ????? 001 ????? 01100 11", sll    , R, R(rd) = src1 << (src2 & 0x0000001f));
  INSTPAT("0100000 ????? ????? 101 ????? 00100 11", srai   , I, R(rd) = (int32_t)src1 >> imm);
  INSTPAT("0100000 ????? ????? 101 ????? 01100 11", sra    , R, R(rd) = (int32_t)src1 >> BITS(src2, 4, 0));
  INSTPAT("0000000 ????? ????? 101 ????? 01100 11", srl    , R, R(rd) = src1 >> BITS(src2, 4, 0));
  INSTPAT("0000000 ????? ????? 001 ????? 00100 11", slli   , I, R(rd) = src1 << imm);
  INSTPAT("0000000 ????? ????? 101 ????? 00100 11", srli   , I, R(rd) = src1 >> imm);
  INSTPAT("??????? ????? ????? 000 ????? 01000 11", sb     , S, Mw(src1 + imm, 1, src2));
  INSTPAT("??????? ????? ????? 001 ????? 01000 11", sh     , S, Mw(src1 + imm, 2, src2));
  INSTPAT("??????? ????? ????? 101 ????? 00000 11", lhu    , I, R(rd) = Mr(src1 + imm, 2) & 0x0000FFFF);
  INSTPAT("??????? ????? ????? 001 ????? 00000 11", lh     , I, R(rd) = SEXT(Mr(src1 + imm, 2), 16));
  INSTPAT("0000000 ????? ????? 100 ????? 01100 11", xor    , R, R(rd) = src1 ^ src2);
  INSTPAT("??????? ????? ????? 100 ????? 00100 11", xori   , I, R(rd) = src1 ^ imm);
  INSTPAT("0000000 ????? ????? 111 ????? 01100 11", and    , R, R(rd) = src1 & src2);
  INSTPAT("??????? ????? ????? 111 ????? 00100 11", andi   , I, R(rd) = src1 & imm);
  INSTPAT("0000000 ????? ????? 110 ????? 01100 11", or     , R, R(rd) = src1 | src2);
  INSTPAT("??????? ????? ????? 110 ????? 00100 11", ori    , I, R(rd) = src1 | imm);
  INSTPAT("0000001 ????? ????? 011 ????? 01100 11", mulhu  , R, uint32_t hi1 = src1 >> 16; uint32_t hi2 = src2 >> 16; \
                                                                uint32_t lo1 = src1 & 0xffff; uint32_t lo2 = src2 & 0xffff; \
                                                                uint32_t high = hi1 * hi2; uint32_t mid1 = hi1 * lo2; \
                                                                uint32_t mid2 = lo1 * hi2; uint32_t low = lo1 * lo2;  \
                                                                uint32_t carry = (low >> 16) + (mid1 & 0xffff) + (mid2 & 0xffff); \
                                                                R(rd) = high + (mid2 >> 16) + (mid1 >> 16) + (carry >> 16));
  INSTPAT("0000000 00001 00000 000 00000 11100 11", ebreak , N, NEMUTRAP(s->pc, R(10))); // R(10) is $a0
  INSTPAT("??????? ????? ????? ??? ????? ????? ??", inv    , N, INV(s->pc));
  INSTPAT_END();

  R(0) = 0; // reset $zero to 0

  return 0;
}

int isa_exec_once(Decode *s) {
  s->isa.inst.val = inst_fetch(&s->snpc, 4);
  return decode_exec(s);
}
