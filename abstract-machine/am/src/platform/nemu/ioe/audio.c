#include <am.h>
#include <nemu.h>

#define AUDIO_FREQ_ADDR      (AUDIO_ADDR + 0x00)
#define AUDIO_CHANNELS_ADDR  (AUDIO_ADDR + 0x04)
#define AUDIO_SAMPLES_ADDR   (AUDIO_ADDR + 0x08)
#define AUDIO_SBUF_SIZE_ADDR (AUDIO_ADDR + 0x0c)
#define AUDIO_INIT_ADDR      (AUDIO_ADDR + 0x10)
#define AUDIO_COUNT_ADDR     (AUDIO_ADDR + 0x14)

void __am_audio_init() {
}

void __am_audio_config(AM_AUDIO_CONFIG_T *cfg) {
  int sbuf_size = inl(AUDIO_SBUF_SIZE_ADDR);
  cfg->bufsize = sbuf_size;
  cfg->present = true;
}

void __am_audio_ctrl(AM_AUDIO_CTRL_T *ctrl) {
  int freq = ctrl->freq;
  int channels = ctrl->channels;
  int samples = ctrl->samples;
  outl(AUDIO_FREQ_ADDR, (uint32_t)freq);
  outl(AUDIO_CHANNELS_ADDR, (uint32_t)channels);
  outl(AUDIO_SAMPLES_ADDR, (uint32_t)samples);
  outl(AUDIO_INIT_ADDR, 1);
}

void __am_audio_status(AM_AUDIO_STATUS_T *stat) {
  int count = inl(AUDIO_COUNT_ADDR);
  stat->count = count;
}

void __am_audio_play(AM_AUDIO_PLAY_T *ctl) {
  Area buf = ctl->buf;
  uint8_t *src = (uint8_t *)buf.start;
  uint32_t size = (uint32_t)(buf.end - buf.start);
  uint32_t sbuf_size = inl(AUDIO_SBUF_SIZE_ADDR);
  outl(AUDIO_INIT_ADDR, 3);
  uint32_t count = inl(AUDIO_COUNT_ADDR);
  // wait until there is enough space in the audio buffer
  while (size + count >= sbuf_size)
    count = inl(AUDIO_COUNT_ADDR);

  outl(AUDIO_INIT_ADDR, 2);
  uint32_t wpos = inl(AUDIO_COUNT_ADDR);
  uint32_t i = 0;
  for (; i + 4 < size; i+=4) {
    uint32_t off = (i + wpos) % sbuf_size;
    outl(AUDIO_SBUF_ADDR + off, *(uint32_t *)(src + i));
  }

  for (; i < size; i++) {
    uint32_t off = (i + wpos) % sbuf_size;
    outb(AUDIO_SBUF_ADDR + off, *(src + i));
  }
}
