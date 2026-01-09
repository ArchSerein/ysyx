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

  for (int i = 0; i < ehdr.e_phnum; i++) {
    if (phdr[i].p_type == PT_LOAD) {
      fs_lseek(fd, phdr[i].p_offset, SEEK_SET);
      #ifdef HAS_VME
      #define RWX_PROT (0xE)
      #define RW_PROT  (0x6)
      #define ROUNDDOWN(a, sz) ((((uintptr_t)a)) & ~((sz) - 1))

      uintptr_t vaddr_start = phdr[i].p_vaddr;
      uintptr_t vaddr_end   = phdr[i].p_vaddr + phdr[i].p_memsz;
      uintptr_t file_end    = phdr[i].p_vaddr + phdr[i].p_filesz;
      uintptr_t vpage       = ROUNDDOWN(vaddr_start, PGSIZE);

      for (; vpage < vaddr_end; vpage += PGSIZE) {
        void *pa        = new_page(1);

        uintptr_t start = (vpage < vaddr_start) ? vaddr_start : vpage;
        uintptr_t npage = vpage + PGSIZE;
        uintptr_t end   = (npage < vaddr_end) ? npage : vaddr_end;

        uintptr_t p_off = start - vpage;

        if (vpage < file_end) {
          map(&pcb->as, (void *)vpage, pa, RWX_PROT);
          uintptr_t read_end = (file_end < end) ? file_end : end;
          size_t bytes_read  = read_end - start;

          assert(fs_read(fd, (void *)((uintptr_t)pa + p_off), bytes_read) == bytes_read);

          if (end > file_end) {
            size_t zero_off   = file_end - vpage;
            size_t bytes_zero = end - file_end;
            memset((void *)((uintptr_t)pa + zero_off), 0, bytes_zero);
          }
          if (p_off > 0) {
            memset(pa, 0, p_off);
          }
        } else {
          map(&pcb->as, (void *)vpage, pa, RW_PROT);
          memset(pa, 0, PGSIZE);
        }
      }
      pcb->max_brk = ROUNDUP(vaddr_end, PGSIZE);
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
