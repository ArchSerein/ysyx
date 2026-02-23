#include <am.h>
#include <klib.h>
#include <klib-macros.h>

void __am_timer_init();

void __am_timer_rtc(AM_TIMER_RTC_T *);
void __am_timer_uptime(AM_TIMER_UPTIME_T *);
void __am_input_keybrd(AM_INPUT_KEYBRD_T *);
void __am_uart_getchar(AM_UART_RX_T *);
void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *);

static void __am_timer_config(AM_TIMER_CONFIG_T *cfg) { cfg->present = true; cfg->has_rtc = true; }
static void __am_input_config(AM_INPUT_CONFIG_T *cfg) { cfg->present = true;  }
static void __am_uart_config(AM_INPUT_CONFIG_T *cfg) { cfg->present = true;  }
static void __am_gpu_config(AM_GPU_CONFIG_T *cfg) { 
  *cfg = (AM_GPU_CONFIG_T) {
    .present = true, .has_accel = false,
    .width = 640, .height = 480,
    .vmemsz = 0
  };
}

typedef void (*handler_t)(void *buf);
static void *lut[128] = {
  [AM_TIMER_CONFIG] = __am_timer_config,
  [AM_TIMER_RTC   ] = __am_timer_rtc,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  [AM_INPUT_CONFIG] = __am_input_config,
  [AM_INPUT_KEYBRD] = __am_input_keybrd,
  [AM_UART_CONFIG]  = __am_uart_config,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  [AM_UART_RX     ] = __am_uart_getchar,
  [AM_GPU_CONFIG]   = __am_gpu_config,
  [AM_GPU_FBDRAW]   = __am_gpu_fbdraw,
};

static void fail(void *buf) { panic("access nonexist register"); }
static void __init_keymap();

bool ioe_init() {
  for (int i = 0; i < LENGTH(lut); i++)
    if (!lut[i]) lut[i] = fail;
  __am_timer_init();
  __init_keymap();
  return true;
}

void ioe_read (int reg, void *buf) { ((handler_t)lut[reg])(buf); }
void ioe_write(int reg, void *buf) { ((handler_t)lut[reg])(buf); }

#define KBD_ADDR 0x10011000
#define SCANCODE(_) \
  _(ESCAPE, 0x76) _(F1, 0x05) _(F2, 0x06) _(F3, 0x04) \
  _(F4, 0x0C) _(F5, 0x03) _(F6, 0x0B) _(F7, 0x83) \
  _(F8, 0x0A) _(F9, 0x01) _(F10, 0x09) _(F11, 0x78) \
  _(F12, 0x07) _(GRAVE, 0x0E) _(1, 0x16) _(2, 0x1E) \
  _(3, 0x26) _(4, 0x25) _(5, 0x2E) _(6, 0x36) _(7, 0x3D) \
  _(8, 0x3E) _(9, 0x46) _(0, 0x45) _(MINUS, 0x4E) \
  _(EQUALS, 0x55) _(BACKSPACE, 0x66) _(TAB, 0x0D) \
  _(Q, 0x15) _(W, 0x1D) _(E, 0x24) _(R, 0x2D) _(T, 0x2C) \
  _(Y, 0x35) _(U, 0x3C) _(I, 0x43) _(O, 0x44) _(P, 0x4D) \
  _(LEFTBRACKET, 0x54) _(RIGHTBRACKET, 0x5B) \
  _(BACKSLASH, 0x5D) _(CAPSLOCK, 0x58) _(A, 0x1C) _(S, 0x1B) \
  _(D, 0x23) _(F, 0x2B) _(G, 0x34) _(H, 0x33) _(J, 0x3B) \
  _(K, 0x42) _(L, 0x4B) _(SEMICOLON, 0x4C) _(APOSTROPHE, 0x52) \
  _(RETURN, 0x5A) _(LSHIFT, 0x12) _(Z, 0x1A) _(X, 0x22) \
  _(C, 0x21) _(V, 0x2A) _(B, 0x32) _(N, 0x31) _(M, 0x3A) \
  _(COMMA, 0x41) _(PERIOD, 0x49) _(SLASH, 0x4A) \
  _(RSHIFT, 0x59) _(LCTRL, 0x14) _(APPLICATION, 0xFF) \
  _(LALT, 0x11) _(SPACE, 0x29) _(RALT, 0x11) _(RCTRL, 0x14) \
  _(UP, 0x7D) _(DOWN, 0x7A) _(LEFT, 0x6B) _(RIGHT, 0x74) \
  _(INSERT, 0x70) _(DELETE, 0x71) _(HOME, 0x6C) \
  _(END, 0x69) _(PAGEUP, 0x75) _(PAGEDOWN, 0x72)

#define PS2_KEY_NAMES(key, code) PS2_KEY_##key = code,

enum {
  PS2_KEY_NONE = 0,
  SCANCODE(PS2_KEY_NAMES)
};
#define PS2_KEY_MAP(k, code) keymap[code] = AM_KEY_ ## k;
static uint8_t keymap[256] = {};
static void __init_keymap() {
  SCANCODE(PS2_KEY_MAP)
}
void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  uint8_t ch = *(volatile uint8_t *)(KBD_ADDR);
  if (ch == 0xf0) {
    kbd->keydown = false;
    kbd->keycode = keymap[*(volatile uint8_t *)(KBD_ADDR)];
  } else {
    kbd->keydown = true;
    kbd->keycode = keymap[ch];
  }
}

void __am_uart_getchar(AM_UART_RX_T *rx) {
  extern uint8_t getch();
  rx->data = getch();
}

#define FB_ADDR 0x21000000
void __am_gpu_fbdraw(AM_GPU_FBDRAW_T *ctl) {
  int x = ctl->x;
  int y = ctl->y;
  int w = ctl->w;
  int h = ctl->h;

  if (!ctl->sync && (w == 0 || h == 0)) return;
  uint32_t *pixels = ctl->pixels;

  uint32_t *fb = (uint32_t *)(uintptr_t)FB_ADDR;

  uint32_t screen_width = 640;

  for (int j = y; j < y + h; j ++) {
    for (int i = x; i < x + w; i ++) {
      fb[j * screen_width + i] = pixels[(j - y) * w + (i - x)];
    }
  }
}
