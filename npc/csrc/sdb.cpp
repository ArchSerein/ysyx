#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include "defs.hpp"
#include "pmem.hpp"
#include "wp.hpp"
#include "state.hpp"
#include <readline/readline.h>
#include <readline/history.h>

NPCState npc_state;
static bool is_batch_mode = false;

void sdb_set_batch_mode() {
  is_batch_mode = true;
}

static int
cmd_si(char *arg)
{
    int n = 1;
    if (arg != NULL)
    {
        n = atoi(arg);
    }

    exec(n);

    return 0;
}

static int
cmd_info(char *arg)
{
    if (!strcmp(arg, "r"))
        isa_reg_display();
    else {
        info_w();
    }
    return 0;
}

static int
cmd_q(char *arg)
{
    return -1;
}
static int
cmd_c(char *args) {
  exec(-1);
  return 0;
}
static int
cmd_p(char *args) {
  bool success = true;
  uint32_t result = expr(args, &success);
  if (success) {
    printf("result = %x\n", result);
  }
  return 0;
}

static int
cmd_w(char *args) {
  new_wp(args);
  return 0;
}

static int
cmd_d(char *args) {
  int n = atoi(args);
  free_wp(n);
  return 0;
}

static int
cmd_x(char *args) {
  int N = atoi(strtok(args, " "));
  char *addr = strtok(NULL, "");
  bool success = true;
  uint32_t result = expr(addr, &success);
  sprintf(addr, "0x%x", result);
  paddr_t vaddr = (paddr_t)strtol(addr, NULL, 16);
  for(int i = 0; i < N; i++)
  {
    uint32_t data = vaddr_read((vaddr + 4 * i), 4);
    printf("addr: 0x%08x->data: 0x%08x\n",vaddr + 4 * i, data);
  }

  return 0;
}

#ifdef CONFIG_FTRACE
static int
cmd_print(char *args) {
  extern void print_func_stack();
  print_func_stack();
  return 0;
}
#endif // CONFIG_FTRACE

#define NR_CMD ARRLEN(cmd_table)

static int cmd_help(char *args);

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  {"help", "Display informations about all supported commands", cmd_help},
  {"si", "Lets the program pause after executing N instructions in a single step.When N is not given, the default is 1.", cmd_si},
  {"info", "Printing Register Status or watchpoint information", cmd_info},
  {"q", "Exit NPC", cmd_q},
  {"c", "Continue to run the program", cmd_c},
  {"p", "Find the value of the expression EXPR", cmd_p},
  {"w", "Suspends program execution when the value of expression EXPR changes.", cmd_w},
  {"d", "Delete the monitoring point with serial number N.", cmd_d},
  {"x","Outputs N consecutive 4-bytes in hexadecimal form", cmd_x},
  #ifdef CONFIG_FTRACE
  {"print", "Print the function call stack", cmd_print},
  #endif // CONFIG_FTRACE
};

static int
cmd_help(char *args) {
  /* extract the first argument */
  char *arg = strtok(NULL, " ");
  int i;

  if (arg == NULL) {
    /* no argument given */
    for (i = 0; i < NR_CMD; i ++) {
      printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
    }
  }
  else {
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(arg, cmd_table[i].name) == 0) {
        printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        return 0;
      }
    }
    printf("Unknown command '%s'\n", arg);
  }
  return 0;
}

static char* rl_gets() {
  static char *line_read = NULL;

  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(npc) ");

  if (line_read && *line_read) {
    add_history(line_read);
  }

  return line_read;
}

void
sdb_mainloop()
{
  if (is_batch_mode) {
    cmd_c(NULL);
    return;
  }
  for (char *str; (str = rl_gets()) != NULL; ) {
        char *str_end = str + strlen(str);

        /* extract the first token as the command */
        char *cmd = strtok(str, " ");
        if (cmd == NULL) { continue; }

        /* treat the remaining string as the arguments,
         * which may need further parsing
         */
        char *args = cmd + strlen(cmd) + 1;
        if (args >= str_end) {
          args = NULL;
    }

    int i;
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(cmd, cmd_table[i].name) == 0) {
        if (cmd_table[i].handler(args) < 0) {
            if(strcmp(cmd, "q") == 0)
                npc_state.state = QUIT;
          return;
        }
        break;
      }
    }

    if (i == NR_CMD) { printf("Unknown command '%s'\n", cmd); }
  }
}

void
init_sdb() {
  /* Compile the regular expressions. */
  init_regex();

  /* Initialize the watchpoint pool. */
  #ifdef CONFIG_WATCHPOINT
    init_wp_pool();
  #endif // CONFIG_WATCHPOINT
}
