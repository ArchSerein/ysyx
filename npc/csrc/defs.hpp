#ifndef __DEFS_HPP
#define __DEFS_HPP

#include "generated/autoconf.h"

typedef struct inst_i{
    uint32_t pc;
    uint32_t inst;
} inst_t;

struct elf{
  char name[16];
  uint32_t addr; 
};

typedef uint32_t paddr_t;
typedef uint32_t vaddr_t;

// macros
// calculate the length of an array
#define ARRLEN(arr) (int)(sizeof(arr) / sizeof(arr[0]))

int         is_exit_state(int state);
void        single_cycle(inst_i *);
uint32_t    isa_reg_str2val(const char *s);
void        isa_reg_display();
void        info_w();
void        free();
void        sim_exit();
void        nvboard_init_warp();
#ifdef CONFIG_TRACE_WAVE
    void        sim_init();
#endif // CONFIG_TRACE_WAVE
void        reset(int n);
void        exec(uint64_t n);
int         is_exit_status_bad();
void        sdb_mainloop();
void        sdb_set_batch_mode();
uint32_t    expr(char *e, bool *success);
void        init_regex();
void        init_sdb();
extern  "C" void disassemble(char *str, int size, uint32_t pc, uint8_t *code, int nbyte);

// difftest.cpp
void    init_difftest(const char *ref_so_file, long img_size, int port);
void    difftest_step(vaddr_t pc);

// npc.cpp
extern "C" void is_difftest(char, int, char);
bool            is_difftest_cycle();
void            set_difftest_time();
extern "C" void inst_count(void);
void            cycle_count(void);

extern "C" void putch(int ch);

uint32_t        get_csr_val(int);
uint32_t        get_inst_reg();
uint32_t        get_pc_reg();
uint32_t        get_reg_val(int);
#endif
