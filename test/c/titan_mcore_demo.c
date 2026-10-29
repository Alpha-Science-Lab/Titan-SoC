#include <stdint.h>
#include "peripherals.h"

#define SPINLOCK_SCRATCHPAD    0u
#define SPINLOCK_DMEM          1u
#define SPINLOCK_IMEM          2u
#define SCRATCHPAD_REG_OFFSET  5u
#define TEST_REG_OFFSET        0u

#define DMA_NUM_BOOT_WORDS     1024u
#define DMA_CHANNEL_STRIDE     8u

#define DMA_REG_CTRL           0u
#define DMA_REG_SRC_ADDR       1u
#define DMA_REG_DST_ADDR       2u
#define DMA_REG_LEN            3u
#define DMA_REG_STATUS         4u

#define DMA_CTRL_START         (1u << 0)

#define DMA_STATUS_DONE        (1u << 1)
#define DMA_STATUS_ERROR       (1u << 2)

static inline uint32_t read_mhartid(void) {
	uint32_t hartid;
	asm volatile ("csrr %0, mhartid" : "=r"(hartid));
	return hartid;
}

static inline void acquire_spinlock(uint32_t lock_id) {
	while (SPINLOCK_ADDRESS[lock_id] != 0u) {
	}
}

static inline void release_spinlock(uint32_t lock_id) {
	SPINLOCK_ADDRESS[lock_id] = 0u;
}

static inline uint32_t dma_reg_offset(uint32_t channel, uint32_t reg) {
	return (channel * DMA_CHANNEL_STRIDE) + reg;
}

static void dma_start_copy(uint32_t channel, uint32_t src_addr, uint32_t dst_addr, uint32_t len_words) {
	BIFROST_ADDRESS[dma_reg_offset(channel, DMA_REG_SRC_ADDR)] = src_addr;
	BIFROST_ADDRESS[dma_reg_offset(channel, DMA_REG_DST_ADDR)] = dst_addr;
	BIFROST_ADDRESS[dma_reg_offset(channel, DMA_REG_LEN)] = len_words;
	BIFROST_ADDRESS[dma_reg_offset(channel, DMA_REG_CTRL)] = DMA_CTRL_START;
}

static uint32_t dma_wait_done_or_error(uint32_t channel) {
	uint32_t status;

	do {
		status = BIFROST_ADDRESS[dma_reg_offset(channel, DMA_REG_STATUS)];
	} while ((status & (DMA_STATUS_DONE | DMA_STATUS_ERROR)) == 0u);

	return status;
}

static void uart_putc(char c) {
    while (((*UART_TX_STATUS_ADDRESS >> UART_TX_STATUS_IDX_EMPTY) & 1u) == 0u) {
    }

    *UART_BUFFER_ADDRESS = (uint8_t)c;
}

static void uart_puts(const char *str) {
    while (*str != '\0') {
        uart_putc(*str++);
    }
}

static void mirror_boot_img_over_tcims(void) {
    
    // TCIMS are 4KB each, which corresponds to 1024 32-bit words
    for (uint32_t i = 0u; i < 1024u; ++i) {
        int32_t word_copied = TCIM0_ADDRESS[i];
        TCIM1_ADDRESS[i] = word_copied;
        TCIM2_ADDRESS[i] = word_copied;
        TCIM3_ADDRESS[i] = word_copied;
    }
}

static void mirror_boot_img_over_tcims_dma(void) {
    
	// CPU pointers are byte addresses; DMA expects Wishbone word addresses
	const uint32_t src = ((uint32_t)(uintptr_t)TCIM0_ADDRESS) >> 2;

	dma_start_copy(
		0u,
		src, 
		((uint32_t)(uintptr_t)TCIM1_ADDRESS) >> 2, 
		DMA_NUM_BOOT_WORDS
	);
	dma_start_copy(
		1u,
		src,
		((uint32_t)(uintptr_t)TCIM2_ADDRESS) >> 2,
		DMA_NUM_BOOT_WORDS
	);
	dma_start_copy(
		2u,
		src,
		((uint32_t)(uintptr_t)TCIM3_ADDRESS) >> 2,
		DMA_NUM_BOOT_WORDS
	);

	const uint32_t st0 = dma_wait_done_or_error(0u);
	const uint32_t st1 = dma_wait_done_or_error(1u);
	const uint32_t st2 = dma_wait_done_or_error(2u);

	if (((st0 | st1 | st2) & DMA_STATUS_ERROR) != 0u) {
		// terminate if any DMA error occurs
		TEST_ADDRESS[TEST_REG_OFFSET] = 2u;
	}
}

static void initialize_shared_data_ram(void) {

    // Shared data RAM capacity 8KB = 2048 32-bit words
    // First 1KB region: 0..255, another 1KB region: 768..1023
    for (uint32_t i = 0u; i < 256u; ++i) {
        MEMORY_ADDRESS[i] = i;
    }

    for (uint32_t i = 768u; i < 1024u; ++i) {
        MEMORY_ADDRESS[i] = (1024u - i);
    }

    // Clear the second 1KB region to leave it available for the hart-1 result
    for (uint32_t i = 256u; i < 768u; ++i) {
        MEMORY_ADDRESS[i] = 0u;
    }
}

static void bring_harts_out_of_reset_task(void) {
	// if (read_mhartid() != 0u) {
	// 	while (1) {
	// 		asm volatile ("nop");
	// 	}
	// }

	*RST_CTRL_ADDRESS = 0xFFF0u;
}

static void hart0_task(void) {
	if (read_mhartid() != 0u) {
		while (1) {
			asm volatile ("nop");
		}
	}

    // First action: seed the other TCIMs from the initialized TCIM0 image so
    // the remaining harts can boot even when their own TCIMs are not preloaded
    acquire_spinlock(SPINLOCK_IMEM);
    uart_puts("Hart 0: mirroring boot image over TCIMs\r\n");
	mirror_boot_img_over_tcims_dma();

    TEST_ADDRESS[TEST_REG_OFFSET] = 1u;
    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = 0u;

    uart_puts("Hart 0: initializing shared data RAM\r\n");
    acquire_spinlock(SPINLOCK_DMEM);
	initialize_shared_data_ram();
    release_spinlock(SPINLOCK_DMEM);

    uart_puts("Hart 0: bringing other harts out of reset\r\n");
	bring_harts_out_of_reset_task();

	while ((TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] & (0x7u << 29)) != (0x7u << 29)) {
        for (uint32_t i = 0; i < 3; i++) {
            asm volatile ("nop");
        }
    }

    uart_puts("Hart 0: all workers are done with their tasks\r\n");
    release_spinlock(SPINLOCK_IMEM);
    TEST_ADDRESS[TEST_REG_OFFSET] = 2u;

	while (1) {
		asm volatile ("nop");
	}
}

static void hart1_task(void) {
	if (read_mhartid() != 1u) {
		while (1) {
			asm volatile ("nop");
		}
	}

    for (uint32_t i = 0u; i < 256u; ++i) 
    {
        acquire_spinlock(SPINLOCK_DMEM);

        uint32_t op1 = MEMORY_ADDRESS[i];
        uint32_t op2 = MEMORY_ADDRESS[768u + i];
        uint32_t sum = op1 + op2;

        MEMORY_ADDRESS[256u + i] = sum;

        release_spinlock(SPINLOCK_DMEM);
    }

    acquire_spinlock(SPINLOCK_SCRATCHPAD);

	uint32_t scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
	scratchpad_value |= (1u << 29);

    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

    release_spinlock(SPINLOCK_SCRATCHPAD);

	while (1) {
		asm volatile ("nop");
	}
}

static void hart2_task(void) {
	if (read_mhartid() != 2u) {
		while (1) {
			asm volatile ("nop");
		}
	}

    uint32_t scratchpad_value;

    do {
        scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
    } while ((scratchpad_value & (1u << 29)) == 0u);

    for (uint32_t i = 0u; i < 256u; ++i) {

        acquire_spinlock(SPINLOCK_DMEM);

        uint32_t op1 = MEMORY_ADDRESS[i];
        uint32_t op2 = MEMORY_ADDRESS[768u + i];
        uint32_t act = MEMORY_ADDRESS[256u + i];

        release_spinlock(SPINLOCK_DMEM);

        uint32_t exp = op1 + op2;

        TEST_ADDRESS[TEST_REG_OFFSET] = act != exp ? 1u : 0u;
    }

    acquire_spinlock(SPINLOCK_SCRATCHPAD);

    scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
    scratchpad_value |= (1u << 30);
    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

    release_spinlock(SPINLOCK_SCRATCHPAD);

    while (1) {
        asm volatile ("nop");
    }
}

static void hart3_task(void) {
	if (read_mhartid() != 3u) {
		while (1) {
			asm volatile ("nop");
		}
	}

	uint8_t seen_buttons = 0u;

	while (1) {
		const uint8_t buttons = *BUTTONS_ADDRESS;
		*LEDS_ADDRESS = (uint16_t)buttons;

		for (uint8_t button_idx = 1u; button_idx <= 4u; ++button_idx) {
			if ((buttons & (1u << button_idx)) != 0u) {
				seen_buttons |= (1u << button_idx);
			}
		}

		if (seen_buttons == 0x1Eu) {
			break;
		}
	}

	acquire_spinlock(SPINLOCK_SCRATCHPAD);

	uint32_t scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
	scratchpad_value |= (1u << 31);
	TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

	release_spinlock(SPINLOCK_SCRATCHPAD);

	while (1) {
		asm volatile ("nop");
	}
}


void main(void) {

	uint32_t hart_id = read_mhartid();

	switch (hart_id) {
		case 0u:
			hart0_task();
			break;
		case 1u:
			hart1_task();
			break;
		case 2u:
			hart2_task();
			break;
		case 3u:
			hart3_task();
			break;
		default:
			while (1) {
				asm volatile ("nop");
			}
			break;
	}
}
