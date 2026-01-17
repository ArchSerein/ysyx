/***************************************************************************************
* Copyright (c) 2014-2022 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <common.h>
#include <device/map.h>
#include <SDL2/SDL.h>

enum {
  reg_freq,
  reg_channels,
  reg_samples,
  reg_sbuf_size,
  reg_init,
  reg_count,
  nr_reg
};

static uint8_t *sbuf = NULL;
static uint32_t *audio_base = NULL;
static uint8_t   mux = 1;
static volatile uint32_t used = 0;
static volatile uint32_t rpos = 0;
static volatile uint32_t wpos = 0;

static void audio_sbuf_handler(uint32_t offset, int len, bool is_write) {
  used += len;
  wpos = (wpos + len) % CONFIG_SB_SIZE;
}

static void audio_callback(void *userdata, uint8_t *stream, int len) {
  SDL_memset(stream, 0, len);

  uint32_t need = (uint32_t)len;
  uint32_t have = used;
  uint32_t n    = (need < have) ? need : have;

  if (n == 0) return;

  uint32_t first = (rpos + n > CONFIG_SB_SIZE) ?
                    (CONFIG_SB_SIZE - rpos) : n;
  SDL_memcpy(stream, sbuf + rpos, first);

  uint32_t second = n - first;
  if (second > 0)
    SDL_memcpy(stream + first, sbuf, second);

  rpos = (rpos + n) % CONFIG_SB_SIZE;
  used -= n;
}

static void audio_io_handler(uint32_t offset, int len, bool is_write) {
  if (is_write) {
    if ((offset >> 2) == reg_init && audio_base[reg_init] == 1) {
      SDL_AudioSpec spec;
      spec.freq = audio_base[reg_freq];
      spec.format = AUDIO_S16SYS;
      spec.channels = audio_base[reg_channels];
      spec.samples = audio_base[reg_samples];
      spec.callback = audio_callback;
      spec.userdata = NULL;
      int ret = SDL_InitSubSystem(SDL_INIT_AUDIO);
      if (ret < 0)
        panic("SDL_InitSubSystem failed: %s", SDL_GetError());
      ret = SDL_OpenAudio(&spec, NULL);
      if (ret < 0)
        panic("SDL_OpenAudio failed: %s", SDL_GetError());
      SDL_PauseAudio(0);
    }
  } else {
    switch (offset >> 2) {
      case reg_sbuf_size:
        audio_base[reg_sbuf_size] = CONFIG_SB_SIZE;
        break;
      case reg_count:
        if (mux == 1)
          audio_base[reg_count] = used;
        else if (mux == 2)
          audio_base[reg_count] = wpos;
        break;
      case reg_init:
        if (audio_base[reg_init] == 2)
          mux = 2;
        else if (audio_base[reg_init] == 3)
          mux = 1;
        break;
    }
  }
}

void init_audio() {
  uint32_t space_size = sizeof(uint32_t) * nr_reg;
  audio_base = (uint32_t *)new_space(space_size);
#ifdef CONFIG_HAS_PORT_IO
  add_pio_map ("audio", CONFIG_AUDIO_CTL_PORT, audio_base, space_size, audio_io_handler);
#else
  add_mmio_map("audio", CONFIG_AUDIO_CTL_MMIO, audio_base, space_size, audio_io_handler);
#endif

  sbuf = (uint8_t *)new_space(CONFIG_SB_SIZE);
  // add_mmio_map("audio-sbuf", CONFIG_SB_ADDR, sbuf, CONFIG_SB_SIZE, NULL);
  add_mmio_map("audio-sbuf", CONFIG_SB_ADDR, sbuf, CONFIG_SB_SIZE, audio_sbuf_handler);
}
