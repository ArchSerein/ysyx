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

static void cmd_echo(char *args) {
  sh_printf("%s", args);
}

static struct {
  const char *name;
  const char *description;
  void (*handler) (char *);
} cmd_table [] = {
  {"echo", "display a line of text", cmd_echo},
};

#define ARRLEN(arr) (int)(sizeof(arr) / sizeof(arr[0]))
#define NR_CMD ARRLEN(cmd_table)

static void sh_handle_cmd(const char *cmd) {
  setenv("PATH", "/bin/", 0);
  char str[64];
  size_t str_len = strlen(cmd);
  memcpy(str, cmd, str_len + 1);
  char *path = strtok(str, " ");
  for (int i = 0; i < NR_CMD; i++) {
    if (strcmp(cmd_table[i].name, path) == 0) {
      char *arg = strlen(path) > str_len ? NULL : str + strlen(path) + 1;
      cmd_table[i].handler(arg);
      return;
    }
  }
  path[strlen(path)-1] = '\0';
  execvp(path, NULL);
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
