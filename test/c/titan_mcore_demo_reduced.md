# Reduced Multicore Execution Demo

## **Goal**

This is a deliberately simpler multicore test than the original DMA-driven demo.
The purpose is to validate the core startup/reset flow and the hart-dispatch logic without introducing DMA traffic or any complex shared-memory synchronization.

The key constraints are:
- no DMA is used
- all TCIMs are initialized from the same `init.mem`
- every hart executes the same binary image
- each hart reads `mhartid` after reset and jumps to its own task
- only hart 0 releases the other harts from reset
- each worker hart signals readiness by setting one scratchpad bit using a read-modify-write sequence under a spinlock
- hart 0 polls the scratchpad and terminates the simulation when `scratchpad[31:29] == 3'b111`

**Important scratchpad rule:** the test peripheral scratchpad is a 32-bit register, so a write replaces the entire word.

Any update of just one bit must therefore be done as a **load/store** sequence: read current value, set or clear the desired bits, write the result back. This update sequence must be guarded by the **spinlock** peripheral. A plain scratchpad read is safe without a lock; the lock is required only for **read-modify-write** updates.

**Spinlock acquire rule:** the lock is acquired by reading the lock register in a polling loop. If the read returns non-zero, another hart already owns the lock and the current hart must retry until it sees `0`, which means it has acquired the lock. Only then is it safe to read-modify-write the scratchpad and release the lock with a write of `0`.

---

## **1. Memory model**

The test image is loaded into every TCIM in the same way:
- TCIM0, TCIM1, TCIM2, and TCIM3 all receive the same memory image
- there is no DMA copy stage
- the same code runs on all harts, but a hart-specific branch is taken according to `mhartid`

This is intentionally simple and keeps the focus on reset sequencing and hart identity rather than data movement.

---

## **2. Boot and reset flow**

At power-up or test start:
- harts 1, 2, and 3 remain in reset
- hart 0 is active and begins execution immediately
- hart 0 reads `mhartid` and identifies itself as hart 0
- hart 0 writes to the reset controller to deassert reset for harts 1, 2, and 3
- after that, the other harts come out of reset and begin execution

The reset controller is therefore the single boot gate for the multicore system.

---

## **3. Hart dispatch**

All harts begin from the same entry point, but each one branches based on `mhartid`:

- hart 0: master/monitor hart
- hart 1: worker 1
- hart 2: worker 2
- hart 3: worker 3

The dispatch pattern is:

```c
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
```

---

## **4. Hart 3 behavior**

Hart 3 does the following once it exits reset:

1. read `mhartid`
2. confirm it is hart 3
3. set `scratchpad[31] = 1`
4. enter an infinite no-op loop


Pseudo-code:

```c
void hart3_task(void)
{
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
```

---

## **5. Hart 2 behavior**

Hart 2 does the following once it exits reset:

1. read `mhartid`
2. confirm it is hart 2
3. set `scratchpad[30] = 1`
4. enter an infinite no-op loop

Pseudo-code:

```c
void hart2_task(void)
{
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
```

---

## **6. Hart 1 behavior**

Hart 1 does the following once it exits reset:

1. read `mhartid`
2. confirm it is hart 1
3. set `scratchpad[29] = 1`
4. enter an infinite no-op loop

Pseudo-code:

```c
void hart1_task(void)
{
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
```

---

## **7. Hart 0 behavior**

Hart 0 is the master monitor. Its actions are:

1. read `mhartid` and confirm it is hart 0
2. write to the reset controller to bring harts 1, 2, and 3 out of reset
3. continuously read the scratchpad register
4. watch for the combined status bits `scratchpad[31:29] == 3'b111`
5. when that pattern is seen, terminate the simulation by writing `2` to the test register
6. otherwise stay in a tight polling loop

The intended signal pattern is:
- hart 3 sets bit 31
- hart 2 sets bit 30
- hart 1 sets bit 29

The worker bits therefore act as a combined-ready mask. The master hart checks the 3-bit field as a whole instead of looking for only the MSB.

Pseudo-code:

```c
void hart0_task(void)
{
    if (read_mhartid() != 0u) {
        while (1) {
            asm volatile ("nop");
        }
    }

    TEST_ADDRESS[TEST_REG_OFFSET] = 1u;
    TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] = 0u;

    bring_harts_out_of_reset_task();

    while (1) {
        if ((TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] & WORKER_READY_MASK) == WORKER_READY_MASK) {
            break;
        }

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
```

This matches the requirement: the simulation is ended once `scratchpad[31:29] == 3'b111`, by writing `2` to the test register. The worker-only status updates are serialized with the spinlock; the monitor hart only reads the scratchpad, so it does not need to acquire the lock.

---

## **8. Termination condition**

The test terminates when the scratchpad indicates that all three worker cores have reached the signaled state.

In the reduced test, the intended completion pattern is:
- `scratchpad[29] = 1` from hart 1
- `scratchpad[30] = 1` from hart 2
- `scratchpad[31] = 1` from hart 3

The monitor hart checks the combined condition:

```c
if ((TEST_ADDRESS[SCRATCHPAD_REG_OFFSET] & WORKER_READY_MASK) == WORKER_READY_MASK) {
    TEST_ADDRESS[TEST_REG_OFFSET] = 0u;
    TEST_ADDRESS[TEST_REG_OFFSET] = 2u;
}
```

This is equivalent to `scratchpad[31:29] == 3'b111`.

This acts as the end-of-test trigger for the simulation environment.

---

## **9. Summary of the reduced design**

This test keeps the multicore hardware checks while removing all the extra complexity:
- no DMA
- no shared data RAM workload
- no inter-core arithmetic handshakes
- no button/LED activity
- no UART reporting loop
- no extra interrupt choreography

The reduced design validates only the startup and coordination behavior:
- uniform image loaded in all TCIMs
- per-hart branch on `mhartid`
- reset gating of harts 1..3 by hart 0
- scratchpad signaling by each worker
- simulation termination controlled by hart 0

This makes the test easy to debug and suitable as a first multicore smoke test before adding more complex application logic.

The one important hardware contract to preserve in all later C code is: a scratchpad write is a **full-register store**, not a masked bit-set, so every update must be implemented as a **read-modify-write** sequence; when the update is not a read-only check, the sequence must be enclosed in the **spinlock** peripheral to prevent multiple harts from clobbering each other's bits.
