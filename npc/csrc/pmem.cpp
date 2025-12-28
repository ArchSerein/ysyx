#include <cstdint>
#include "pmem.hpp"
#include <iostream>
#include <cassert>
#include <cstring>
#include <chrono>
#include "defs.hpp"
#include "debug.hpp"
#include "difftest.hpp"

#define MASK(addr) ((addr) & (~0x03u))

uint8_t *sram = NULL;
uint8_t *mrom = NULL;
uint8_t *flash = NULL;
uint8_t *psram = NULL;
uint8_t *sdram = NULL;
uint8_t *pmem = NULL;

uint8_t* mrom_to_host(uint32_t paddr) { return mrom + paddr - CONFIG_MROM_BASE; }
uint8_t* sram_to_host(uint32_t paddr) { return sram + paddr - CONFIG_SRAM_BASE; }
uint8_t* flash_to_host(uint32_t paddr) { return flash + paddr; }
uint8_t* psram_to_host(uint32_t paddr) { return psram + paddr; }
uint8_t* sdram_to_host(uint32_t paddr) { return sdram + paddr; }
uint8_t* guest_to_host(uint32_t paddr) { return pmem + paddr - CONFIG_MBASE; }

long init_mem(char *path) {
    mrom = (uint8_t *)aligned_alloc(32, CONFIG_MROM_SIZE);
    sram = (uint8_t *)aligned_alloc(32, CONFIG_SRAM_SIZE);
    flash = (uint8_t *)aligned_alloc(32, CONFIG_FLASH_SIZE);
    psram = (uint8_t *)aligned_alloc(32, CONFIG_PSRAM_SIZE);
    sdram = (uint8_t *)aligned_alloc(32, CONFIG_SDRAM_SIZE);
    if (mrom == NULL || sram == NULL || flash == NULL ||
        psram == NULL || sdram == NULL) {
        Log("mem init fail, exit now\n");
        exit(1);
    }
    if(path == NULL)
    {
        printf("No image is given, exit now\n");
        exit(0);
    }

    FILE *fp = fopen(path, "rb");
    if(!fp)
    {
        printf("open image fail, exit now\n");
        exit(1);
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);

    fseek(fp, 0, SEEK_SET);
    int ret;
    ret = fread(flash, size, 1, fp);
    assert(ret == 1);
    Log("load image size: 0x%08lx", size);

    fclose(fp);

    Log("mem initalization complete");
    return size;
}

extern "C" int pmem_read(int raddr) {
    if (raddr == 0xa0000048)
        return  (int)(std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::system_clock::now().time_since_epoch()).count());
    if (raddr == 0xa000004c)
        return (int)(std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::system_clock::now().time_since_epoch()).count() >> 32) ;
    uint32_t vaddr = (uint32_t)(raddr & ~0x3u);
    uint8_t *paddr = guest_to_host(vaddr);

    uint32_t data = *(uint32_t *)paddr;
    #ifdef CONFIG_MTRACE
        printf("pmem_read-> addr: %08x data: %08x\n", raddr, data);
    #endif // CONFIG_MTRACE
    return data;
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    if (waddr == 0xa00003f8) {
        #ifdef CONFIG_DIFFTEST
            difftest_skip_ref(1);
        #endif // CONFIG_DIFFTEST
        printf("%c", wdata & 0xff);
        fflush(stdout);
        return;
    }
    uint32_t vaddr = (uint32_t)(waddr & ~0x3u);
    uint8_t *paddr = guest_to_host(vaddr);
    uint32_t rdata = *(uint32_t *)paddr;
    switch(wmask)
    {
        case 0x0f:
            *(uint32_t *)paddr = wdata;
            break;
        case 0x0c:
            *(uint32_t *)paddr = (wdata & 0xffff0000) | (rdata & 0x0000ffff);
            break;
        case 0x08:
            *(uint32_t *)paddr = (wdata & 0xff000000) | (rdata & 0x00ffffff);
            break;
        case 0x04:
            *(uint32_t *)paddr = (wdata & 0x00ff0000) | (rdata & 0xff00ffff);
            break;
        case 0x03:
            *(uint32_t *)paddr = (wdata & 0x0000ffff) | (rdata & 0xffff0000);
            break;
        case 0x02:
            *(uint32_t *)paddr = (wdata & 0x0000ff00) | (rdata & 0xffff00ff); 
            break;
        case 0x01:
            *(uint32_t *)paddr = (wdata & 0x000000ff) | (rdata & 0xffffff00);
            break;
        default:
            printf("paddr_write fault waddr: %x\n", vaddr);
    }

    uint32_t update_data = *(uint32_t *)paddr;
    // mtrace
    #ifdef CONFIG_MTRACE
        printf("pmem_write-> addr: %08x origin_data: %08x wdata: %08x update_data: %08x wmask: %08x\n",\
                                vaddr, rdata, wdata, update_data, wmask);
    #endif // CONFIG_MTRACE
}

extern "C" int inst_read(int vaddr) {
    uint8_t *paddr = guest_to_host((uint32_t)vaddr);

    #ifdef CONFIG_MTRACE
        printf("inst_read: %08x %08x\n", vaddr, *(uint32_t *)paddr);
    #endif // CONFIG_MTRACE
    return *(uint32_t *)paddr;
}

extern "C" uint32_t vaddr_read(uint32_t addr, int len) {
    uint8_t *paddr = guest_to_host((uint32_t)addr);
    switch(len)
    {
        case 1:
            return (uint32_t)*(uint8_t *)paddr;
        case 2:
            return (uint32_t)*(uint16_t *)paddr;
        case 4:
            return (uint32_t)*(uint32_t *)paddr;
        default:
            assert(0);
    }
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
    if ((uint32_t)addr >= CONFIG_FLASH_SIZE) {
        Log("flash_read: 0x%08x out of range", addr);
        *data = -1;
        return;
    }

    uint8_t *paddr;
    paddr = flash_to_host((uint32_t)MASK(addr));
    #ifdef CONFIG_MTRACE
        Log("flash_read: %08x %08x", addr, *(int32_t *)paddr);
    #endif // CONFIG_MTRACE
    *data = *(int32_t *)paddr;
}
extern "C" void mrom_read(int32_t addr, int32_t *data) {
    if ((uint32_t)addr >= CONFIG_MROM_BASE + CONFIG_MROM_SIZE ||
        (uint32_t)addr < CONFIG_MROM_BASE) {
        Log("mrom_read: 0x%08x out of range", addr);
        *data = -1;
        return;
    }

    uint8_t *paddr;
    paddr = mrom_to_host((uint32_t)MASK(addr));
    #ifdef CONFIG_MTRACE
        Log("mrom_read: %08x %08x", addr, *(int32_t *)paddr);
    #endif // CONFIG_MTRACE
    *data = *(int32_t *)paddr;
}

extern "C" void psram_read(int32_t addr, int32_t *data) {
    uint8_t *paddr;
    paddr = psram_to_host((uint32_t)(addr));
    #ifdef CONFIG_MTRACE
        Log("psram_read: %08x %08x", addr, *(int32_t *)paddr);
    #endif // CONFIG_MTRACE
    *data = *(int32_t *)paddr;
}

extern "C" void psram_write(int32_t addr, int8_t data) {
    uint8_t *paddr;
    paddr = psram_to_host((uint32_t)(addr));
    #ifdef CONFIG_MTRACE
        Log("psram_write: %08x %02x", addr, data);
    #endif // CONFIG_MTRACE
    *(int8_t *)paddr = data;
}

extern "C" void sdram_read(int32_t addr, int32_t *data) {
    uint8_t *paddr;
    paddr = sdram_to_host((uint32_t)addr);
    *data = *(int32_t *)paddr & 0xffff;
    #ifdef CONFIG_MTRACE
        Log("sdram_read: addr: 0x%x data: 0x%x", addr, *data);
    #endif // CONFIG_MTRACE
}

extern "C" void sdram_write(int32_t addr, uint8_t mask, int32_t data) {
    uint8_t *paddr;
    paddr = sdram_to_host((uint32_t)addr);
    #ifdef CONFIG_MTRACE
        Log("sdram_write: addr: 0x%x mask: 0x%x data: 0x%x", addr, mask, data);
    #endif // CONFIG_MTRACE
    switch (mask) {
        case 0x02:
            *(int16_t *)paddr = *(int16_t *)paddr & 0xff00 | (data & 0x00ff);
            break;
        case 0x01:
            *(int16_t *)paddr = *(int16_t *)paddr & 0x00ff | (data & 0xff00);
            break;
        case 0x00:
            *(int16_t *)paddr = data & 0xffff;
            break;
        case 0x03:
            break;
        default:
            printf("sdram_write fault mask: %x\n", mask);
            break;
    }
}

void free() {
    free(mrom);
    free(sram);
    free(flash);
    free(psram);
    free(sdram);
}

