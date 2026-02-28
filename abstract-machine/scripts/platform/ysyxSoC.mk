AM_SRCS := riscv/ysyxSoC/start.S \
		   riscv/ysyxSoC/trap.S \
           riscv/ysyxSoC/trm.c \
		   riscv/ysyxSoC/ioe.c \
		   riscv/ysyxSoC/timer.c \
           riscv/ysyxSoC/vme.c \
           platform/dummy/mpe.c \
		   riscv/ysyxSoC/cte.C

CFLAGS    += -fdata-sections -ffunction-sections
LDFLAGS   += -T $(AM_HOME)/scripts/ysyxSoClinker.ld \
						 --defsym=_pmem_start=0x30000000 --defsym=_entry_offset=0x0
LDFLAGS   += --gc-sections -e _start
CFLAGS += -DMAINARGS=\"$(mainargs)\"
.PHONY: $(AM_HOME)/am/src/riscv/ysyxSoC/trm.c

image: $(IMAGE).elf
	@$(OBJDUMP) -d $(IMAGE).elf > $(IMAGE).txt
	@echo + OBJCOPY "->" $(IMAGE_REL).bin
	@$(OBJCOPY) -S --set-section-flags .bss=alloc,contents \
	--set-section-flags .bss.extra=alloc,contents -O binary \
	-j .ftext -j .text -j .rodata -j .data.extra -j .data \
	-j .ssbl $(IMAGE).elf $(IMAGE).bin

run: image
	$(MAKE) -C $(NPC_HOME) ISA=$(ISA) ARCH=$(ARCH) run IMG=$(IMAGE).bin

gdb: image
	$(MAKE) -C $(NPC_HOME) ISA=$(ISA) gdb IMG=$(IMAGE).bin
