#include <nterm.h>
#include <stdarg.h>
#include <unistd.h>
#include <SDL.h>

char handle_key(SDL_Event *ev);

static void sh_printf(const char *format, ...) {
  static char buf[256] = {};
  va_list ap;
  va_start(ap, format);
  int len = vsnprintf(buf, 256, format, ap);
  va_end(ap);
  term->write(buf, len);
}

static void sh_banner() {
  sh_printf("Built-in Shell in NTerm (NJU Terminal)\n\n");
}

static void sh_prompt() {
  sh_printf("sh> ");
}

static int cmd_echo(char *argv) {
  if (argv == NULL)
    return -1;
  sh_printf("%s", argv);
  return 0;
}

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  {"echo", "display a line of text", cmd_echo},
};

#define ARRLEN(arr) (int)(sizeof(arr) / sizeof(arr[0]))
#define NR_CMD ARRLEN(cmd_table)

static void token_parser(char *argv[], char *cmd) {
  char *saveptr;
  char *token = strtok_r(cmd, " ", &saveptr);
  int i = 0;
  while (token) {
    argv[i++] = token;
    token = strtok_r(NULL, " ", &saveptr);
  }
  argv[i] = NULL;
}

static void sh_handle_cmd(const char *cmd) {
  setenv("PATH", "/bin/:/usr/bin/", 0);
  size_t length = strlen(cmd);
  char str[length+1];
  memcpy(str, cmd, length);
  str[length-1] = 0;
  char *argv[64] = { NULL };
  token_parser(argv, str);
  for (int i = 0; i < NR_CMD; i++) {
    if (strcmp(cmd_table[i].name, argv[0]) == 0) {
      char *args = (char *)(cmd + strlen(argv[0]) + 1);
      if (cmd_table[i].handler(args) < 0)
        sh_printf("command %s exec failed", args);
      return;
    }
  }
  execvp(argv[0], argv);
}

void builtin_sh_run() {
  sh_banner();
  sh_prompt();

  while (1) {
    SDL_Event ev;
    if (SDL_PollEvent(&ev)) {
      if (ev.type == SDL_KEYUP || ev.type == SDL_KEYDOWN) {
        const char *res = term->keypress(handle_key(&ev));
        if (res) {
          sh_handle_cmd(res);
          sh_prompt();
        }
      }
    }
    refresh_terminal();
  }
}
