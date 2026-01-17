#include <common.h>

#if defined(MULTIPROGRAM) && !defined(TIME_SHARING)
# define MULTIPROGRAM_YIELD() yield()
#else
# define MULTIPROGRAM_YIELD()
#endif

#define NAME(key) \
  [AM_KEY_##key] = #key,

static const char *keyname[256] __attribute__((used)) = {
  [AM_KEY_NONE] = "NONE",
  AM_KEYS(NAME)
};

size_t serial_write(const void *buf, size_t offset, size_t len) {
  size_t i;
  for (i = 0; i < len; i++) {
    putch(((char *)buf)[i]);
  }
  return i;
}

size_t events_read(void *buf, size_t offset, size_t len) {
  char *ptr = (char *)buf;
  size_t ret = 0;
  AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
  if (ev.keycode != AM_KEY_NONE) {
    // strcpy(ptr, keyname[ev.keycode]);
    if (ev.keydown) {
      #ifdef CONFIG_FG_PCB
      uint32_t front_end = 0;
      switch (ev.keycode) {
        case AM_KEY_F1:
          front_end = 1;
          break;
        case AM_KEY_F2:
          front_end = 2;
          break;
        case AM_KEY_F3:
          front_end = 3;
          break;
        default:
          sprintf(ptr, "kd %s", keyname[ev.keycode]);
          break;
      }
      if (front_end != 0) {
        extern void switch_current_fg_pcb(uint32_t);
        switch_current_fg_pcb(front_end);
      }
      #else
      sprintf(ptr, "kd %s", keyname[ev.keycode]);
      #endif
    } else {
      sprintf(ptr, "ku %s", keyname[ev.keycode]);
    }
    ret = strlen(keyname[ev.keycode])+3;
  }
  return ret;
}

size_t dispinfo_read(void *buf, size_t offset, size_t len) {
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  sprintf(buf, "WIDTH : %d HEIGHT : %d", cfg.width, cfg.height);
  return strlen(buf);
}

struct fb_info {
  int w, h;
  int x, y;
  uint32_t *pixels;
};
size_t fb_write(const void *buf, size_t offset, size_t len) {
  int x, y, w, h;
  struct fb_info *info = (struct fb_info *)buf;
  x = info->x;
  y = info->y;
  w = info->w;
  h = info->h;
  uint32_t *pixels = info->pixels;
  io_write(AM_GPU_FBDRAW, x, y, pixels, w, h, true);
  return 0;
}

size_t sb_write(const void *buf, size_t offset, size_t len) {
  Area sbuf = {
    .start = (void *)buf,
    .end   = (void *)buf + len,
  };
  io_write(AM_AUDIO_PLAY, sbuf);
  return len;
}

size_t sbctl_read(void *buf, size_t offset, size_t len) {
  int count = io_read(AM_AUDIO_STATUS).count;
  *(int *)buf = count;
  return sizeof(int);
}

size_t sbctl_write(const void *buf, size_t offset, size_t len) {
  int *params   = (int *)buf;
  int freq      = params[0];
  int channels  = params[1];
  int samples   = params[2];
  io_write(AM_AUDIO_CTRL, freq, channels, samples);
  return len;
}

void init_device() {
  Log("Initializing devices...");
  ioe_init();
}
