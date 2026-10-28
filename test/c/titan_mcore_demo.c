#include <stdint.h>
#include "peripherals.h"

#define SPINLOCK_SCRATCHPAD    0u
#define SPINLOCK_DMEM          1u
#define SPINLOCK_IMEM          2u
#define SCRATCHPAD_REG_OFFSET  5u
#define TEST_REG_OFFSET        0u

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
    mirror_boot_img_over_tcims();

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
