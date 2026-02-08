#include <am.h>
#include <klib-macros.h>
#include <klib.h>

#define UART_BASE 0x10000000L
#define UART_TX 0x00
#define UART_RX 0x00
#define UART_IER 0x01
#define UART_FCR 0x02
#define UART_LCR 0x03
#define UART_LSR 0x05
// divisor
#define UART_MSB 0x01
#define UART_LSB 0x00
#define UART_OUTPUT_PORT (UART_BASE + UART_TX)
#define UART_INPUT_PORT (UART_BASE + UART_RX)

#ifndef MAINARGS
#define MAINARGS ""
#endif
static const char mainargs[] = MAINARGS;
int main(const char *args);

#define _heap_end (0x80000000 + 0x400000)

extern char _heap_start[];
Area heap = RANGE(_heap_start, _heap_end);
void *addr = (void *)_heap_start;

#define LCR_BAUD_LATCH (1 << 7)
#define LCR_EIGHT_BITS (3 << 0)
static void _uart_init() {
  // 关闭中断
  *(volatile char *)(UART_BASE + UART_IER) = 0x00;

  // 设置 DLAB=1 以配置波特率
  *(volatile char *)(UART_BASE + UART_LCR) = LCR_BAUD_LATCH;

  // 设置波特率分频值
  *(volatile char *)(UART_BASE + UART_MSB) = 0x00; // 高字节
  *(volatile char *)(UART_BASE + UART_LSB) = 0x01; // 低字节

  // 设置 8 位数据，无校验，1 停止位，并清除 DLAB
  *(volatile char *)(UART_BASE + UART_LCR) = LCR_EIGHT_BITS;

  // 重置和使能 FIFO
  *(volatile char *)(UART_BASE + UART_FCR) = 0x07;
}

#define LSR_TX_IDLE (1 << 5) // THR can accept another character to send
void putch(char ch) {
  while ((*(volatile char *)(UART_BASE + UART_LSR) & LSR_TX_IDLE) == 0)
    ;
  *(volatile char *)(UART_OUTPUT_PORT) = ch;
}
#define LSR_RX_READY (1 << 0) // Receive data is ready
uint8_t getch() {
  if ((*(volatile uint8_t *)(UART_BASE + UART_LSR) & LSR_RX_READY) == 0) {
    return 0xff;
  } else {
    uint8_t data = *(volatile uint8_t *)(UART_INPUT_PORT);
    return data;
  }
}

#define SPI_BASE 0x10001000
#define SPI_DIV 0x14
#define SPI_CTRL 0x10
#define SPI_SS 0x18
#define SPI_RX0 0x0
#define SPI_TX1 0x4
#define GO_BSY (1 << 8)

#define FLASH_READ 0x03
#define FLASH_CMD_MASK(addr) ((FLASH_READ << 24) | (addr & 0x00ffffff))
#define SET_FLASH_MODE(mode)                                                   \
  (*(volatile uint32_t *)(SPI_BASE + SPI_CTRL) = mode)
#define CONFIG_SS(ss) (*(volatile uint32_t *)(SPI_BASE + SPI_SS) = ss)

static uint32_t invert_endian(uint32_t data) {
  return ((data & 0xff) << 24) | ((data & 0xff00) << 8) |
         ((data & 0xff0000) >> 8) | ((data & 0xff000000) >> 24);
}
uint32_t flash_read(uint32_t addr) {
  *(volatile uint32_t *)(SPI_BASE + SPI_TX1) = FLASH_CMD_MASK(addr);
  *(volatile uint32_t *)(SPI_BASE + SPI_DIV) = 0x1;
  CONFIG_SS(1 << 0);
  SET_FLASH_MODE(0x40);
  *(volatile uint32_t *)(SPI_BASE + SPI_CTRL) |= GO_BSY;
  while (*(volatile uint32_t *)(SPI_BASE + SPI_CTRL) & GO_BSY)
    ;
  CONFIG_SS(0);
  uint32_t data = *(volatile uint32_t *)(SPI_BASE + SPI_RX0);
  printf("flash_read: 0x%08x\tdata: 0x%08x\n", addr, invert_endian(data));
  return invert_endian(data);
}

void halt(int code) {
  asm volatile("mv a0, %0" : : "r"(code));
  asm volatile("ebreak");
  while (1)
    ;
}

void _ssbl();
__attribute__((section("fsbl"))) __attribute__((used)) void _fsbl() {
  extern char _ssbl_start[];
  extern char _load_ssbl_size[], _load_ssbl_start[];
  for (size_t i = 0; i < (size_t)_load_ssbl_size; i++) {
    *(_ssbl_start + i) = *(_load_ssbl_start + i);
  }
  _ssbl();
}

// 放入 .ssbl 段
void _trm_init();
__attribute__((section("ssbl"))) __attribute__((used)) void _ssbl() {
  extern char _data_start[], _etext_start[], _rodata_start[];
  extern char _data_end[], _etext_end[], _rodata_end[];
  extern char _data_extra_start[], _data_extra_end[];
  extern char _load_data_start[];
  extern char _load_etext_start[];
  extern char _load_rodata_start[];
  extern char _load_data_extra_start[];
  const size_t _load_data_size = _data_end - _data_start;
  const size_t _load_etext_size = _etext_end - _etext_start;
  const size_t _load_rodata_size = _rodata_end - _rodata_start;
  const size_t _load_data_extra_size = _data_extra_end - _data_extra_start;
  for (size_t i = 0; i < _load_etext_size; i++) {
    *(_etext_start + i) = *(_load_etext_start + i);
  }
  for (size_t i = 0; i < _load_rodata_size; i++) {
    *(_rodata_start + i) = *(_load_rodata_start + i);
  }
  for (size_t i = 0; i < _load_data_size; i++) {
    *(_data_start + i) = *(_load_data_start + i);
  }
  for (size_t i = 0; i < _load_data_extra_size; i++) {
    *(_data_extra_start + i) = *(_load_data_extra_start + i);
  }
  asm volatile("fence.i" ::: "memory");
  _trm_init();
}

__attribute__((used))
static void info() {
    uint32_t mvendorid, marchid;
    // 读取 mvendorid 寄存器（地址 0xF11）
    asm volatile(
        "csrr %0, 0xf11"  // 读取 mvendorid 寄存器到 mvendorid 变量
        : "=r"(mvendorid)  // 输出操作数，将结果放入 mvendorid
    );

    // 读取 marchid 寄存器（地址 0xF12）
    asm volatile(
        "csrr %0, 0xf12"  // 读取 marchid 寄存器到 marchid 变量
        : "=r"(marchid)    // 输出操作数，将结果放入 marchid
    );
    printf("%s_%d\n", &mvendorid, marchid);
    asm volatile("sw %0, 0(%1)" : : "r"(marchid), "r"(0x10002008));
    // uint32_t pass = 0;
    // while (pass != 0x0f) {
    //     asm volatile("lw %0, 0(%1)" : "=r"(pass) : "r"(0x10002004));
    // }
    printf("welcome to my riscv npc!\n");
}

void _trm_init() {
  _uart_init();
  info();
  int ret = main(mainargs);
  halt(ret);
}
