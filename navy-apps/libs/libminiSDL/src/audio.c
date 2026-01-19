#include <NDL.h>
#include <SDL.h>
#include <sdl-helper.h>
#include <stdlib.h>
#include <string.h>

static uint32_t intervel    = 0;
static uint32_t last_time   = 0;
static void *   userdata    = NULL;
static uint32_t pause_flag  = 1;
static void (*callback)(void *userdata, uint8_t *stream, int len) = NULL;
static uint8_t stream[SBUF_SIZE] = {0};
static bool    re_entry     = false;

int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained) {
  int freq = desired->freq;
  int channels = desired->channels;
  int samples = desired->samples;
  NDL_OpenAudio(freq, channels, samples);
  last_time = SDL_GetTicks();
  callback  = desired->callback;
  intervel  = samples / freq * 1000;
  userdata  = desired->userdata;
  if (obtained != NULL) {
    obtained->freq = freq;
    obtained->channels = channels;
    obtained->samples = samples;
    obtained->format = desired->format;
    obtained->callback = desired->callback;
    obtained->userdata = desired->userdata;
  }
  return 0;
}

void SDL_CloseAudio() {
  NDL_CloseAudio();
  pause_flag = 1; // close audio, pause callback
}

void SDL_PauseAudio(int pause_on) {
  // pause_on is 1, never call callback
  // until pause_on is 0
  pause_flag = pause_on;
}

void CallbackHelper(void) {
  if (re_entry || pause_flag) // pause_on is not 0, never call callback
    return;
  re_entry = true;
  uint32_t current_time = SDL_GetTicks();
  if (current_time - last_time >= intervel) {
    callback(userdata, stream, SBUF_SIZE);
    NDL_PlayAudio(stream, SBUF_SIZE);
    last_time = current_time;
  }
  re_entry = false;
}

static int16_t clip(int32_t mixed) {
  int32_t ret = 0;
  if (mixed > 32767)
    ret = 32767;
  else if (mixed < -32768)
    ret = -32768;
  else
   ret = mixed;
  return (int16_t)ret;
}

void SDL_MixAudio(uint8_t *dst, uint8_t *src, uint32_t len, int volume) {
  CallbackHelper();
  if (volume < 0) volume = 0;
  if (volume > SDL_MIX_MAXVOLUME) volume = SDL_MIX_MAXVOLUME;

  uint32_t samples = len >> 1;
  int16_t *d       = (int16_t *)dst;
  int16_t *s       = (int16_t *)src;
  for (uint32_t i = 0; i < samples; i++) {
    int32_t mixed  = d[i] + (s[i] * volume) / SDL_MIX_MAXVOLUME;
    d[i] = clip(mixed);
  }
}

SDL_AudioSpec *SDL_LoadWAV(const char *file, SDL_AudioSpec *spec, uint8_t **audio_buf, uint32_t *audio_len) {
  FILE *fp = fopen(file, "r");
  SDL_AudioSpec *ret = NULL;
  RIFF_CHUNK riff;
  FORMAT_CHUNK format;
  DATA_CHUNK data;
  fread(&riff, sizeof(RIFF_CHUNK), 1, fp);
  if (strncmp(riff.id, "RIFF", 4))
    goto error;
  if (strncmp(riff.type, "WAVE", 4))
    goto error;

  fread(&format, sizeof(FORMAT_CHUNK), 1, fp);

  if (strncmp(format.id, "fmt ", 4))
    goto error;
  if (format.byte_rate != format.channels * format.sample_rate * format.bits_per_sample / 8)
    goto error;
  if (format.block_align != format.channels * format.bits_per_sample / 8)
    goto error;
  if (format.format != 1)
    goto error;

  spec->channels = format.channels;
  spec->format   = 0x8010;
  spec->freq     = format.sample_rate;

  fread(&data, sizeof(DATA_CHUNK), 1, fp);

  if (strncmp(data.id, "data", 4))
    goto error;

  spec->size     = data.size;
  uint8_t *buf   = (uint8_t *)malloc(data.size);
  fread(buf, data.size, 1, fp);
  *audio_buf     = buf;
  *audio_len     = data.size;
  ret            = spec;
error:
  fclose(fp);
  return ret;
}

void SDL_FreeWAV(uint8_t *audio_buf) {
  if(audio_buf == NULL)
    return;
  free(audio_buf);
}

void SDL_LockAudio() {
}

void SDL_UnlockAudio() {
}
