#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <getopt.h>
#include "pmem.hpp"
#include "defs.hpp"
#include "ftrace.hpp"
#include <verilated.h>
#include "debug.hpp"
#include <nvboard.h>

const char ref_so_file[] = "/home/serein/ysyx/ysyx-workbench/nemu/build/riscv32-nemu-interpreter-so";
extern "C" void init_disasm(const char *triple);

static int parse_args(int argc, char *argv[]) {
  const struct option table[] = {
    {"batch"    , no_argument      , NULL, 'b'},
    {0          , 0                , NULL,  0 },
  };
  int o;
  while ( (o = getopt_long(argc, argv, "-b", table, NULL)) != -1) {
    switch (o) {
      case 'b': sdb_set_batch_mode(); break;
    }
  }
  return 0;
}

int main(int argc, char *argv[], char *env[]) {
    #ifdef CONFIG_TRACE_WAVE
      sim_init();
    #endif // CONFIG_TRACE_WAVE
    #ifdef CONFIG_FTRACE
      if(argc < 3)
    #else
      if(argc < 2)
    #endif // CONFIG_FTRACE
    {
        printf("need a argument to initial pmem\n");
        exit(0);
    }

    Log("initializing memory: %s", argv[1]);
    long size = init_mem(argv[1]);
    #ifdef CONFIG_FTRACE
      parse_elf(argv[2]);
    #endif // CONFIG_FTRACE
    init_sdb();
    #ifdef CONFIG_ITRACE
      init_disasm("riscv32-pc-linux-gnu");
    #endif // CONFIG_ITRACE

    parse_args(argc, argv);
    Verilated::commandArgs(argc, argv);

    // nvboard
    nvboard_init_warp();

    auto start = std::chrono::high_resolution_clock::now();
    reset(1000);
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    Log("cycle time: %ld ms", duration.count());

    #ifdef CONFIG_DIFFTEST
        init_difftest(ref_so_file, size, 1234);
    #endif // CONFIG_DIFFTEST

    // 进入sdb
    sdb_mainloop();

    sim_exit();
    // 释放mem申请的内存
    free();
    nvboard_quit();
    return is_exit_status_bad();
}
