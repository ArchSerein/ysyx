#include <fs.h>

typedef size_t (*ReadFn) (void *buf, size_t offset, size_t len);
typedef size_t (*WriteFn) (const void *buf, size_t offset, size_t len);

typedef struct {
  char *name;
  size_t size;
  size_t disk_offset;
  ReadFn read;
  WriteFn write;
} Finfo;

enum {FD_STDIN, FD_STDOUT, FD_STDERR, FD_EVENTS, FD_DISPINFO,
        FD_FB};

size_t invalid_read(void *buf, size_t offset, size_t len) {
  panic("invalid_read: should not reach here");
  return 0;
}

size_t invalid_write(const void *buf, size_t offset, size_t len) {
  panic("invalid_write: should not reach here");
  return 0;
}

extern size_t events_read(void *buf, size_t offset, size_t len);
extern size_t serial_write(const void *buf, size_t offset, size_t len);
extern size_t dispinfo_read(void *buf, size_t offset, size_t len);
extern size_t fb_write(const void *buf, size_t offset, size_t len);
/* This is the information about all files in disk. */
static Finfo file_table[] __attribute__((used)) = {
  [FD_STDIN]  = {"stdin", 0, 0, invalid_read, invalid_write},
  [FD_STDOUT] = {"stdout", 0, 0, invalid_read, serial_write},
  [FD_STDERR] = {"stderr", 0, 0, invalid_read, serial_write},
  [FD_EVENTS] = {"/dev/events", 0, 0, events_read, invalid_write},
  [FD_DISPINFO] = {"/proc/dispinfo", 0, 0, dispinfo_read, invalid_write},
  [FD_FB] = {"/dev/fb", 0, 0, invalid_read, fb_write},
#include "files.h"
};

#define NR_FILES (sizeof(file_table) / sizeof(file_table[0]))
size_t disk_offset_start[NR_FILES];

void init_fs() {
  // TODO: initialize the size of /dev/fb
  int w = 400;
  int h = 300;
  file_table[FD_FB].size = w * h * 4;
}

extern size_t serial_write(const void *buf, size_t offset, size_t len);
extern size_t ramdisk_write(const void *buf, size_t offset, size_t len);
int
fs_open(const char *pathname, int flags, int mode) {
  int fd = 0;
  for (fd = 0; fd < NR_FILES; fd++) {
    if (strcmp(pathname, file_table[fd].name) == 0) {
      disk_offset_start[fd] = file_table[fd].disk_offset;
      return fd;
    }
  }
  panic("no such file: %s", pathname);
  return -1;
}

size_t
fs_lseek(int fd, size_t offset, int whence) {
  switch (whence) {
    case SEEK_SET: disk_offset_start[fd] = file_table[fd].disk_offset + offset; break;
    case SEEK_CUR: disk_offset_start[fd] += offset; break;
    case SEEK_END: disk_offset_start[fd] = file_table[fd].size + file_table[fd].disk_offset; break;
    default: panic("should not reach here");
  }
  #ifdef CONFIG_STRACE
    printf("fs_lseek: change the file offset, current disk_offset->0x%x\n", disk_offset_start[fd]);
  #endif // !CONFIG_STRACE
  return disk_offset_start[fd] - file_table[fd].disk_offset;
}

extern size_t ramdisk_read(void *buf, size_t offset, size_t len);
size_t
fs_read(int fd, void *buf, size_t len) {
  size_t ret;
  if (file_table[fd].read != NULL) {
    ret = file_table[fd].read(buf, disk_offset_start[fd], len);
  }
  else {
    if (disk_offset_start[fd] + len > file_table[fd].disk_offset + file_table[fd].size) {
      len = file_table[fd].disk_offset + file_table[fd].size - disk_offset_start[fd];
    }
    ret = ramdisk_read(buf, disk_offset_start[fd], len);
    fs_lseek(fd, ret, SEEK_CUR);
  }
  #ifdef CONFIG_STRACE
    printf("fs_read: read %d bytes form the file %s\n", ret, file_table[fd].name);
  #endif // !CONFIG_STRACE
  return ret;
}

size_t
fs_write(int fd, const void *buf, size_t len) {
  size_t ret;
  if (file_table[fd].write != NULL) {
    // ret = serial_write(buf, 0, len);
    ret = file_table[fd].write(buf, disk_offset_start[fd], len);
    #ifdef CONFIG_STRACE
      printf("output %d bytes to terminal\n", ret);
    #endif // !CONFIG_STRACE
  } else {
    ret = ramdisk_write(buf, disk_offset_start[fd], len);
    fs_lseek(fd, ret, SEEK_CUR);
    #ifdef CONFIG_STRACE
      printf("output %d bytes to file %s\n", ret, file_table[fd].name);
    #endif // !CONFIG_STRACE
  }
  return ret;
}

int
fs_close(int fd) {
  #ifdef CONFIG_STRACE
    printf("fs_close: close the file %s\n", file_table[fd].name);
  #endif // !CONFIG_STRACE
  return 0;
}
