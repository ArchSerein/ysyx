#include <NDL.h>
#include <SDL.h>
#include <sdl-helper.h>

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

void SDL_MixAudio(uint8_t *dst, uint8_t *src, uint32_t len, int volume) {
}

SDL_AudioSpec *SDL_LoadWAV(const char *file, SDL_AudioSpec *spec, uint8_t **audio_buf, uint32_t *audio_len) {
  return NULL;
}

void SDL_FreeWAV(uint8_t *audio_buf) {
}

void SDL_LockAudio() {
}

void SDL_UnlockAudio() {
}
