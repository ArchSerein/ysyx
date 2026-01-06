#include <proc.h>
#include <elf.h>
#include <fs.h>

#ifdef __LP64__
# define Elf_Ehdr Elf64_Ehdr
# define Elf_Phdr Elf64_Phdr
#else
# define Elf_Ehdr Elf32_Ehdr
# define Elf_Phdr Elf32_Phdr
#endif

extern size_t ramdisk_read(void *buf, size_t offset, size_t len);
extern size_t fs_open(const char *pathname, int flags, int mode);
extern size_t fs_read(int fd, void *buf, size_t len);
extern size_t fs_lseek(int fd, size_t offset, int whence);
extern int    fs_close(int fd);
static uintptr_t loader(PCB *pcb, const char *filename) {
  int fd = fs_open(filename, 0, 0);
  if (fd < 0) {
    panic("should not reach here");
  }
  Elf_Ehdr ehdr;

  assert(fs_read(fd, &ehdr, sizeof(ehdr)) == sizeof(ehdr));

  #if defined(__ISA_AM_NATIVE__)
  # define EXPECT_TYPE EM_X86_64
  #elif defined(__ISA_X86__)
  # define EXPECT_TYPE EM_386
  #elif defined(__ISA_RISCV32__) || defined(__ISA_RISCV64__)
  # define EXPECT_TYPE EM_RISCV
  #elif defined(__ISA_MIPS32__)
  # define EXPECT_TYPE EM_MIPS
  #else
  # error Unsupported ISA
  #endif

  assert(*(uint32_t *)&ehdr.e_ident == 0x464c457f);
  assert(ehdr.e_machine == EXPECT_TYPE);

  // uint32_t base;
  // base = fs_lseek(fd, 0, SEEK_CUR);

  fs_lseek(fd, ehdr.e_phoff, SEEK_SET);

  Elf_Phdr phdr[ehdr.e_phnum];
  size_t phdr_size = fs_read(fd, phdr, sizeof(Elf_Phdr) * ehdr.e_phnum);
  assert(phdr_size == sizeof(Elf_Phdr) * ehdr.e_phnum);

  size_t bytes_read = 0;
  for (int i = 0; i < ehdr.e_phnum; i++) {
    if (phdr[i].p_type == PT_LOAD) {
      fs_lseek(fd, phdr[i].p_offset, SEEK_SET);
      #ifdef HAS_VME
      #define RWX_PROT (0xE)
      Elf32_Word j = 0;
      for ( ; j < phdr[i].p_filesz; j += PGSIZE) {
        bytes_read = phdr[i].p_filesz - j < PGSIZE ? phdr[i].p_filesz - j : PGSIZE;
        void *pa = new_page(1);
        map(&pcb->as, (void *)(phdr[i].p_vaddr + j), pa, RWX_PROT);
        assert(fs_read(fd, pa, bytes_read) == bytes_read);
        if (bytes_read < PGSIZE) {
          pa = (void *)((uintptr_t)pa + bytes_read);
          size_t len = PGSIZE - bytes_read;
          memset(pa, 0, len);
        }
      }
      for ( ; j < phdr[i].p_memsz; j += PGSIZE) {
        void *pa = new_page(1);
        map(&pcb->as, (void *)(phdr[i].p_vaddr + j), pa, RWX_PROT);
        memset(pa, 0, PGSIZE);
      }
      #else
      assert(fs_read(fd, (void *)phdr[i].p_vaddr, phdr[i].p_filesz) == phdr[i].p_filesz);
      if (phdr[i].p_filesz < phdr[i].p_memsz)
        memset((void *)(phdr[i].p_vaddr + phdr[i].p_filesz), 0, phdr[i].p_memsz - phdr[i].p_filesz);
      #endif
    }
  }
  assert(fs_close(fd) == 0);
  return ehdr.e_entry;
}

void naive_uload(PCB *pcb, const char *filename) {
  uintptr_t entry = loader(pcb, filename);
  Log("Jump to entry = %p", entry);
  ((void(*)())entry) ();
}

uintptr_t uload(PCB *pcb, const char *filename) {
  uintptr_t entry = loader(pcb, filename);
  Log("Jump to entry = %p", entry);
  return entry;
}
