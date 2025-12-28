#include <NDL.h>
#include <SDL.h>
#include <string.h>

#define keyname(k) #k,

static const char *keyname[] = {
  "NONE",
  _KEYS(keyname)
};
uint8_t keystate[sizeof(keyname) / sizeof(keyname[0])] = {0};

int SDL_PushEvent(SDL_Event *ev) {
  return 0;
}

int SDL_PollEvent(SDL_Event *ev) {
  char buf[64];
  if (NDL_PollEvent(buf, sizeof(buf)) == 0)
    return 0;
  char keydown[4];
  char keycode[12];
  sscanf(buf, "%s %s", keydown, keycode);
  if (strcmp(keydown, "kd") == 0) {
    ev->type = SDL_KEYDOWN;
  } else {
    ev->type = SDL_KEYUP;
  }

  for (int i = 0; i < sizeof(keyname) / sizeof(keyname[0]); i++) {
    if (strcmp(keyname[i], keycode) == 0) {
      ev->key.keysym.sym = i;
      keystate[i] = (ev->type == SDL_KEYDOWN) ? 1 : 0;
      break;
    }
  }
  return 1;
}

int SDL_WaitEvent(SDL_Event *event) {
  char buf[64];
  while(NDL_PollEvent(buf, sizeof(buf)) == 0)
    ;
  char keydown[4];
  char keycode[12];
  sscanf(buf, "%s %s", keydown, keycode);
  if (strcmp(keydown, "kd") == 0) {
    event->type = SDL_KEYDOWN;
  } else {
    event->type = SDL_KEYUP;
  }

  for (int i = 0; i < sizeof(keyname) / sizeof(keyname[0]); i++) {
    if (strcmp(keyname[i], keycode) == 0) {
      event->key.keysym.sym = i;
      break;
    }
  }

  return 0;
}

int SDL_PeepEvents(SDL_Event *ev, int numevents, int action, uint32_t mask) {
  return 0;
}

uint8_t* SDL_GetKeyState(int *numkeys) {
  if (numkeys) {
    *numkeys = sizeof(keyname) / sizeof(keyname[0]);
  }
  return keystate;
}
