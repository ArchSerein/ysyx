#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int evtdev = -1;
static int fbdev = -1;
static int screen_w = 0, screen_h = 0;

uint32_t NDL_GetTicks() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  uint32_t ms = tv.tv_sec * 1000 + tv.tv_usec / 1000;
  return ms;
}

int NDL_PollEvent(char *buf, int len) {
  int fp = open("/dev/events", 0, 0);
  if (fp == -1) {
    printf("open failed\n");
    return -1;
  }
  int ret = read(fp, buf, len);
  close(fp);
  return ret;
}

void NDL_OpenCanvas(int *w, int *h) {
  if (getenv("NWM_APP")) {
    int fbctl = 4;
    fbdev = 5;
    screen_w = *w; screen_h = *h;
    char buf[64];
    int len = sprintf(buf, "%d %d", screen_w, screen_h);
    // let NWM resize the window and create the frame buffer
    write(fbctl, buf, len);
    while (1) {
      // 3 = evtdev
      int nread = read(3, buf, sizeof(buf) - 1);
      if (nread <= 0) continue;
      buf[nread] = '\0';
      if (strcmp(buf, "mmap ok") == 0) break;
    }
    close(fbctl);
  } else {
    char buf[64];
    int fd = open("/proc/dispinfo", 0, 0);
    read(fd, buf, 64);
    close(fd);
    sscanf(buf, "WIDTH : %d HEIGHT : %d", &screen_w, &screen_h);
    if (*w > screen_w || *w == 0) *w = screen_w;
    if (*h > screen_h || *h == 0) *h = screen_h;
  }
}

struct fb_info {
  int w, h;
  int x, y;
  uint32_t *pixels;
};
void NDL_DrawRect(uint32_t *pixels, int x, int y, int w, int h) {
  struct fb_info info = {.w = w, .h = h, .x = x, .y = y,
                          .pixels = pixels};
  int fd = open("/dev/fb", 0, 0);
  int len = w * h * sizeof(uint32_t);
  write(fd, &info, len);
  close(fd);
}

void NDL_OpenAudio(int freq, int channels, int samples) {
  int fd = open("/dev/sbctl", 0, 0);
  int arguments[3] = {freq, channels, samples};
  write(fd, arguments, sizeof(arguments));
}

void NDL_CloseAudio() {
  // wait until the audio finishes
  // then directly return;
  int fd = open("/dev/sbctl", 0, 0);
  int count = 0;
  read(fd, &count, sizeof(count));
  while (count > 0) {
    read(fd, &count, sizeof(count));
  }
}

int NDL_PlayAudio(void *buf, int len) {
  int fd = open("/dev/sb", 0, 0);
  return write(fd, buf, len);
}

int NDL_QueryAudio() {
  int fd = open("/dev/sbctl", 0, 0);
  int count = 0;
  read(fd, &count, sizeof(count));
  return count;
}

int NDL_Init(uint32_t flags) {
  if (getenv("NWM_APP")) {
    evtdev = 3;
  }
  return 0;
}

void NDL_Quit() {
}
