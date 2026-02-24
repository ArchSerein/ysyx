#include <am.h>
#include <keymap.h>
#include <klib-macros.h>

void __am_timer_init();
void __am_gpu_init();
void __am_audio_init();
void __am_input_keybrd(AM_INPUT_KEYBRD_T *);
void __am_timer_rtc(AM_TIMER_RTC_T *);
void __am_timer_uptime(AM_TIMER_UPTIME_T *);
void __am_gpu_config(AM_GPU_CONFIG_T *);
void __am_gpu_status(AM_GPU_STATUS_T *);
void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *);
void __am_audio_config(AM_AUDIO_CONFIG_T *);
void __am_audio_ctrl(AM_AUDIO_CTRL_T *);
void __am_audio_status(AM_AUDIO_STATUS_T *);
void __am_audio_play(AM_AUDIO_PLAY_T *);
void __am_disk_config(AM_DISK_CONFIG_T *cfg);
void __am_disk_status(AM_DISK_STATUS_T *stat);
void __am_disk_blkio(AM_DISK_BLKIO_T *io);
void __am_uart_getchar(AM_UART_RX_T *rx);

static void __am_timer_config(AM_TIMER_CONFIG_T *cfg) { cfg->present = true; cfg->has_rtc = true; }
static void __am_input_config(AM_INPUT_CONFIG_T *cfg) { cfg->present = true;  }
static void __am_uart_config(AM_UART_CONFIG_T *cfg)   { cfg->present = true; }
static void __am_net_config (AM_NET_CONFIG_T *cfg)    { cfg->present = false; }

typedef void (*handler_t)(void *buf);
static void *lut[128] = {
  [AM_TIMER_CONFIG] = __am_timer_config,
  [AM_TIMER_RTC   ] = __am_timer_rtc,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  [AM_INPUT_CONFIG] = __am_input_config,
  [AM_INPUT_KEYBRD] = __am_input_keybrd,
  [AM_GPU_CONFIG  ] = __am_gpu_config,
  [AM_GPU_FBDRAW  ] = __am_gpu_fbdraw,
  [AM_GPU_STATUS  ] = __am_gpu_status,
  [AM_UART_CONFIG ] = __am_uart_config,
  [AM_AUDIO_CONFIG] = __am_audio_config,
  [AM_AUDIO_CTRL  ] = __am_audio_ctrl,
  [AM_AUDIO_STATUS] = __am_audio_status,
  [AM_AUDIO_PLAY  ] = __am_audio_play,
  [AM_DISK_CONFIG ] = __am_disk_config,
  [AM_DISK_STATUS ] = __am_disk_status,
  [AM_DISK_BLKIO  ] = __am_disk_blkio,
  [AM_NET_CONFIG  ] = __am_net_config,
  [AM_UART_RX     ] = __am_uart_getchar,
};

static void fail(void *buf) { panic("access nonexist register"); }

bool ioe_init() {
  for (int i = 0; i < LENGTH(lut); i++)
    if (!lut[i]) lut[i] = fail;
  __am_gpu_init();
  __am_timer_init();
  __am_audio_init();
  return true;
}

static int shift_pressed = 0;
void __am_uart_getchar(AM_UART_RX_T *rx) {
  // rx->data = getch();
  AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);

  if (ev.keycode == AM_KEY_NONE) {
    rx->data = 0xff;
    return;
  }

  if (ev.keycode == AM_KEY_LSHIFT ||
      ev.keycode == AM_KEY_RSHIFT) {
    shift_pressed = ev.keydown;
    rx->data = 0xff;
    return;
  }

  if (!ev.keydown) {
    rx->data = 0xff;
    return;
  }

  uint8_t ch = keymap[ev.keycode];
  if (ch == 0) {
    rx->data = 0xff;
    return;
  }

  if (shift_pressed) {

    if (ch >= 'a' && ch <= 'z') {
      ch = ch - 'a' + 'A';
    }
    else {
      switch (ch) {
        case '-': ch = '_'; break;
        case '=': ch = '+'; break;
        case '[': ch = '{'; break;
        case ']': ch = '}'; break;
        case '\\': ch = '|'; break;
        case ';': ch = ':'; break;
        case '\'': ch = '"'; break;
        case ',': ch = '<'; break;
        case '.': ch = '>'; break;
        case '/': ch = '?'; break;
        case '`': ch = '~'; break;

        case '1': ch = '!'; break;
        case '2': ch = '@'; break;
        case '3': ch = '#'; break;
        case '4': ch = '$'; break;
        case '5': ch = '%'; break;
        case '6': ch = '^'; break;
        case '7': ch = '&'; break;
        case '8': ch = '*'; break;
        case '9': ch = '('; break;
        case '0': ch = ')'; break;
      }
    }
  }

  rx->data = ch;
}

void ioe_read (int reg, void *buf) { ((handler_t)lut[reg])(buf); }
void ioe_write(int reg, void *buf) { ((handler_t)lut[reg])(buf); }
