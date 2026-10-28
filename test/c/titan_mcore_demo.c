#include <stdint.h>
#include "peripherals.h"

#define SPINLOCK_ID            0u
#define TEST_REG_OFFSET        0u
#define SCRATCHPAD_REG_OFFSET  5u
#define WORKER_READY_MASK       (0x7u << 29)

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

    TEST_ADDRESS[TEST_REG_OFFSET] = 1u;
    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = 0u;

	bring_harts_out_of_reset_task();

	while ((TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] 
        & WORKER_READY_MASK) != WORKER_READY_MASK) {
        for (uint32_t i = 0; i < 3; i++) {
            asm volatile ("nop");
        }
    }

    TEST_ADDRESS[TEST_REG_OFFSET] = 0u;
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

    acquire_spinlock(SPINLOCK_ID);

	uint32_t scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
	scratchpad_value |= (1u << 29);

    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

    release_spinlock(SPINLOCK_ID);

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

    acquire_spinlock(SPINLOCK_ID);

	uint32_t scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
	scratchpad_value |= (1u << 30);

    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

    release_spinlock(SPINLOCK_ID);

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

    acquire_spinlock(SPINLOCK_ID);

	uint32_t scratchpad_value = TEST_ADDRESS[SCRATCHPAD_REG_OFFSET];
	scratchpad_value |= (1u << 31);

    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = scratchpad_value;

    release_spinlock(SPINLOCK_ID);

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
